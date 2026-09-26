---
phase: 1
title: "Server data + job store"
status: pending
priority: P1
effort: "4h"
dependencies: []
---

# Phase 1: Server data + job store

## Overview
Add ownership, the pose draft, the Pose link and soft-hide to `extraction_jobs`, and give
`ExtractionJobStore` the owner-scoped queries that Phases 2 and 3 need.

## Requirements
- Functional: create owner jobs with a draft, list them for their owner with a cursor, fetch one scoped to its owner, retry a failed job, hide a job, and finalize a job with a Pose.
- Non-functional: applying `schema.sql` repeatedly stays idempotent, and legacy admin jobs without an owner keep working unchanged.

## Architecture
Change the CREATE definition to `source_image_base64 TEXT` (nullable) for fresh databases, then append
this delta after the `extraction_jobs` CREATE in `src/db/schema.sql` for existing databases:
```sql
ALTER TABLE extraction_jobs ADD COLUMN IF NOT EXISTS owner_account_id TEXT;
ALTER TABLE extraction_jobs ADD COLUMN IF NOT EXISTS pose_draft JSONB;
ALTER TABLE extraction_jobs ADD COLUMN IF NOT EXISTS pose_id TEXT;
ALTER TABLE extraction_jobs ADD COLUMN IF NOT EXISTS hidden_at TIMESTAMPTZ;
ALTER TABLE extraction_jobs ALTER COLUMN source_image_base64 DROP NOT NULL;
CREATE INDEX IF NOT EXISTS idx_extraction_jobs_owner_created
  ON extraction_jobs(owner_account_id, created_at DESC, id DESC) WHERE hidden_at IS NULL;
```
`PoseDraft = { name: string; tags: string[]; description: string | null }`.

New store methods:
- `enqueue({ …, ownerAccountId?: string, poseDraft?: PoseDraft })`
- `getByIdForOwner(id, ownerAccountId)`: returns `null` when the owner differs or the job is hidden.
- `listByOwner(ownerAccountId, { state?: 'active'|'finished', limit, cursor })`: newest first, keyset cursor
  `base64url(created_at|id)`, excludes hidden jobs, LEFT JOINs `media_assets` (role `thumbnail`) to get `thumbnailUrl`.
- `retryFailed(id, ownerAccountId)` → `'requeued' | 'not_found' | 'not_retryable'`. Runs a single
  `UPDATE … WHERE status='failed' AND owner_account_id=… AND hidden_at IS NULL AND source_image_base64 IS NOT NULL`.
  When zero rows change, a follow-up SELECT decides the result: a missing, foreign-owned or hidden job → `not_found`; any other case → `not_retryable`.
- `hide(id, ownerAccountId)` → boolean. Sets `hidden_at = COALESCE(hidden_at, NOW())` and, when `status='failed'`, also
  `source_image_base64 = NULL` (D11). It never touches `poses`.
- `markSucceededWithPose(sql, id, lockToken, poseId)`: takes the transaction handle, sets `status='succeeded'`,
  `pose_id`, and nulls both base64 columns and the lock `WHERE id=… AND lock_token=…`. **It asserts
  `result.count === 1` and otherwise throws `StaleLockError`**, so the surrounding transaction rolls back (a 0-row UPDATE does not throw in Postgres).
  `StaleLockError` is exported from the store module.
- `toJob` maps the new fields (`ownerAccountId`, `poseDraft`, `poseId`, `hiddenAt`). `ExtractionJob.sourceImageBase64` and the row type become
  `string | null` (`extractionJobStore.ts:11`). The worker already guards: an owner job with a null source is never claimable, because
  `claimNext` only picks `queued`/stale `processing` and retry requires a non-null source.
  Because widening the type breaks the strict `tsc` check at its two current consumers, Phase 1 also adds minimal null guards there so the phase
  exits with `npm run lint` green. `job-processor.ts:69`: a null source → `markFailedOrRequeue(..., 'SOURCE_MISSING')` (add the code to `worker/error-codes.ts`). `adminCommunityRoutes.ts:174`: a null
  source → 400 `JOB_NOT_SUCCEEDED`, the same code the route already uses for an unusable job. Phase 2 later replaces both call sites.

`claimNext` needs no change. Retried jobs re-enter through `status='queued'` with `attempts=0`.

## Related Code Files
- Modify: `web/services/pose-extract-server/src/db/schema.sql`
- Modify: `web/services/pose-extract-server/src/db/extractionJobStore.ts`
- Create: `web/services/pose-extract-server/src/db/extractionJobStore.test.ts`
- Modify (null guards only): `src/worker/job-processor.ts`, `src/routes/adminCommunityRoutes.ts`

## Implementation Steps
1. Append the schema delta, then run `connection.test.ts` to prove that applying it twice is safe.
2. Extend the types and row mapping, then add the methods above.
3. Write the store tests with `setupTestDatabase()`: owner isolation, cursor pagination across 25 jobs, state filter,
   hidden jobs excluded, retry from each status, retry of a hidden failed job → `not_found`, hide being idempotent,
   hide of a failed job nulling its source, `markSucceededWithPose` nulling base64, and `markSucceededWithPose` with a stale token throwing
   `StaleLockError` and leaving the row unchanged.

## Success Criteria
- [ ] `npx vitest run src/db` passes.
- [ ] `npm run lint` passes.
- [ ] Existing `job-processor.test.ts` and `worker-loop.test.ts` still pass unchanged.

## Risk Assessment
- `DROP NOT NULL` on an existing Postgres column is safe and idempotent. If PGlite rejects it, the tests show it immediately; fall back to storing `''` and treat empty as null.
