/* eslint-disable no-console */
/**
 * migrate-local-sqlite-to-prod.ts
 *
 * One-shot, idempotent migration of legacy LOCAL data → PROD Postgres + R2 (Cloudflare).
 * Companion of scripts/backfill-dev-community-r2.ts (that one backfills PROD poses→R2;
 * this one moves legacy SQLite rows → PROD DB and any real local image files → R2).
 *
 * DESIGN CONTRACT
 * ---------------
 * - DEFAULT MODE IS DRY-RUN: the script NEVER writes anything (DB or R2) unless
 *   --apply is passed. PO approval is required before any --apply run.
 * - Idempotent: INSERT ... ON CONFLICT (id) DO NOTHING everywhere; R2 uploads skip
 *   objects that already exist (HEAD). Re-running never duplicates or overwrites.
 * - Protected poses are NEVER modified/deleted; any row whose id is in the protected
 *   or excluded sets is skipped even if it exists in a source DB (belt & braces).
 * - No secrets are ever printed or written to the ledger. api_key values are only
 *   recorded as SHA-256 hashes.
 * - Sources (canonical local), resolved relative to --repo-root (default cwd):
 *     data/local.db      → api_keys            (new schema, canonical)
 *     data/keys.db       → request_logs        (history)
 *     .docker-persist/data/keys.db → extraction_jobs (dev-stack runs)
 *     data/dev.db        → community_poses     (EXCLUDED by default: junk "Test Pose")
 *     data/community, .docker-persist/data/community, .docker-data/community
 *                        → local image files to upload to R2 (currently empty)
 * - Junk policy (defaults; flags to override):
 *     community_poses        skipped unless --include-test-data
 *     extraction_jobs        only status='succeeded' migrated unless --include-failed-jobs
 *     app_settings           never migrated by this script (runtime config, not data)
 * - LEDGER: written to docs/evidence/<name>.json even in dry-run mode. Contains
 *   per-source counts and per-item results (id + sha256 of payload + outcome). No
 *   secrets, no base64 payloads.
 *
 * USAGE (from repo root; env from the PROD Railway service):
 *   export DATABASE_URL ADMIN_SECRET R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET R2_PUBLIC_URL
 *   ./node_modules/.bin/tsx web/services/pose-extract-server/scripts/migrate-local-sqlite-to-prod.ts            # dry-run
 *   ... --apply   # real migration (requires BOTH --apply AND env MIGRATE_CONFIRM=1, see below)
 *   Options: --include-test-data, --include-failed-jobs, --repo-root <dir>, --ledger <path>
 */

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";

import postgres from "postgres";

import { getEnv } from "../src/config/env";
import { buildCommunityObjectKey, buildPublicUrl, objectExists, uploadObject } from "../src/services/r2Storage";

// ─────────────────────────────────────────────────────────────────────────────
// Constants — protected / excluded ids. NEVER modified, deleted, or recreated.
// ─────────────────────────────────────────────────────────────────────────────
const PROTECTED_POSE_IDS = new Set([
  "a43838f4-312d-4ea7-9a05-6f7c191fd691", // Seated Raising Glass — protected
  "e41fed67-90cf-40b6-9ddc-c1727afa054d" //  Seated Eating Pizza — protected
]);
const EXCLUDED_POSE_IDS = new Set(["5f671bf2" /* legacy bad-sunset pose */]);
const EXCLUDED_JOB_IDS = new Set(["6faf7f58" /* do not reuse this job */]);
const LEGACY_OWNER = "00000000-0000-0000-0000-000000000000"; // nil UUID = legacy owner (see schema.sql)

type DbTableRow = Record<string, unknown>;

interface SourceSpec {
  label: string;
  path: string;
  table: string;
  where?: string;
}

interface LedgerItem {
  source: string;
  kind: "api_key" | "request_log" | "extraction_job" | "community_pose" | "media_asset" | "local_file";
  id: string;
  hash: string;
  outcome: "inserted" | "skipped-existing" | "skipped-protected" | "skipped-excluded" | "skipped-junk" | "uploaded" | "dry-run";
  note?: string;
}

