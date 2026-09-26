---
phase: 2
title: "Worker materializes Pose"
status: pending
priority: P1
effort: "5h"
dependencies: [1]
---

# Phase 2: Worker materializes Pose

## Overview
When an owner job's extraction succeeds, the worker creates the Pose and three media assets atomically
and then drops the raw payloads. Admin (owner-less) jobs behave exactly as before.

## Requirements
- Functional: exactly one Pose per owner job. The Pose has `status='local'`, `current_job_id=job.id`, and
  name/tags/description taken from `pose_draft`. Three `media_assets` rows (original, skeleton, thumbnail) are `ready`.
- Non-functional: safe when the job is re-claimed after a stale lock, and no orphaned R2 objects are left on the failure path.

## Architecture
Extract the upload-and-insert logic from `routes/adminCommunityRoutes.ts` (lines ~171–205) into
`src/services/poseMaterializer.ts`:
```ts
materializePose({ poseId, ownerAccountId, currentJobId,
  metadata: { name, tags, description, bodyParts?: string[] /* default [] */, difficulty?: PoseDifficulty | null /* default null */ },
  source:{b64,mime}, result:{b64,mime}, keyPrefix: 'community'|'poses', mediaStorage, createPose })
// uploads 3 objects → calls createPose → on error removes uploaded keys (Promise.allSettled) and rethrows
```
The admin route passes its `bodyParts` and `difficulty` unchanged (`adminCommunityRoutes.ts:193-205`, `communityStore.ts:30-42`), so
`adminCommunityRoutes.test.ts` stays green without edits. The worker passes the draft fields and relies on the defaults.

Worker flow in `worker/job-processor.ts`, after `backgroundRemover.removeBackground`:
```
if (!job.ownerAccountId) { markSucceeded(...) ; return }           // legacy admin path unchanged
// safeFinalize(p): db.begin(tx => markSucceededWithPose(tx, job.id, lockToken, p));
//   catches StaleLockError → log + return (the job already belongs to / was finalized by another worker); never requeues.
existing = communityStore.getPoseByCurrentJobId(job.id)
if (existing) { await safeFinalize(existing.poseId); return }      // no upload happened
poseId = randomUUID()
try {
  // materializePose owns upload + allSettled cleanup; createPose callback runs the single transaction
  await materializePose({ …, keyPrefix: 'poses', mediaStorage,
    createPose: input => db.begin(async tx => { const p = await communityStore.createPose(input, tx);
                                                await jobStore.markSucceededWithPose(tx, job.id, lockToken, poseId); return p }) })
} catch (e) {                                                       // keys already removed by materializePose (allSettled, logged)
  if (e is StaleLockError) { log; return }                          // do NOT touch the job
  if (e is unique violation on current_job_id) {
    const winner = await getPoseByCurrentJobId(job.id)
    if (winner) { await safeFinalize(winner.poseId); return }
    // unreachable in practice; fall through to requeue
  }
  await markFailedOrRequeue(job.id, lockToken, 'POSE_MATERIALIZE_FAILED', msg)
}
```
`materializePose` rethrows the original error after cleanup, so the three branches above still see `StaleLockError` or the unique violation.
This owner branch catches all of its own errors, so none can reach the generic `catch` in `processNextJob` (`job-processor.ts:75-77`).
Only provider and background-removal errors, which happen before this branch, reach that catch.
Invariant: R2 keys are removed **only after** the transaction that would have referenced them has rolled back, so a committed
Pose never points at deleted objects.
Add `POSE_MATERIALIZE_FAILED` to `worker/error-codes.ts`. `communityStore.createPose` has to accept an
optional transaction handle; add the parameter without changing any existing caller.
The unique index `idx_poses_current_job_id` is the final guard against duplicates. When the insert raises
a unique violation, re-read the Pose by `current_job_id` and finalize with it.

`processNextJob` gets `communityStore`, `db` and a `mediaStorage: { put(key, body, mime), remove(key), publicUrl(key) }` injected.
`worker-main.ts` wires them in, building `mediaStorage` from `r2Storage.ts` (`uploadObject`, `deleteObject`, `buildPublicUrl` with
`R2_PUBLIC_URL`), matching how `app.ts:205-215` wires the admin community route (`publicUrlBase: process.env.R2_PUBLIC_URL`). The worker process therefore needs the `R2_*` env vars. Add them to the worker service
config and `railway.toml` or the deploy notes. Check that
`WORKER_STALE_LOCK_SECONDS` (default 120) exceeds the p95 provider time plus about 10 s of upload. If it does not,
raise the default and note that in the phase handback.

## Related Code Files
- Create: `web/services/pose-extract-server/src/services/poseMaterializer.ts`, `poseMaterializer.test.ts`
- Modify: `src/worker/job-processor.ts`, `src/worker/job-processor.test.ts`, `src/worker/worker-main.ts`, `src/worker/error-codes.ts`,
  `src/worker/worker-loop.ts` (+ `worker-loop.test.ts`): `WorkerLoopDeps` forwards `communityStore`, `db` and `mediaStorage` to `processNextJob`
  (`worker-loop.ts:30-58` currently passes only `jobStore`, `providerSettingsStore`, `createProvider` and `staleLockSeconds`)
- Modify: `src/routes/adminCommunityRoutes.ts` (use the materializer, same behavior), `src/db/communityStore.ts` (optional tx param)

## Implementation Steps
1. Extract the materializer and switch the admin route to it. `adminCommunityRoutes.test.ts` must stay green before continuing.
2. Add the owner branch to `processNextJob`, with R2 stubbed through the existing `r2Storage` mocking style.
3. Tests: owner success creates 1 pose + 3 assets and nulls base64; a second run on the same job (simulated re-claim) creates no second pose;
   an upload failure removes the uploaded keys and requeues with `POSE_MATERIALIZE_FAILED`; admin jobs keep `result_image_base64`;
   **stale lock** (the token is changed before finalize) → the transaction rolls back, no Pose row remains, the uploaded keys are removed, and the job row stays untouched;
   **unique collision** (a Pose with the same `current_job_id` is pre-inserted) → the loser's keys are removed and the job is finalized to the existing `poseId`;
   **existing Pose + stale token** (the Pose exists and the job's `lock_token` is NULL or different) → no `markFailedOrRequeue` call, and the job stays `succeeded`;
   **cleanup failure** (`mediaStorage.remove` rejects) → the job is still requeued with `POSE_MATERIALIZE_FAILED` and the rejection is logged.

## Success Criteria
- [ ] `npx vitest run src/worker src/services/poseMaterializer.test.ts src/routes/adminCommunityRoutes.test.ts` passes.
- [ ] `npm run lint` passes.

## Risk Assessment
- The stale lock expires mid-upload and a second worker re-claims the job → `StaleLockError` rolls back the loser's transaction, and only then are its
  keys removed; the unique index makes sure at most one Pose commits. This is covered by the two race tests above.
- R2 is not configured in an environment → the materializer throws, the job requeues, and after max attempts it ends `failed` with a clear code. The worker must log it.
