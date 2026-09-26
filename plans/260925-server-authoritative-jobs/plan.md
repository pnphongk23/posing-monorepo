---
title: "Server-authoritative extraction Jobs — backend + iOS"
status: pending
priority: P1
created: 2026-09-25
updated: 2026-09-26
blockedBy: []
blocks: []
---

# Server-authoritative extraction Jobs — backend + iOS

Supersedes decision 1 ("Jobs stored locally") and sign-out policy B of
`plans/260924-1738-feat-004-005-design-closure/shared-contract.md` (user-approved option A,
2026-09-25). The docs and prototype streams already landed (uncommitted) and are the product contract:
`docs/harness/specs/api/openapi.yaml`, `docs/harness/specs/data-contract.md`,
`docs/harness/designs/basic-design/screens/mobile/scr-004-01-add-pose.md`,
`docs/harness/designs/basic-design/screens/mobile/scr-005-01-jobs.md`, `docs/prototype/screens/{add-pose,jobs}.html`.

## Outcome
The iOS app stores no extraction jobs. `pose-extract-server` owns job state for each account.
When extraction succeeds, the worker creates the Pose and its three media assets. The native Add Pose
and Jobs screens read and write only through the server.

## Non-goals
- Cancel API, push notifications, offline submit queue, local jobs cache.
- Publishing or editing a Pose (`/api/guides` PATCH/publish/etc.). This plan mounts only `GET /api/guides/:id`.
- Android/KMP and web user UI.
- Changing the admin community intake flow beyond keeping it working.

## Key decisions (made while planning, reversible)
| # | Decision | Why |
|---|---|---|
| D1 | Materialize the Pose **inside the worker, before** the job is marked `succeeded`. The worker uploads media to R2, then one DB transaction inserts `poses` + `media_assets`, sets `extraction_jobs.pose_id`, `status='succeeded'`, and nulls both base64 columns. A failed upload or insert goes through the existing `markFailedOrRequeue` with code `POSE_MATERIALIZE_FAILED`. | This keeps each job atomic: a user job can never be `succeeded` without a Pose, so no sweeper is needed. |
| D2 | Idempotency comes from the existing unique index `idx_poses_current_job_id`. Before uploading, the worker checks `getPoseByCurrentJobId(job.id)`. If a Pose already exists, it only finalizes the job. | This covers the stale-lock re-claim case. |
| D3 | Reuse the admin materialization code: extract `services/poseMaterializer.ts` from `routes/adminCommunityRoutes.ts` and have both callers use it. | DRY; that code is already tested. |
| D4 | Pose media goes to the same R2 bucket at the unguessable key `poses/{poseId}/{role}.{ext}` with public-URL locators, the same way community media is stored. | Matches existing infra. The privacy trade-off is recorded as risk R3. |
| D5 | Auth on `POST /api/extract-pose`: an **AccountSession** creates an owner-scoped job, and the draft is required. An **AdminBearer** creates an owner-less job with the draft optional; that is the legacy admin path, which keeps base64 and is never auto-materialized. Admin-ui's proxy starts sending the admin bearer. Anonymous requests get 401. | This keeps the admin community intake working. |
| D6 | `GET /api/extract-jobs/:id` uses the same dual auth. Account callers must own the job, otherwise 404. For owner jobs, `result` is always `null` after materialization and clients use `poseId`. | This matches openapi `ExtractionJobPublic` and the retention rule. |
| D7 | `ExtractionJobListItem` gets a nullable `thumbnailUrl` (the Pose thumbnail once `Ready`, otherwise `null`). Rows without a thumbnail show a placeholder. This is a small additive contract change, and Phase 3 syncs openapi and api-contract for it. | Without local photo copies, the server is the only thumbnail source. |
| D8 | Retry (`POST /api/me/extract-jobs/:id/retry`) is only allowed from `failed`. It resets `attempts=0`, clears the error, and sets `status='queued'`. Failed owner jobs keep `source_image_base64`, so a retry has input. | BR-JOB-002 stays valid, and the user gets the full attempt budget again. |
| D9 | While the Jobs screen is visible, iOS polls `GET /api/me/extract-jobs?limit=50` (no `state` filter) every 5 s and splits the rows by status on the client. That way a job moving from active to finished appears under Finish in the same refresh. The Add Pose processing surface polls `GET /api/extract-jobs/:id` for the one submitted job. The badge refreshes when Poses appears and when the app returns to the foreground. There is no background polling. | Polling only `?state=active` would drop finished jobs (review finding). |
| D10 | `/api/me/*` accepts **AccountSession only**. Phase 3 removes `AdminBearer` from those operations in openapi. | Admins have no "me". |
| D11 | Hiding a `failed` job also nulls `source_image_base64`. Hidden jobs cannot be retried (the API returns 404). | A hidden job would otherwise keep ~10 MB in the DB forever. |
| D12 | iOS keeps its deployment target at 15.0. The photo picker is a `PHPickerViewController` wrapper (iOS 14+), not `PhotosPicker` (iOS 16). | Avoids raising the minimum OS. |
| D13 | Private poses open in `PoseDetailScreen` with an `isPrivate` flag that skips the `confirmPublished` check, which only knows about community and saved poses. | Otherwise a freshly created pose shows as unavailable (review finding). |