interface DryRunPlan {
  api_keys: number;
  request_logs: number;
  extraction_jobs: number;
  community_poses: number;
  local_files: number;
  skipped_junk: number;
  skipped_protected: number;
}

// ─────────────────────────────────────────────────────────────────────────────
// Small helpers — no external sqlite dependency (uses sqlite3 CLI with -json).
// ─────────────────────────────────────────────────────────────────────────────
function sqliteJson(dbPath: string, sql: string): DbTableRow[] {
  const out = execFileSync("sqlite3", ["-json", dbPath, sql], { encoding: "utf8", maxBuffer: 512 * 1024 * 1024 });
  return JSON.parse(out) as DbTableRow[];
}

function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex").slice(0, 32);
}

function md5(value: string): string {
  return createHash("md5").update(value).digest("hex");
}

/** Same deterministic UUID derivation as schema.sql's compatibility migration. */
function mediaUuid(poseId: string, role: string): string {
  const h = md5(`${poseId}:${role}`);
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20, 32)}`;
}

function parseArgs(argv: string[]): Record<string, string | boolean> {
  const flags: Record<string, string | boolean> = { apply: false, includeTestData: false, includeFailedJobs: false };
  for (const arg of argv) {
    if (arg === "--apply") flags.apply = true;
    else if (arg === "--include-test-data") flags.includeTestData = true;
    else if (arg === "--include-failed-jobs") flags.includeFailedJobs = true;
    else if (arg.startsWith("--repo-root=")) flags.repoRoot = arg.slice("--repo-root=".length);
    else if (arg.startsWith("--ledger=")) flags.ledger = arg.slice("--ledger=".length);
  }
  return flags;
}

function normalizeTs(value: unknown): string | null {
  if (value == null) return null;
  const s = String(value).trim();
  if (!s) return null; // why: empty/whitespace would otherwise become the invalid literal "Z" and crash Postgres
  if (/[zZ]|[+-]\d{2}:\d{2}$/.test(s)) return s; // already has zone
  return s.includes("T") ? `${s}Z` : `${s.replace(" ", "T")}Z`;
}

// ─────────────────────────────────────────────────────────────────────────────
// main
// ─────────────────────────────────────────────────────────────────────────────
async function main(): Promise<void> {
  const flags = parseArgs(process.argv.slice(2));
  const apply = flags.apply === true;
  const repoRoot = (flags.repoRoot as string) || process.cwd();
  const ledgerPath = (flags.ledger as string) || path.join(repoRoot, "docs", "evidence", "260826-local-to-prod-migrate-ledger.json");

  if (apply) {
    // Belt & braces: real mode requires explicit confirmation, not just the flag.
    if (!process.env.MIGRATE_CONFIRM) {
      throw new Error("Refusing --apply without MIGRATE_CONFIRM=1 in the environment (PO approval gate).");
    }
    console.log("=== APPLY MODE: real writes to PROD Postgres / R2 ===");
  } else {
    console.log("=== DRY-RUN MODE (no writes). Re-run with --apply (+ MIGRATE_CONFIRM=1) after PO approval ===");
  }

  const env = getEnv(); // requires DATABASE_URL, ADMIN_SECRET, R2_* — from PROD service env
  const sql = postgres(env.DATABASE_URL, { max: 2 });

  // Ensure sqlite3 CLI is available up-front.
  try {
    execFileSync("sqlite3", ["--version"], { stdio: "ignore" });
  } catch {
    throw new Error("sqlite3 CLI not found on PATH — required to read legacy local DBs.");
  }

  const sources: SourceSpec[] = [
    { label: "local.db:api_keys", path: path.join(repoRoot, "web/services/pose-extract-server/data/local.db"), table: "api_keys" },
    { label: "keys.db:request_logs", path: path.join(repoRoot, "web/services/pose-extract-server/data/keys.db"), table: "request_logs" },
    { label: "docker-keys.db:extraction_jobs", path: path.join(repoRoot, ".docker-persist/data/keys.db"), table: "extraction_jobs" },
    { label: "dev.db:community_poses", path: path.join(repoRoot, "web/services/pose-extract-server/data/dev.db"), table: "community_poses" }
  ];

  const communityDirs = [
    path.join(repoRoot, "web/services/pose-extract-server/data/community"),
    path.join(repoRoot, ".docker-persist/data/community"),
    path.join(repoRoot, ".docker-data/community")
  ];

  const ledger: { mode: string; runAt: string; target: "prod"; sources: Array<{ label: string; path: string; count: number }>; items: LedgerItem[]; plan: DryRunPlan } = {
    mode: apply ? "apply" : "dry-run",
    runAt: new Date().toISOString(),
    target: "prod",
    sources: [],
    items: [],
    plan: { api_keys: 0, request_logs: 0, extraction_jobs: 0, community_poses: 0, local_files: 0, skipped_junk: 0, skipped_protected: 0 }
  };

  const existingKeys = new Set<string>();
  const existingJobs = new Set<string>();
  const existingPoses = new Set<string>();
  const existingMedia = new Set<string>();
  const existingLogIds = new Set<number>();

  try {
    // Read-only preflight against PROD: load ids already present (for idempotency/skip).
    const keys = (await sql`SELECT id FROM api_keys`) as Array<{ id: string }>;
    const jobs = (await sql`SELECT id FROM extraction_jobs`) as Array<{ id: string }>;
    const poses = (await sql`SELECT pose_id FROM poses`) as Array<{ pose_id: string }>;
    const logs = (await sql`SELECT id FROM request_logs`) as Array<{ id: number }>;
    for (const r of keys) existingKeys.add(r.id);
    for (const r of jobs) existingJobs.add(r.id);
    for (const r of poses) existingPoses.add(r.pose_id);
    for (const r of logs) existingLogIds.add(Number(r.id));

    // ── api_keys ─────────────────────────────────────────────────────────────
    const keyRows = sqliteJson(sources[0].path, `SELECT * FROM ${sources[0].table}`);
    ledger.sources.push({ label: sources[0].label, path: sources[0].path, count: keyRows.length });
    for (const row of keyRows) {
      const id = String(row.id);
      const hash = sha256(id + ":" + String(row.api_key ?? ""));
      let outcome: LedgerItem["outcome"] = "dry-run";
      if (existingKeys.has(id)) outcome = "skipped-existing";
      else if (PROTECTED_POSE_IDS.has(id)) outcome = "skipped-protected";
      if (outcome === "dry-run") ledger.plan.api_keys += 1;
      if (outcome === "skipped-protected") ledger.plan.skipped_protected += 1;
      ledger.items.push({ source: sources[0].label, kind: "api_key", id: shortId(id), hash, outcome, note: `name=${row.name}` });
      if (apply && outcome === "dry-run") {
        await sql`
          INSERT INTO api_keys (id, name, api_key, status, requests_today, created_at, last_used_at)
          VALUES (${id}, ${String(row.name)}, ${String(row.api_key)}, ${String(row.status ?? "active")},
                  ${Number(row.requests_today ?? 0)}, ${normalizeTs(row.created_at)}, ${normalizeTs(row.last_used_at)})
          ON CONFLICT (id) DO NOTHING
        `;
        ledger.items[ledger.items.length - 1] = { ...ledger.items[ledger.items.length - 1], outcome: "inserted" };
      }
    }

    // ── request_logs (after api_keys so the FK target exists) ────────────────
    const logRows = sqliteJson(sources[1].path, `SELECT * FROM ${sources[1].table}`);
    ledger.sources.push({ label: sources[1].label, path: sources[1].path, count: logRows.length });
    for (const row of logRows) {
      const rawId = Number(row.id);
      const hash = sha256(`${rawId}:${String(row.timestamp ?? "")}:${String(row.success ?? "")}`);
      let outcome: LedgerItem["outcome"] = "dry-run";
      if (existingLogIds.has(rawId)) outcome = "skipped-existing";
      if (outcome === "dry-run") ledger.plan.request_logs += 1;
      ledger.items.push({ source: sources[1].label, kind: "request_log", id: String(rawId), hash, outcome });
      if (apply && outcome === "dry-run") {
        await sql`
          INSERT INTO request_logs (id, key_id, timestamp, processing_time_ms, success, error_code)
          VALUES (${rawId}, ${row.key_id != null ? String(row.key_id) : null}, ${normalizeTs(row.timestamp)},
                  ${row.processing_time_ms != null ? Number(row.processing_time_ms) : null},
                  ${Boolean(row.success)}, ${row.error_code != null ? String(row.error_code) : null})
          ON CONFLICT (id) DO NOTHING
        `;
        ledger.items[ledger.items.length - 1] = { ...ledger.items[ledger.items.length - 1], outcome: "inserted" };
      }
    }
    if (apply && logRows.length > 0) {
      await sql`SELECT setval(pg_get_serial_sequence('request_logs','id'), GREATEST((SELECT COALESCE(MAX(id),1) FROM request_logs), 1))`;
    }

    // ── extraction_jobs ───────────────────────────────────────────────────────
    const jobRows = sqliteJson(sources[2].path, `SELECT * FROM ${sources[2].table}`);
    ledger.sources.push({ label: sources[2].label, path: sources[2].path, count: jobRows.length });
    for (const row of jobRows) {
      const id = String(row.id);
      const status = String(row.status);
      const payload = String(row.result_image_base64 ?? "") || String(row.source_image_base64 ?? "");
      const hash = sha256(id + ":" + payload.slice(0, 1024));
      const VALID_JOB_STATUS = new Set(["queued", "processing", "succeeded", "failed"]);
      let outcome: LedgerItem["outcome"] = "dry-run";
      if (EXCLUDED_JOB_IDS.has(id)) outcome = "skipped-excluded";
      else if (existingJobs.has(id)) outcome = "skipped-existing";
      else if (!VALID_JOB_STATUS.has(status)) {
        // why: status outside the schema CHECK set would violate the constraint on insert — skip and record it
        outcome = "skipped-junk";
        ledger.plan.skipped_junk += 1;
        ledger.items.push({ source: sources[2].label, kind: "extraction_job", id: shortId(id), hash, outcome, note: `status=${status}; status not in CHECK set` });
        continue;
      }
      else if (!flags.includeFailedJobs && status !== "succeeded") {
        outcome = "skipped-junk";
        ledger.plan.skipped_junk += 1;
      }
      if (outcome === "dry-run") ledger.plan.extraction_jobs += 1;
      ledger.items.push({ source: sources[2].label, kind: "extraction_job", id: shortId(id), hash, outcome, note: `status=${status}` });
      if (apply && outcome === "dry-run") {
        await sql`
          INSERT INTO extraction_jobs (id, status, source_image_base64, source_mime_type, result_image_base64,
                                       result_mime_type, error_code, error_message, attempts, max_attempts,
                                       locked_at, lock_token, created_at, updated_at)
          VALUES (${id}, ${status}, ${String(row.source_image_base64 ?? "")}, ${String(row.source_mime_type ?? "image/png")},
                  ${row.result_image_base64 != null ? String(row.result_image_base64) : null},
                  ${row.result_mime_type != null ? String(row.result_mime_type) : null},
                  ${row.error_code != null ? String(row.error_code) : null},
                  ${row.error_message != null ? String(row.error_message) : null},
                  ${Number(row.attempts ?? 0)}, ${Number(row.max_attempts ?? 3)},
                  ${normalizeTs(row.locked_at)}, ${row.lock_token != null ? String(row.lock_token) : null},
                  ${normalizeTs(row.created_at)}, ${normalizeTs(row.updated_at)})
          ON CONFLICT (id) DO NOTHING
        `;
        ledger.items[ledger.items.length - 1] = { ...ledger.items[ledger.items.length - 1], outcome: "inserted" };
      }
    }

    // ── community_poses → poses + media_assets + R2 uploads ──────────────────
    const poseRows = sqliteJson(sources[3].path, `SELECT * FROM ${sources[3].table}`);
    ledger.sources.push({ label: sources[3].label, path: sources[3].path, count: poseRows.length });
    for (const row of poseRows) {
      const id = String(row.id);
      const hash = sha256(id + ":" + String(row.image_path ?? ""));
      let outcome: LedgerItem["outcome"] = "dry-run";
      if (PROTECTED_POSE_IDS.has(id)) outcome = "skipped-protected";
      else if (EXCLUDED_POSE_IDS.has(id)) outcome = "skipped-excluded";
      else if (existingPoses.has(id)) outcome = "skipped-existing";
      else if (!flags.includeTestData) {
        // why: community_poses are ALL junk by default; --include-test-data gates every one (drop the old any-local-file bypass)
        outcome = "skipped-junk";
        ledger.plan.skipped_junk += 1;
      }
      if (outcome === "dry-run") ledger.plan.community_poses += 1;
      ledger.items.push({ source: sources[3].label, kind: "community_pose", id: shortId(id), hash, outcome, note: `name=${row.name}` });

      if (apply && outcome === "dry-run") {
        await sql.begin(async (tx) => {
          await tx`
            INSERT INTO poses (pose_id, owner_account_id, name, tags, difficulty, description, body_parts, status,
                               created_at, updated_at, download_count)
            VALUES (${id}, ${LEGACY_OWNER}, ${String(row.name)}, ${String(row.tags ?? "[]")},
                    ${row.difficulty != null ? String(row.difficulty) : null},
                    ${row.description != null ? String(row.description) : null},
                    ${String(row.body_parts ?? "[]")},
                    ${String(row.status ?? "draft") === "published" ? "published" : "local"},
                    ${normalizeTs(row.uploaded_at)}, ${normalizeTs(row.uploaded_at)}, ${Number(row.download_count ?? 0)})
            ON CONFLICT (pose_id) DO NOTHING
          `;
          const roles: Array<{ role: "original" | "skeleton" | "thumbnail"; locator: string | null; ext: string }> = [
            { role: "original", locator: row.image_path as string | null, ext: extOf(row.image_path) },
            { role: "skeleton", locator: row.image_path as string | null, ext: extOf(row.image_path) },
            { role: "thumbnail", locator: (row.thumbnail_path as string | null) ?? (row.image_path as string | null), ext: extOf((row.thumbnail_path as string | null) ?? (row.image_path as string | null)) }
          ];
          for (const r of roles) {
            const mediaId = mediaUuid(id, r.role);
            const exists = (await tx`SELECT 1 FROM media_assets WHERE pose_id=${id} AND role=${r.role}`).length > 0;
            if (exists) {
              if (!existingMedia.has(mediaId)) existingMedia.add(mediaId);
              continue;
            }
            let locator = r.locator;
            const file = r.locator ? localFileFor(r.locator, communityDirs) : null;
            if (file) {
              const key = buildCommunityObjectKey(r.role, r.ext, id);
              const existsR2 = await objectExists(key);
              if (!existsR2) {
                const body = fs.readFileSync(file);
                await uploadObject({ fileKey: key, body, mimeType: mimeFor(r.ext) });
                ledger.items.push({ source: sources[3].label, kind: "local_file", id: shortId(key), hash: sha256(key + body.length), outcome: "uploaded" });
                ledger.plan.local_files += 1;
              }
              locator = buildPublicUrl(env.R2_PUBLIC_URL, key);
            }
            await tx`
              INSERT INTO media_assets (media_id, pose_id, role, locator, mime_type, readiness)
              VALUES (${mediaId}, ${id}, ${r.role}, ${locator ?? ""}, ${mimeFor(r.ext)}, 'ready')
              ON CONFLICT (pose_id, role) DO NOTHING
            `;
          }
        });
        ledger.items[ledger.items.length - 1] = { ...ledger.items[ledger.items.length - 1], outcome: "inserted" };
      }
    }

    // ── local community image dirs (files not referenced by any DB row) ──────
    let orphanFiles = 0;
    for (const dir of communityDirs) {
      if (!fs.existsSync(dir)) continue;
      for (const file of fs.readdirSync(dir)) {
        if (file.startsWith(".")) continue;
        orphanFiles += 1;
        ledger.items.push({ source: `dir:${path.basename(dir)}`, kind: "local_file", id: file, hash: sha256(file), outcome: "dry-run", note: "untracked file — not referenced by any source row; left in place" });
      }
    }
    if (orphanFiles > 0) {
      ledger.plan.local_files += 0; // informational; orphan files are never uploaded
      console.log(`  [info] ${orphanFiles} stray file(s) found in community dirs — never uploaded/moved; review manually.`);
    }
  } finally {
    await sql.end();
  }

  // ── report + ledger ─────────────────────────────────────────────────────────
  const p = ledger.plan;
  console.log("");
  console.log("DRY-RUN/PLAN SUMMARY (mode: " + ledger.mode + ")");
  console.log(`  api_keys        will insert : ${p.api_keys}`);
  console.log(`  request_logs    will insert : ${p.request_logs}`);
  console.log(`  extraction_jobs will insert : ${p.extraction_jobs}  (failed/queued/processing skipped unless --include-failed-jobs; detail in ledger)`);
  console.log(`  community_poses will insert : ${p.community_poses}  (junk/test skipped unless --include-test-data; total skipped-junk across kinds: ${p.skipped_junk})`);
  console.log(`  local files     to upload  : ${p.local_files}`);
  console.log(`  protected poses : NOT TOUCHED (a43838f4**, e41fed67**) — protected skipped: ${p.skipped_protected}`);
  console.log(`                 : excluded ids 5f671bf2** (pose), 6faf7f58** (job) — never migrated`);
  console.log("");
  console.log(`  PROD Postgres already has: ${existingKeys.size} keys, ${existingJobs.size} jobs, ${existingPoses.size} poses, ${existingLogIds.size} logs`);
  console.log(`  Ledger written: ${ledgerPath}`);
  fs.mkdirSync(path.dirname(ledgerPath), { recursive: true });
  fs.writeFileSync(ledgerPath, JSON.stringify(ledger, null, 2) + "\n", "utf8");
  console.log(`  Source DBs are NOT deleted (cleanup only after user confirms DONE).`);
}

// ─────────────────────────────────────────────────────────────────────────────
// tiny utils used above
// ─────────────────────────────────────────────────────────────────────────────
function shortId(id: string): string {
  return id.length > 12 ? `${id.slice(0, 8)}…${id.slice(-4)}` : id;
}

function extOf(value: unknown): string {
  const s = String(value ?? "");
  const isUrl = /^https?:\/\//.test(s);
  const last = s.split(/[\/?#]/).pop() ?? "";
  const dot = last.lastIndexOf(".");
  const ext = dot >= 0 ? last.slice(dot + 1).toLowerCase().replace(/[^a-z0-9]/g, "") : "";
  if (!ext || ext.length > 5) return "png";
  return isUrl || ext.length > 0 ? (ext || "png") : "png";
}

function mimeFor(ext: string): string {
  return ext === "jpg" || ext === "jpeg" ? "image/jpeg" : ext === "webp" ? "image/webp" : "image/png";
}

function localFileFor(ref: unknown, dirs: string[]): string | null {
  if (ref == null) return null;
  const s = String(ref);
  if (/^https?:\/\//.test(s)) return null; // already remote (e.g. dev R2 URL)
  const fileName = path.basename(s);
  for (const dir of dirs) {
    const candidate = path.join(dir, fileName);
    if (fs.existsSync(candidate)) return candidate;
  }
  // Also handle relative path that points into any community dir directly.
  for (const dir of dirs) {
    if (fs.existsSync(path.join(dir, s))) return path.join(dir, s);
  }
  return null;
}

main().catch((error) => {
  console.error(`migration failed: ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
});