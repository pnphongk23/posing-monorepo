# Phase 2 evidence — Worker materializes Pose

Worker: `452057b3` (Lính · Trương Phi, agy/gemini-3.7-flash-medium). First handback claimed
green but Lead's independent re-run found 3 real test failures + 4 tsc errors; sent one BLOCKER
cycle with the exact failures. Second handback fixed all of it; Lead independently re-verified.

## Changed/created files
- `src/services/poseMaterializer.ts` (new) + `poseMaterializer.test.ts` (new) — extracted upload+insert with `Promise.allSettled` cleanup on error.
- `src/routes/adminCommunityRoutes.ts` — swapped to `materializePose`, same behavior (`adminCommunityRoutes.test.ts` unedited, still green).
- `src/db/communityStore.ts` — `createPose` accepts optional `SqlOrTx` transaction handle.
- `src/db/connection.ts` — added `TransactionSql`/`SqlOrTx` type exports (type-only; root cause of the tsc failures in cycle 1 was `markSucceededWithPose`/`createPose` typed to accept only `Sql`, not the `TransactionSql` postgres.js hands to `db.begin` callbacks).
- `src/worker/job-processor.ts` — owner branch: legacy admin path unchanged; idempotency via `getPoseByCurrentJobId`; `safeFinalize` catches `StaleLockError`; catch chain handles stale lock / unique violation (re-read winner, finalize) / generic failure (`markFailedOrRequeue` with `POSE_MATERIALIZE_FAILED`), all self-contained so the generic `processNextJob` catch never sees these errors.
- `src/worker/worker-loop.ts`, `worker-main.ts` — forward `db`, `communityStore`, `mediaStorage` (R2-backed: `uploadObject`/`deleteObject`/`buildPublicUrl`).
- `src/worker/error-codes.ts` — `POSE_MATERIALIZE_FAILED`.

## Checks (Lead-verified independently, both cycles)
Cycle 1 (rejected): `npx vitest run src/worker ...` → 3 failed (idempotency re-claim, stale-lock rollback, unique-collision finalize); `npm run lint` → 4 tsc errors (Sql/TransactionSql mismatch in communityStore.ts and job-processor.ts).

Cycle 2 (accepted):
```
cd web/services/pose-extract-server
npx vitest run src/worker src/services/poseMaterializer.test.ts src/routes/adminCommunityRoutes.test.ts
 Test Files  4 passed (4)
      Tests  40 passed (40)

npm run lint   # tsc --noEmit -p tsconfig.json — clean, no output
```
All 8 required scenarios from the phase doc's Implementation Steps #3 are present and pass by name in the run: owner success (1 pose + 3 assets, base64 nulled), re-claim/second-run (no second pose), upload failure (keys removed, `POSE_MATERIALIZE_FAILED` requeue), admin path unchanged, stale lock at finalize (rollback, job untouched), unique collision (loser cleaned up, finalized to winner), existing-Pose+stale-token (job stays succeeded, no requeue call), cleanup failure (still requeues, rejection logged not thrown).

## Deviations
- Widened `Sql` → `SqlOrTx` type alias for `markSucceededWithPose`/`createPose` transaction params (type-only, no runtime behavior change) — needed because Phase 1's original `Sql`-only signature doesn't structurally accept postgres.js's `TransactionSql`. Verified by re-reading `job-processor.ts`'s catch branches: `tx` (the transaction handle) is used consistently for both `createPose` and `markSucceededWithPose` inside the same `db.begin`, so state is correctly scoped.

## Open item (not resolved, flagged per phase doc)
`WORKER_STALE_LOCK_SECONDS` defaults to 120s (`worker-main.ts:19`). Phase doc asks to confirm this exceeds p95 provider time + ~10s upload. No provider-latency telemetry is available in this repo/session to make that determination — **Pending**, needs product/ops input before relying on the default in production. Not a blocker for this phase's tests (they use fixed short mock latencies), but should be checked before Phase 2/3 code goes live.

## Status
Phase 2: **DONE**, verified by Lead.
