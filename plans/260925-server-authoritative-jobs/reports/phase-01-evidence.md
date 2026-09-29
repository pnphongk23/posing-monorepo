# Phase 1 evidence — Server data + job store

Worker: `2bd67dd9` (Lính · Quan Vũ, agy/gemini-3.7-flash-medium). Worker's own handback was
non-substantive ("Waiting for test completion."); Lead (this report) independently re-ran the
checks and reviewed the diff against `phase-01-server-data-and-store.md` before accepting.

## Changed/created files
- `src/db/schema.sql` — nullable `source_image_base64`, idempotent `ALTER TABLE` delta, `idx_extraction_jobs_owner_created`.
- `src/db/extractionJobStore.ts` — `PoseDraft`, widened `ExtractionJob`/row types, `getByIdForOwner`, `listByOwner` (keyset cursor + thumbnail join), `retryFailed`, `hide`, `markSucceededWithPose`, exported `StaleLockError`.
- `src/db/extractionJobStore.test.ts` (new) — owner isolation, pagination, state filter, hidden exclusion, retry per status, hide idempotency/base64 null, `markSucceededWithPose` success + stale-lock rollback.
- `src/db/connection.test.ts` — added idempotent-reapply test for the schema delta.
- `src/worker/error-codes.ts` — `SOURCE_MISSING`.
- `src/worker/job-processor.ts` — null-source guard → `markFailedOrRequeue(..., SOURCE_MISSING)` (line ~69, matches phase doc; Phase 2 will replace this call site with the materializer branch).
- `src/routes/adminCommunityRoutes.ts` — null-source guard → 400 `JOB_NOT_SUCCEEDED` (line ~162; Phase 2 replaces this too).
- `vitest.config.ts` — `testTimeout: 20000` (PGlite suite runtime; minor, not scope-breaking).

## Checks run by Lead (re-verified independently)
```
cd web/services/pose-extract-server
npx vitest run src/db --fileParallelism false
 Test Files  5 passed (5)
      Tests  31 passed (31)

npx vitest run src/worker/job-processor.test.ts src/worker/worker-loop.test.ts
 Test Files  2 passed (2)
      Tests  18 passed (18)

npm run lint   # tsc --noEmit -p tsconfig.json — clean, no output
```

## Deviations from the phase doc
- None material. `attempts` reset to 0 happens inside the same `retryFailed` UPDATE rather than a separate step — consistent with plan.md D8.
- Minor: worker also touched `vitest.config.ts` (test timeout) and `connection.test.ts` (added idempotency test) which were not in its explicit owned-files list, but both are small, in-domain, and required to prove the phase-doc's own acceptance criterion ("connection.test.ts fails on a re-apply" per plan.md R4). Accepted.

## Status
Phase 1: **DONE**, verified by Lead. Unblocks Phase 2 and Phase 3 (both depend on Phase 1 only; plan.md confirms their write-sets don't overlap).