## Phases
| # | Phase | Owner area | Depends | Status |
|---|---|---|---|---|
| 1 | [Server data + job store](phase-01-server-data-and-store.md) | `web/services/pose-extract-server/src/db` | — | pending |
| 2 | [Worker materializes Pose](phase-02-worker-materialize-pose.md) | `src/worker`, `src/services` | 1 | pending |
| 3 | [Server API + admin proxy](phase-03-server-api-and-admin-proxy.md) | `src/routes`, `src/app.ts`, admin-ui proxy, openapi delta | 1 | pending |
| 4 | [iOS networking + jobs service](phase-04-ios-networking-and-jobs-service.md) | `mobile/iosApp/iosApp/Core/Network`, `Features/Jobs` (service) | 3 (contract) | pending |
| 5 | [iOS Add Pose + Jobs UI](phase-05-ios-add-pose-and-jobs-ui.md) | `Features/Jobs`, `Features/Poses` (unit tests + stubbed previews; live run is Phase 6) | 4 | pending |
| 6 | [End-to-end verification + docs sync](phase-06-e2e-verification-and-docs.md) | tests, docs | 2, 3, 5 | pending |

Phases 2 and 3 can run in parallel after 1: their write-sets do not overlap, and `app.ts` belongs only to Phase 3.
Phase 4 can start against the openapi contract once Phase 3's route signatures are frozen.

## Acceptance (mission level)
- `npm test` and `npm run lint` pass in `web/services/pose-extract-server`, including the new tests listed in each phase.
- Owner isolation: account B gets 404 on A's job for GET/retry/DELETE, and A's list never shows B's jobs (integration test).
- A succeeded owner job has exactly one Pose even when the worker processes it twice (test).
- A succeeded owner job has `source_image_base64` and `result_image_base64` set to NULL.
- The admin community intake (extract → poll → `POST /api/admin/community/poses`) still works (existing tests stay green, and the proxy sends the bearer).
- iOS: `xcodebuild test` on the `Dev` scheme passes, and the new unit tests cover the Jobs view-model state mapping and polling lifecycle.
- iOS has no `JobRecord` table or new local job persistence; `grep` for `JobRecord|localIntentId` in `mobile/` returns 0.
- On the simulator, a manual end-to-end run of Add Pose → Jobs `Queued/Processing` → `Ready` → `View pose` works, and a reinstall shows the same jobs after sign-in.

## Risks
- R1 A long provider run holds the job lock while R2 uploads run → the upload happens inside the same claim, and the stale-lock window (`staleLockSeconds`) must exceed provider time plus upload time. Phase 2 checks the configured value.
- R2 **Deploy order (mandatory): 1) `web/admin-ui` proxy with the bearer patch; 2) `pose-extract-server` (schema, worker, API); 3) iOS build.**
  The admin-ui patch is backward compatible because the current server ignores the extra header. Deploying the server before admin-ui would break admin intake with 401.
  The server must also ship before the iOS build that sends drafts. Old app builds keep calling `/api/extract-pose` without auth and will get 401. Accept this: the feature is unreleased, and a grep shows the current iOS code has no Add Pose UI.
- R3 Public R2 URLs for private poses stay reachable to anyone who has the URL. This is accepted for now because keys are UUIDs and match the community pattern. If that is not acceptable, switch to presigned GET later (only D4 changes).
- R4 The schema is applied idempotently from `schema.sql` (no migration tool), so new columns use `ALTER TABLE … ADD COLUMN IF NOT EXISTS`. Signal it broke: `connection.test.ts` fails on a re-apply.

- R5 Failed jobs that are never hidden keep `source_image_base64` (needed for Retry). FUTURE: a TTL purge for failed jobs older than N days. This is out of scope for this plan.

## Open questions
None.
