---
work_item: 3
title: Route extract through ExtractionJob worker with gpt_image_2 CLI spawn
status: completed
priority: P2
effort: L
dependencies:
  - 2
decision_dependencies: []
---

# Work Item 3: Route extract through ExtractionJob worker with gpt_image_2 CLI spawn

**Kind:** technical

## Tasks

- Refactor `job-processor.ts` to accept `PoseExtractorProvider` from factory
  instead of `GeminiBrowserClient`.
- Refactor `worker-main.ts` to load `ProviderSettingsStore`, build factory deps,
  and remove Playwright browser startup for extract jobs (or gate behind env flag
  default off).
- Complete `HiggsfieldCliProvider`: capture real CLI JSON fixture for
  result URL parsing (historical `gpt_image_2` fixture retained in tests),
  implement URL extraction, MIME detection, timeout, cleanup.
- Change `POST /api/extract-pose` to enqueue `ExtractionJob` and return `202`
  with `jobId` + poll URL (no sync base64 in phase 1).
- Add public `GET /api/extract-jobs/:jobId` (IP rate-limited) returning same
  shape as admin job status minus admin-only fields.
- Ensure `adminCommunityRoutes` enqueue path uses same worker provider selection
  (no separate engine).
- Update `extractPose.test.ts` and add worker integration test: enqueue → mock
  provider → `succeeded`.
- Document breaking change: mobile sync client out of scope; server OpenAPI +
  extract-pose spec updated in WI-1/WI-7.

## Scope and affected files

- `web/services/pose-extract-server/src/worker/job-processor.ts`
- `web/services/pose-extract-server/src/worker/worker-main.ts`
- `web/services/pose-extract-server/src/worker/gemini-browser-client.ts` (deprecate/remove from extract path)
- `web/services/pose-extract-server/src/routes/extractPoseRoutes.ts`
- `web/services/pose-extract-server/src/routes/extractJobsRoutes.ts` (new)
- `web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts`
- `web/services/pose-extract-server/src/app.ts` / `index.ts` (route registration)
- `web/services/pose-extract-server/src/services/higgsfieldCliProvider.ts`
- `web/services/pose-extract-server/src/extractPose.test.ts`
- `web/services/pose-extract-server/src/db/extractionJobStore.ts` (optional `provider` audit column)

## Success criteria

- Worker processes jobs with `gemini_native` (REST) and `higgsfield_cli` (CLI)
  based on SQLite settings.
- Higgsfield path runs `higgsfield generate create kling_omni_image --image <path> --wait --json`
  and stores base64 result on job row.
- `POST /api/extract-pose` returns `202` + `jobId`; no inline `--wait` HTTP sync.
- Public poll endpoint returns `queued` → `processing` → `succeeded`/`failed`.
- Community `202` intake unchanged in shape; jobs processed by same worker.
- Playwright browser client not required for default extract worker startup.

## Risks

- CLI JSON schema unknown until live probe; parse failures must not crash worker.
- Large base64 in SQLite rows already exist; monitor job table size.
- Removing browser worker may affect operators relying on Gemini web UI path.
- Concurrent jobs spawning CLI may hit rate limits; document max concurrency.

## Required evidence

- Captured anonymized CLI stdout fixture committed under `src/fixtures/` or test.
- `npm run backend:test` — extract + worker tests green.
- Manual or scripted run: enqueue job with `higgsfield_cli` setting → `succeeded`.
- Plan verification ledger item "Higgsfield CLI response field" → **Verified**.
