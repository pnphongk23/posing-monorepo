---
name: rednote-dev-pose-materialization
description: Safe step-by-step procedure for public RedNote video pose retrieval, Higgsfield CLI extraction, background lineart removal preflight, R2 admin materialization, DB/R2/API verification, and environment cleanup in dev stack.
---

# RedNote Dev Pose Materialization Procedure

This skill defines the canonical, portable, step-by-step procedure for extracting public RedNote/Xiaohongshu video frames, executing pose extraction via Higgsfield CLI worker, materializing R2 assets via the Admin API (per DEC-005), verifying DB/R2/live endpoints, and performing strict environment cleanup.

---

## 1. Public-Only Retrieval Policy & Frame Selection

- **Public Access Only:** Retrieve content exclusively via standard public HTTP GET requests. NEVER attempt to bypass login prompts, anti-bot mechanisms, captchas, paywalls, DRM, or access controls. If a public link requires authentication or protection bypass, **STOP immediately and report `BLOCKED_NEEDS_LEAD`**.
- **Source Selection:** Extract frames from public MP4 video streams.
- **Frame Quality Criteria:**
  - Subject is clear and sharp (high Laplacian variance / contrast).
  - Full body and limbs (or pose-relevant upper/lower body) are fully visible without excessive blur or occlusion.
  - Stance/gesture is visually distinct from existing published samples (e.g. distinct from "Seated Eating Pizza" and "Seated Raising Glass").
  - Clear subject-background contrast suitable for pose extraction and lineart background removal.
- **Local Inspection Only:** Inspect candidate frame(s) locally using local viewing/analysis tools without logging base64 payloads, raw image bytes, or public video URL origins to chat or repository logs.

---

## 2. Preflight Prerequisites & Safety Boundaries

### Credentials & Security
- **Canonical Host Credentials Path:** `~/.config/higgsfield/credentials.json` ONLY.
- **Strict Prohibition:** NEVER inspect, read, copy to repository, print, or log credential contents, API keys, bearer tokens, DB passwords, R2 secret keys, or R2 bucket hostnames/origins.
- **Temporary Container Access:** If copying credentials into a dev container for execution, copy to `/tmp/higgsfield/credentials.json` with strict `chmod 600` permissions. Remove temporary credentials immediately during cleanup. Do NOT use obsolete `~/.higgsfield`.

### Execution Environment & Docker Policy
- **Docker Compose Dev Stack Policy:** ALL backend execution commands (including provider API updates, job enqueue/polling, worker execution, DB queries, R2 object verification, and worker cleanup) MUST be run through the Docker Compose dev stack (`docker compose -f docker-compose.dev.yml exec ...`).
- **Host Limitations:** Host `curl` and read-only file/log inspection are allowed for quick read-only observation, but CANNOT count as backend test/smoke evidence.
- **Lineart Background Removal Preflight:**
  - Standard container must include `python3` and `PIL` (Pillow).
  - Script path: `/app/scripts/remove_bg_lineart.py` inside `pose-extract-server`.
  - Check availability with `docker compose -f docker-compose.dev.yml exec pose-extract-server python3 -c "import PIL"`.
  - If Python/Pillow dependency is missing, any durable fix must be a source-controlled Dockerfile configuration (`Dockerfile.dev`), NEVER `pip install` on a live running container.

---

## 3. Step-by-Step Pose Materialization Procedure

### Step 3.1 — Configure Active Extraction Provider
Switch active provider to `higgsfield_cli` via the Admin Settings API using Docker Compose:
```bash
docker compose -f docker-compose.dev.yml exec pose-extract-server \
  curl -s -X PUT \
  -H "Authorization: Bearer ${ADMIN_SECRET}" \
  -H "Content-Type: application/json" \
  -d '{"provider": "higgsfield_cli"}' \
  http://localhost:3000/api/admin/settings/extraction-provider
```

### Step 3.2 — Higgsfield Workspace Selection (if required)
Ensure the Higgsfield CLI has a selected workspace:
```bash
docker compose -f docker-compose.dev.yml exec \
  -e HIGGSFIELD_CREDENTIALS_PATH=/tmp/higgsfield/credentials.json \
  pose-extract-server higgsfield workspace list
```
If no workspace shows `✓` under `SELECTED`, set the workspace ID:
```bash
docker compose -f docker-compose.dev.yml exec \
  -e HIGGSFIELD_CREDENTIALS_PATH=/tmp/higgsfield/credentials.json \
  pose-extract-server higgsfield workspace set <WORKSPACE_ID>
```

### Step 3.3 — Enqueue Extraction Job
Submit the candidate image to the async extraction endpoint (returns `202 Accepted` with `jobId`):
```bash
docker compose -f docker-compose.dev.yml exec pose-extract-server \
  curl -s -X POST \
  -F "image=@/path/to/candidate_frame.png;type=image/png" \
  http://localhost:3000/api/extract-pose
```
Record the returned `jobId`.

