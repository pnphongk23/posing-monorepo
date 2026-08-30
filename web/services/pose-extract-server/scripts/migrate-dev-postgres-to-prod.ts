/* eslint-disable no-console */
/**
 * migrate-dev-postgres-to-prod.ts
 *
 * Migrates the REAL legacy data from the local dev-stack Postgres
 * (docker compose dev: pose-postgres-dev, db "pose") into PROD:
 *   - poses + media_assets + extraction_jobs rows  → PROD Postgres (DATABASE_URL)
 *   - media objects (original/skeleton/thumbnail)  → PROD R2 bucket (R2_*), copied
 *     object-for-object from the dev R2 bucket (DEV_R2_*) — same object keys,
 *     locators rewritten to the PROD public URL.
 *
 * Safety contract (same as migrate-local-sqlite-to-prod.ts):
 *   - DEFAULT MODE IS DRY-RUN: writes NOTHING (no uploads, no inserts). Real mode
 *     requires BOTH --apply AND env MIGRATE_CONFIRM=1.
 *   - Idempotent: INSERT ... ON CONFLICT DO NOTHING on every table; R2 uploads skip
 *     objects that already exist in PROD (HEAD).
 *   - Protected poses are never modified/deleted (kept byte-identical when copying,
 *     skipped if PROD already has them). Excluded ids are never migrated.
 *   - No secrets printed or written; ledger records sha256 hashes only.
 *
 * USAGE (run from repo root):
 *   # PROD env (from Railway service pose-extract-server c4350044...):
 *   export DATABASE_URL R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET R2_PUBLIC_URL
 *   # DEV env (dev stack):
 *   export DATABASE_URL_DEV=postgresql://postgres:postgres@localhost:5433/pose
 *   export DEV_R2_ACCOUNT_ID DEV_R2_ACCESS_KEY_ID DEV_R2_SECRET_ACCESS_KEY DEV_R2_BUCKET
 *   ./web/services/pose-extract-server/node_modules/.bin/tsx \
 *     web/services/pose-extract-server/scripts/migrate-dev-postgres-to-prod.ts        # dry-run
 *   # ... after PO approval:
 *   export MIGRATE_CONFIRM=1
 *   ... --apply
 */

import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";

