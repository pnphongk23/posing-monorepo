# Local Legacy-SQLite Scout — 260826 (DATA MIGRATE local→prod)

- **Author/Owner:** Trương Liêu [Lính · executor] · **Reviewer/Lead:** Tướng quân (Gia Cát Cẩn)
- **Scope:** inventory + read-only analysis of every legacy local SQLite DB, the PROD (Railway Postgres + Cloudflare R2) baseline, and the dry-run migration plan. **No writes performed** (no `--apply`, no R2 upload, no prod mutation). Script under test: `web/services/pose-extract-server/scripts/migrate-local-sqlite-to-prod.ts` (dry-run only).
- **Git baseline:** HEAD `49a2eb36b9825bbbbae688e5e96d729b3903b10e`.

---

## 1) Source inventory (absolute paths under repo root)

| DB file | Table | Rows | What it is |
|---------|-------|------|------------|
| `web/services/pose-extract-server/data/dev.db` | `community_poses` | **1** | Single "Test Pose" `46fa9b5a-f6de-4b7b-a4bd-095c0c808064`, `status=draft`; `image_path` is already a remote R2 URL on the **OLD dev** bucket `pub-fa04b9ec…` (no local file). Junk draft → excluded by default policy. |
| `…/data/dev.db` | `extraction_jobs` | **6** | All failed, placeholder-size base64 (no real photo). |
| `…/data/dev.db` | `api_keys` | **0** | — |
| `…/data/dev.db` | `request_logs` | **0** | — |
| `web/services/pose-extract-server/data/local.db` | `api_keys` | **1** | NEW-schema canonical key id `3f360925-e95f-4f73-b4eb-f77c21e6369e`, name `79ai.001`, `status=active`, `api_key` column, 216-char secret. |
| `…/data/local.db` | `request_logs` | **0** | — |
| `web/services/pose-extract-server/data/keys.db` | `api_keys` | **1** | **OLD-schema** (access_token/domain) row, same key id `3f360925…` — **not** a migration source (source is local.db). |
| `…/data/keys.db` | `request_logs` | **92** | History: 33 rows `key_id=NULL`, 59 rows `key_id=3f360925…` (FK target exists in migrated api_keys). Mostly `success=false` with `error_code=POSE_PROVIDER_ERROR`; `success` stored as INTEGER 0/1. |
| `.docker-persist/data/keys.db` | `extraction_jobs` | **5** | dev-stack runs: **3 failed**, **1 `processing`**, **1 SUCCEEDED**. The single SUCCEEDED job `15b00720-fa49-46d6-a7be-d85a8172ae5c` carries the **only real photo pair** in the local estate (`source_image_base64` ≈ 3,910,268 chars png; `result_image_base64` ≈ 2,951,380 chars png). The `processing` job `da09f9bd-008e-4dbb-be73-a54e81c84145` holds a real source image (84,216 chars) but is not finalized. |
| `.docker-persist/data/keys.db` | `app_settings` | 1 | `extraction_provider` — runtime config, **never migrated**. |
| `.docker-data/keys.db` | `app_settings` | 1 | `higgsfield_cli` only. |
| `.docker-persist/data/prod.db` | (schema only) | 0 | Empty. |
| `data/community`, `.docker-persist/data/community`, `.docker-data/community` | files | **0 files** | All three community image dirs are **empty → there are NO local image files to upload to R2.** |

> **Count note (vs baseline):** the baseline read `.docker-persist/data/keys.db` `extraction_jobs` as **6** (5 failed + 1 succeeded). Direct re-count here is **5** (3 failed + 1 `processing` + 1 succeeded). The `will-insert` outcome is unchanged (only the 1 SUCCEEDED job qualifies). This is the only inventory discrepancy found; the ledger records the true count of 5.

---

## 2) Conclusion — nothing of substance to migrate