### Step 3.4 — Execute Worker & Poll Job Status
Run the temporary worker process inside the container to process the queued job:
```bash
docker compose -f docker-compose.dev.yml exec -d \
  -e HIGGSFIELD_CREDENTIALS_PATH=/tmp/higgsfield/credentials.json \
  pose-extract-server npx tsx src/worker/worker-main.ts
```
Poll job status until `"succeeded"`:
```bash
docker compose -f docker-compose.dev.yml exec pose-extract-server \
  curl -s http://localhost:3000/api/extract-jobs/<JOB_ID>
```
*Note: DEC-005 defers worker-to-R2 upload to Phase 5. The extraction worker stores result image base64 in `extraction_jobs`.*

### Step 3.5 — Admin R2 Materialization & Publishing
1. **Materialize Pose to R2:** Call `POST /api/admin/community/poses`. This uploads `original`, `skeleton`, and `thumbnail` media assets to R2 and creates a canonical local Pose:
   ```bash
   docker compose -f docker-compose.dev.yml exec pose-extract-server \
     curl -s -X POST \
     -H "Authorization: Bearer ${ADMIN_SECRET}" \
     -H "Content-Type: application/json" \
     -d '{
       "jobId": "<JOB_ID>",
       "ownerAccountId": "00000000-0000-4000-8000-000000000001",
       "name": "<Canonical Pose Name>",
       "tags": ["tag1", "tag2"],
       "difficulty": "beginner",
       "description": "<Pose Description>",
       "bodyParts": ["full_body"]
     }' \
     http://localhost:3000/api/admin/community/poses
   ```
   Record the generated `poseId` (UUID).

2. **Publish Pose:** Update status from `local` to `published`:
   ```bash
   docker compose -f docker-compose.dev.yml exec pose-extract-server \
     curl -s -X PATCH \
     -H "Authorization: Bearer ${ADMIN_SECRET}" \
     -H "Content-Type: application/json" \
     -d '{"status": "published"}' \
     http://localhost:3000/api/admin/community/poses/<POSE_ID>
   ```

---

## 4. Verification & Validation Gates

1. **DB Media Locators:** Query Postgres via Docker Compose to verify the 3 required roles (`original`, `skeleton`, `thumbnail`) exist, have `readiness = 'ready'`, and locators use HTTP(S) R2 URLs with NO `data:` URLs:
   ```bash
   docker compose -f docker-compose.dev.yml exec postgres psql -U postgres -d pose \
     -c "SELECT pose_id, role, readiness, locator FROM media_assets WHERE pose_id = '<POSE_ID>';"
   ```
2. **R2 Object Accessibility (3/3 HEAD + GET):** Verify both `HEAD` and `GET` for all 3 media roles return HTTP status `200`, non-empty size, and `image/png` content-type via Docker Compose S3/R2 client script or curl. Sanitize host/bucket origin in logs.
3. **Public API Endpoints:**
   - **Browse:** `GET /api/community/poses` returns all published poses (including existing 2 samples and the new pose).
   - **Targeted Search:** `GET /api/community/poses?q=<query>` matches the new pose.
   - **Detail View:** `GET /api/community/poses/<POSE_ID>` returns the full public projection with status `published` and increments `downloadCount`.

---

## 5. Failure Handling & Cleanup Protocol

### Rollback Protocol (on job or materialization failure)
1. Delete temporary/failed test job records from `extraction_jobs` in DB.
2. Remove any orphaned R2 objects created for the failed pose ID.
3. Preserve existing sample poses (`a43838f4-312d-4ea7-9a05-6f7c191fd691` and `e41fed67-90cf-40b6-9ddc-c1727afa054d`) byte-for-byte; NEVER modify or delete them.

### Mandatory Final Cleanup Sequence
1. **Restore Active Provider:** Set `extraction_provider = gemini_native` via Admin API:
   ```bash
   docker compose -f docker-compose.dev.yml exec pose-extract-server \
     curl -s -X PUT \
     -H "Authorization: Bearer ${ADMIN_SECRET}" \
     -H "Content-Type: application/json" \
     -d '{"provider": "gemini_native"}' \
     http://localhost:3000/api/admin/settings/extraction-provider
   ```
2. **Clear Active Queue:** Confirm active queue count is `0`:
   ```bash
   docker compose -f docker-compose.dev.yml exec postgres psql -U postgres -d pose \
     -c "SELECT count(*) FROM extraction_jobs WHERE status IN ('pending', 'processing');"
   ```
3. **Stop Temporary Worker Process (No Service Restart):** Do NOT restart the backend service. Stop ONLY the temporary `worker-main.ts` background process via Compose:
   ```bash
   docker compose -f docker-compose.dev.yml exec -T pose-extract-server sh -c 'pkill -f "[w]orker-main.ts" || true'
   ```
   Verify no `worker-main.ts` process remains:
   ```bash
   docker compose -f docker-compose.dev.yml exec -T pose-extract-server sh -c 'pgrep -f "[w]orker-main.ts" || true'
   ```
4. **Purge Temp Credentials & Artifacts:** Remove `/tmp/higgsfield/credentials.json` and any local temporary extracted frame/video files from host and container:
   ```bash
   docker compose -f docker-compose.dev.yml exec pose-extract-server rm -rf /tmp/higgsfield /tmp/lineart-bg-removal /tmp/extract-jobs
   ```
