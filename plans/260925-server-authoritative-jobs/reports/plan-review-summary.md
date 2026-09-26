# Plan review summary

Final candidate: plan content sha256 prefix `07101574235649cb` (plan.md + phase-01..06).
Result: **CLEAR** from both independent lenses in cycle 7 (backend `e31b8e56`, iOS + contract `7302bc42`).

## Cycle history
| Cycle | Backend | iOS + contract | Main issues fixed |
|---|---|---|---|
| 1 | CHANGES_REQUIRED | CHANGES_REQUIRED | Stale-lock rollback, deploy order, hidden-job retry; private pose detail, polling dropped finished jobs, scheme, sign-out wiring |
| 2 | CLEAR | CHANGES_REQUIRED | `success` field breaks job decoding |
| 3 | CHANGES_REQUIRED | CHANGES_REQUIRED | `finalize` StaleLockError path, admin metadata, cleanup failure; SignInIntent, guide envelope, skeleton mapping |
| 4 | CLEAR | CHANGES_REQUIRED | Guest guard, fixture bundling, post-sign-in navigation |
| 5 | CHANGES_REQUIRED | CLEAR | Phase 1 could not exit with lint green |
| 6 | CLEAR | CHANGES_REQUIRED | Guest submit error, 202/204 handling, submit failure, `watchJob` offline/retry |
| 7 | CLEAR | CLEAR | — |

From cycle 5 onward, reviews were scoped to plan-level quality (tests, model, cases, verifiability), per the user's direction.

## Non-blocking notes for implementers (cycle 7)
These do not change behavior contracts. Apply them during implementation; they were not written into the frozen plan.
- Phase 3: mount `/api/guides` only when `communityStore` is configured as well.
- Phase 4: `watchJob` treats a 404 as `.gone` whether `PoseAPIError.code` is `NOT_FOUND` or the `"404"` status fallback (`APIClient.swift:73-84`).
- Phase 4: on `SessionEvent.signedIn`, `JobsService` calls `refresh()` so the badge fills in right after sign-in.
- Phase 5: `JobsScreen` takes `onTryPose` from `PosesScreen` and forwards it to `PoseDetailScreen` (`PosesFeature.swift:608`).
- Phase 5: `NativePose` lives in `mobile/iosApp/iosApp/Core/Network/FeatureService.swift`.
- Phase 5: polling stops in `onDisappear` when `PoseDetailScreen` is pushed from Jobs. Check that polling resumes after popping back, and refresh the badge when the Add Pose / sign-in sheets are dismissed.
- Future: a TTL sweep for failed jobs that were never hidden (plan R5).