import { DeleteObjectCommand, GetObjectCommand, HeadObjectCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import postgres from "postgres";

// ─────────────────────────────────────────────────────────────────────────────
// Protected / excluded ids. NEVER modified, deleted, or recreated in PROD.
// ─────────────────────────────────────────────────────────────────────────────
const PROTECTED_POSE_IDS = [
  "a43838f4-312d-4ea7-9a05-6f7c191fd691", // Seated Raising Glass Pose (keep)
  "e41fed67-90cf-40b6-9ddc-c1727afa054d" //  Seated Eating Pizza Pose (keep)
];
const EXCLUDED_POSE_IDS = ["5f671bf2-6bf4-4955-adc3-09cad9473d47"]; // bad-sunset "Seated Sunset Flash Pose"
const EXCLUDED_JOB_IDS = ["6faf7f58", "ab30d194-1bff-49da-9bfd-04a9343e42d4"]; // 6faf7f58: never reuse; ab30d194: belongs to the excluded bad pose

interface PoseRow {
  pose_id: string;
  owner_account_id: string;
  name: string;
  tags: string;
  difficulty: string | null;
  description: string | null;
  body_parts: string;
  status: string;
  current_job_id: string | null;
  created_at: Date;
  updated_at: Date;
  download_count: number;
}

interface MediaRow {
  media_id: string;
  pose_id: string;
  role: "original" | "skeleton" | "thumbnail";
  locator: string;
  mime_type: string;
  readiness: string;
}

interface JobRow {
  id: string;
  status: string;
  source_image_base64: string | null;
  source_mime_type: string | null;
  result_image_base64: string | null;
  result_mime_type: string | null;
  error_code: string | null;
  error_message: string | null;
  attempts: number;
  max_attempts: number;
  locked_at: Date | null;
  lock_token: string | null;
  created_at: Date;
  updated_at: Date;
}

function sha256(v: string): string {
  return createHash("sha256").update(v).digest("hex").slice(0, 32);
}

function isExcluded(id: string, list: string[]): boolean {
  return list.some((e) => id === e || id.startsWith(e));
}

function shortId(id: string): string {
  return id.length > 16 ? `${id.slice(0, 12)}…${id.slice(-4)}` : id;
}

function r2Client(accountId: string | undefined, keyId: string | undefined, secret: string | undefined): S3Client {
  if (!accountId || !keyId || !secret) throw new Error("Missing R2 credentials");
  return new S3Client({
    region: "auto",
    endpoint: `https://${accountId}.r2.cloudflarestorage.com`,
    credentials: { accessKeyId: keyId, secretAccessKey: secret }
  });
}

async function objectExists(client: S3Client, bucket: string, key: string): Promise<boolean> {
  try {
    await client.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
    return true;
  } catch {
    return false;
  }
}

async function copyObject(devClient: S3Client, devBucket: string, prodClient: S3Client, prodBucket: string, key: string): Promise<"copied" | "exists" | "failed"> {
  try {
    if (await objectExists(prodClient, prodBucket, key)) return "exists";
    const got = await devClient.send(new GetObjectCommand({ Bucket: devBucket, Key: key }));
    const body = await got.Body?.transformToByteArray();
    if (!body) return "failed";
    await prodClient.send(new PutObjectCommand({ Bucket: prodBucket, Key: key, Body: Buffer.from(body), ContentType: got.ContentType ?? "image/png", CacheControl: "public, max-age=31536000, immutable", ContentDisposition: "inline" }));
    return "copied";
  } catch {
    return "failed";
  }
}

function keyFromLocator(locator: string): string | null {
  try {
    const u = new URL(locator);
    const key = u.pathname.replace(/^\/+/, "");
    return key.startsWith("community/") ? key : null;
  } catch {
    return null;
  }
}

interface LedgerItem {
  kind: string;
  id?: string;
  name?: string;
  poseId?: string;
  role?: string;
  key?: string;
  status?: string;
  hash: string;
  outcome: string;
  note?: string;
}

interface Ledger {
  mode: string;
  runAt: string;
  target: string;
  protectedPoses: string[];
  excludedPoseIds: string[];
  excludedJobIds: string[];
  sources: Record<string, string>;
  items: LedgerItem[];
  plan: { poses: number; media: number; jobs: number; uploads: number; skippedJunk: number };
}

async function main(): Promise<void> {
  const argv = process.argv.slice(2);
  const apply = argv.includes("--apply");
  const includeLocal = true; // PO approved migrating the local pose a46fefd0 as-is
  const ledgerPath = path.join(process.cwd(), "docs", "evidence", "260826-dev-to-prod-migrate-ledger.json");

  if (apply && !process.env.MIGRATE_CONFIRM) {
    throw new Error("Refusing --apply without MIGRATE_CONFIRM=1 (PO approval gate).");
  }
  console.log(apply ? "=== APPLY MODE: real writes to PROD Postgres / PROD R2 ===" : "=== DRY-RUN MODE (no writes). Re-run with --apply (+ MIGRATE_CONFIRM=1) after PO approval ===");

  const envDef = {
    prodDb: process.env.DATABASE_URL ?? "",
    r2Account: process.env.R2_ACCOUNT_ID ?? "",
    r2Key: process.env.R2_ACCESS_KEY_ID ?? "",
    r2Secret: process.env.R2_SECRET_ACCESS_KEY ?? "",
    r2Bucket: process.env.R2_BUCKET ?? "",
    r2Public: process.env.R2_PUBLIC_URL ?? "",
    devDb: process.env.DATABASE_URL_DEV ?? "",
    devR2Account: process.env.DEV_R2_ACCOUNT_ID ?? "",
    devR2Key: process.env.DEV_R2_ACCESS_KEY_ID ?? "",
    devR2Secret: process.env.DEV_R2_SECRET_ACCESS_KEY ?? "",
    devR2Bucket: process.env.DEV_R2_BUCKET ?? ""
  } as Record<string, string>;
  for (const k of Object.keys(envDef)) {
    if (!envDef[k]) throw new Error(`Missing env ${k}`);
  }
  const env = envDef;

  const dev = postgres(env.devDb, { max: 3 });
  const prod = postgres(env.prodDb, { max: 3 });
  const devClient = r2Client(env.devR2Account, env.devR2Key, env.devR2Secret);
  const prodClient = r2Client(env.r2Account, env.r2Key, env.r2Secret);

  const ledger: Ledger = {
    mode: apply ? "apply" : "dry-run",
    runAt: new Date().toISOString(),
    target: "prod",
    protectedPoses: PROTECTED_POSE_IDS,
    excludedPoseIds: EXCLUDED_POSE_IDS,
    excludedJobIds: EXCLUDED_JOB_IDS,
    sources: { devPostgres: env.devDb.replace(/\/\/.*@/, "//***@"), devR2Bucket: env.devR2Bucket, prodR2Bucket: env.r2Bucket },
    items: [],
    plan: { poses: 0, media: 0, jobs: 0, uploads: 0, skippedJunk: 0 }
  };

  // Declared here (outside the try) so the final summary can read them.
  const uploadTasks: Array<{ media: MediaRow; key: string }> = [];
  const prodPoses = new Set<string>();
  const prodMedia = new Set<string>();
  const prodJobs = new Set<string>();

  try {
    // ── read dev source (read-only) ──────────────────────────────────────────
    const poses = (await dev`SELECT * FROM poses`) as unknown as PoseRow[];
    const media = (await dev`SELECT * FROM media_assets`) as unknown as MediaRow[];
    const jobs = (await dev`SELECT * FROM extraction_jobs`) as unknown as JobRow[];

    const poseIds = new Set(poses.map((p) => p.pose_id));
    const allowedMedia = media.filter((m) => poseIds.has(m.pose_id) && !isExcluded(m.pose_id, EXCLUDED_POSE_IDS));

    // ── PROD preflight (read-only) ───────────────────────────────────────────
    const prodPoseRows = (await prod`SELECT pose_id FROM poses`) as unknown as Array<{ pose_id: string }>;
    for (const r of prodPoseRows) prodPoses.add(r.pose_id);
    const prodMediaRows = (await prod`SELECT pose_id || ':' || role AS k FROM media_assets`) as unknown as Array<{ k: string }>;
    for (const r of prodMediaRows) prodMedia.add(r.k);
    const prodJobRows = (await prod`SELECT id FROM extraction_jobs`) as unknown as Array<{ id: string }>;
    for (const r of prodJobRows) prodJobs.add(r.id);

    // ── poses plan ───────────────────────────────────────────────────────────
    for (const p of poses) {
      const isProto = isExcluded(p.pose_id, PROTECTED_POSE_IDS);
      const isBad = isExcluded(p.pose_id, EXCLUDED_POSE_IDS);
      let outcome = "dry-run";
      let note = `status=${p.status}; protected=${isProto}`;
      if (isBad) {
        outcome = "skipped-junk";
        ledger.plan.skippedJunk = (ledger.plan.skippedJunk as number) + 1;
        note = "bad sunset — excluded";
      } else if (prodPoses.has(p.pose_id)) {
        outcome = "skipped-existing";
        note = "already in PROD (protected kept untouched)";
      } else if (p.status === "local" && !includeLocal) {
        outcome = "skipped-junk";
        ledger.plan.skippedJunk = (ledger.plan.skippedJunk as number) + 1;
      } else {
        ledger.plan.poses = (ledger.plan.poses as number) + 1;
      }
      ledger.items.push({ kind: "pose", id: shortId(p.pose_id), name: p.name, hash: sha256(p.pose_id + p.name), outcome, note });
      if (apply && outcome === "dry-run") {
        await prod`
          INSERT INTO poses (pose_id, owner_account_id, name, tags, difficulty, description, body_parts, status,
                             current_job_id, created_at, updated_at, download_count)
          VALUES (${p.pose_id}, ${p.owner_account_id}, ${p.name}, ${p.tags}, ${p.difficulty}, ${p.description},
                  ${p.body_parts}, ${p.status}, ${p.current_job_id}, ${p.created_at}, ${p.updated_at}, ${p.download_count})
          ON CONFLICT (pose_id) DO NOTHING
        `;
        ledger.items[ledger.items.length - 1] = { ...ledger.items[ledger.items.length - 1], outcome: "inserted" };
      }
    }

    // ── media plan + R2 copy ────────────────────────────────────────────────
    uploadTasks.length = 0;
    for (const m of allowedMedia) {
      if (isExcluded(m.pose_id, EXCLUDED_POSE_IDS)) continue;
      const key = keyFromLocator(m.locator);
      let outcome = "dry-run";
      let note = "";
      if (!key) {
        outcome = "skipped-junk";
        note = "locator not on R2 community key: " + m.locator.slice(0, 50);
      } else if (prodMedia.has(`${m.pose_id}:${m.role}`)) {
        outcome = "skipped-existing";
        note = "media already in PROD";
      } else {
        ledger.plan.media += 1;
        uploadTasks.push({ media: m, key });
      }
      ledger.items.push({ kind: "media", poseId: shortId(m.pose_id), role: m.role, key: key ?? "", hash: sha256(m.media_id + (key ?? "")), outcome, note });
    }

    if (apply && uploadTasks.length > 0) {
      // concurrent-limited uploads; keep failures visible in the ledger
      const concurrency = 8;
      let index = 0;
      const workers = Array.from({ length: concurrency }, async () => {
        while (index < uploadTasks.length) {
          const task = uploadTasks[index++];
          const result = await copyObject(devClient, env.devR2Bucket, prodClient, env.r2Bucket, task.key);
          if (result === "copied") {
            ledger.plan.uploads += 1;
            const entry = ledger.items.find((it) => it.kind === "media" && it.key === task.key && it.outcome === "dry-run");
            if (entry) entry.outcome = "uploaded";
          } else if (result === "exists") {
            const entry = ledger.items.find((it) => it.kind === "media" && it.key === task.key);
            if (entry) entry.outcome = "skipped-existing";
          } else {
            const entry = ledger.items.find((it) => it.kind === "media" && it.key === task.key);
            if (entry) { entry.outcome = "failed"; entry.note = "R2 dev->prod copy failed"; }
            console.error(`  [warn] copy failed for ${task.key}`);
          }
        }
      });
      await Promise.all(workers);

      // insert media with PROD locators — only when the object truly exists in PROD R2
      for (const task of uploadTasks) {
        const entry = ledger.items.find((it) => it.kind === "media" && it.key === task.key);
        if (entry?.outcome === "failed") continue; // object copy failed — never insert a dangling row
        const locator = `${(env.r2Public ?? "").replace(/\/+$/, "")}/${task.key}`;
        const exists = await objectExists(prodClient, env.r2Bucket, task.key);
        if (!exists) {
          if (entry) { entry.outcome = "failed"; entry.note = "object not present in PROD R2 after upload attempt"; }
          console.error(`  [warn] ${task.key} missing in PROD R2 — media row not inserted`);
          continue;
        }
        await prod`
          INSERT INTO media_assets (media_id, pose_id, role, locator, mime_type, readiness)
          VALUES (${task.media.media_id}, ${task.media.pose_id}, ${task.media.role}, ${locator}, ${task.media.mime_type}, ${task.media.readiness})
          ON CONFLICT (pose_id, role) DO NOTHING
        `;
        if (entry && entry.outcome === "dry-run") entry.outcome = "inserted";
      }
    }

    // ── jobs plan ───────────────────────────────────────────────────────────
    for (const j of jobs) {
      if (isExcluded(j.id, EXCLUDED_JOB_IDS)) {
        ledger.items.push({ kind: "job", id: shortId(j.id), hash: sha256(j.id), outcome: "skipped-junk", note: "excluded (6faf7f58 / bad-sunset job)" });
        ledger.plan.skippedJunk = (ledger.plan.skippedJunk as number) + 1;
        continue;
      }
      let outcome = prodJobs.has(j.id) ? "skipped-existing" : "dry-run";
      if (outcome === "dry-run") ledger.plan.jobs = (ledger.plan.jobs as number) + 1;
      ledger.items.push({ kind: "job", id: shortId(j.id), status: j.status, hash: sha256(j.id + (j.result_image_base64 ?? "").slice(0, 128)), outcome });
      if (apply && outcome === "dry-run") {
        await prod`
          INSERT INTO extraction_jobs (id, status, source_image_base64, source_mime_type, result_image_base64,
                                       result_mime_type, error_code, error_message, attempts, max_attempts,
                                       locked_at, lock_token, created_at, updated_at)
          VALUES (${j.id}, ${j.status}, ${j.source_image_base64}, ${j.source_mime_type}, ${j.result_image_base64},
                  ${j.result_mime_type}, ${j.error_code}, ${j.error_message}, ${j.attempts}, ${j.max_attempts},
                  ${j.locked_at}, ${j.lock_token}, ${j.created_at}, ${j.updated_at})
          ON CONFLICT (id) DO NOTHING
        `;
        ledger.items[ledger.items.length - 1] = { ...ledger.items[ledger.items.length - 1], outcome: "inserted" };
      }
    }
  } finally {
    await dev.end();
    await prod.end();
  }

  const p = ledger.plan as { poses: number; media: number; jobs: number; uploads: number; skippedJunk: number };
  console.log("");
  console.log(`PLAN SUMMARY (mode=${ledger.mode})`);
  console.log(`  poses to insert  : ${p.poses}   (protected kept; bad 5f671bf2 excluded; local a46fefd0 included per PO)`);
  console.log(`  media to insert  : ${p.media}   (upload+insert or skip-existing)`);
  console.log(`  R2 objects to copy (dev→prod): ${uploadTasks?.length ?? 0} (uploads done: ${p.uploads})`);
  console.log(`  jobs to insert   : ${p.jobs}   (excluded: 6faf7f58, ab30d194)`);
  console.log(`  skipped as junk/excluded: ${p.skippedJunk}`);
  console.log(`  PROD preflight   : poses ${[...prodPoses ?? []].length}, media ${[...prodMedia ?? []].length}, jobs ${[...prodJobs ?? []].length}`);
  console.log(`  Ledger: ${ledgerPath}`);
  fs.mkdirSync(path.dirname(ledgerPath), { recursive: true });
  fs.writeFileSync(ledgerPath, JSON.stringify(ledger, null, 2) + "\n", "utf8");
  console.log(`  Source data is NOT deleted (keep until user confirms DONE).`);
}

main().catch((error) => {
  console.error(`migration failed: ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
});