- **No real local image files exist** (all community dirs empty). There is therefore **nothing to upload to R2** and no `community_poses` row backed by a local asset.
- The only "real" artifact in the entire local estate is the **1 SUCCEEDED extraction_jobs row** (a real photo pair already stored as base64 inside the DB row). Per the runbook, base64 stays inside `extraction_jobs` — it is **not** expanded into invented `poses`/`media_assets` rows (no metadata) and is **not** uploaded to R2 without a DB row.
- Everything else worth carrying is developer/CI **history**: **1 api_key** (NEW schema, canonical) + **92 request_logs** (mostly failure history).
- **PROD baseline (read-only via Railway prod env):** Postgres — `api_keys` 0, `request_logs` 0, `extraction_jobs` 0, `poses` 0, `media_assets` 0, `app_settings` 1 (default). R2 `ai-pose-prod` — **0 objects**. Both services running (pose-extract-server `c4350044…`, admin-ui `76c642df…`). `DATABASE_URL`, `R2_*`, `ADMIN_SECRET` present.

---

## 3) Protected / excluded ids (never modified, deleted, or recreated)

These rows no longer exist in any current local/prod estate (they previously lived in a **dev-stack Postgres volume that no longer exists**):

- **PROTECTED poses:** `a43838f4-312d-4ea7-9a05-6f7c191fd691` (Seated Raising Glass), `e41fed67-90cf-40b6-9ddc-c1727afa054d` (Seated Eating Pizza).
- **EXCLUDED ids:** pose `5f671bf2` (legacy bad-sunset), job `6faf7f58` (do not reuse).

The migration script hard-guards both sets (belt & braces) regardless of source content.

---

## 4) DRY-RUN evidence (idempotency — run twice, identical)

Ran read-only (PROD env via Railway service `c4350044…`, **no** `--apply`):
`./web/services/pose-extract-server/node_modules/.bin/tsx web/services/pose-extract-server/scripts/migrate-local-sqlite-to-prod.ts`

| Metric | Run 1 | Run 2 |
|--------|-------|-------|
| exit code | 0 | 0 |
| api_keys will insert | **1** | **1** |
| request_logs will insert | **92** | **92** |
| extraction_jobs will insert | **1** (SUCCEEDED) | **1** |
| community_poses will insert | **0** | **0** |
| local files to upload | **0** | **0** |
| skipped-junk (across kinds) | 5 (4 jobs + 1 Test Pose) | 5 |
| PROD Postgres already has | 0 keys / 0 jobs / 0 poses / 0 logs | 0 / 0 / 0 / 0 |

**Idempotent:** both runs produced identical `will-insert` plans and left PROD Postgres untouched (baseline read-only counts 0). The second run is a pure re-plan, not a re-apply — the dry-run performs only `SELECT`s (+ ledger write), never inserts.
Ledger (script's own output): `docs/evidence/260826-local-to-prod-migrate-ledger.json` (`mode: dry-run`).

> **Dry-run writes nothing** except the ledger file. No R2 HEAD/upload and no DB writes occur in dry-run mode.

---

## 5) tsc compatibility

- **Project check** (backend `web/services/pose-extract-server`): `./node_modules/.bin/tsc --noEmit -p tsconfig.json` → **exit 0** (script is outside `include` scope, so this only proves the backend stays green).
- **Standalone check** (config at `/tmp/tsc-check/tsconfig.json`, symlink to backend; `extends` backend tsconfig, `types:["node"]`, `typeRoots` → backend `node_modules/@types`, `rootDir` → backend, include `src/**/*.ts` + `scripts/migrate-local-sqlite-to-prod.ts`, exclude `*.test.ts`): `.../node_modules/.bin/tsc --noEmit -p /tmp/tsc-check/tsconfig.json` → **exit 0**.

---

## 6) PO decision needed (summary)

See `docs/evidence/260826-data-migrate-plan.md` § Decisions for the three options. In short: there is **no real local data to migrate** beyond history (key + 92 logs + 1 succeeded job) — the estate is effectively a "verify-only / nothing to migrate" state unless real source data is supplied from elsewhere.
