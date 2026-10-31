# Release test matrix — 4 business flows

Read-only QA audit of `main` @ `c05930b` (2026-10-31). Scope: purchase, extract pose, save pose, job status.
Layers checked: `mobile/iosApp/iosAppTests` (XCTest), `mobile/iosApp/maestro/flows` + `docs/qa/test-cases/*.md` (TC ids / traceability), `web/services/pose-extract-server/src/**/*.test.ts` (server).

Status meaning: **COVERED** = an existing test asserts the stated behaviour at the named layer and I opened it to confirm.
**PARTIAL** = a test asserts part of the behaviour; the unasserted part is named. **MISSING** = no test, file names notwithstanding.
Existing TC ids are reused; `NEW-nn` are proposed ids (not yet in `docs/qa/test-cases`). Empty cells in "Existing coverage" are the gap.

Known limits carried into every flow: no camera in the Simulator (capture is device-only); only the `ai-pose-test` iPhone 16 sim is configured; purchase E2E still needs a real RevenueCat Dev key + product ids (`Config/Dev-Debug.xcconfig` still ships the `REPLACE_WITH_…` placeholder, and no `*.storekit` file exists in the repo).

Known risk carried into this release: `extractPoseEnabled` is client-only; server accepts direct POST — accepted for this release (prod flag ON).

## Summary

| Flow | Cases | Covered | Partial | MISSING |
|---|---|---|---|---|
| 1. Purchase | 8 | 5 | 3 | 0 |
| 2. Extract pose (Add pose + consent + job) | 6 | 4 | 0 | 2 |
| 3. Save pose | 6 | 3 | 2 | 1 |
| 4. Job status (Jobs screen) | 6 | 3 | 3 | 0 |
| **Total** | **26** | **15** | **8** | **3** |

## 1. Purchase

| ID | Pri | Case | Preconditions / expected | Layer | Existing coverage | Status |
|---|---|---|---|---|---|---|
| TC-PAY-004 | P0 | Happy path (buy annual) | Signed in, real Dev key + products; sheet closes, entitlement granted, capture succeeds | XCTest + manual-device | `Features/PaywallModelTests.swift:164 testPurchaseConfirmsEntitlement`; `Services/RevenueCatAdapterTests.swift:322 testPurchaseOfLoadedPackageConfirmsEntitlement` — model/adapter only, no store | PARTIAL (E2E blocked: placeholder key, no `.storekit`) |
| NEW-01 | P1 | User cancels purchase | Signed in, plan picked; cancel → sheet stays, no access, "Purchase cancelled. No access was granted.", gate stays fail-open | XCTest | `Features/PaywallModelTests.swift:179 testCancelledPurchaseNeverReportsAccess`; `Services/RevenueCatAdapterTests.swift:591 testCancelledPurchaseKeepsTheCancelledKind` | COVERED |
| NEW-02 | P1 | Purchase fails | Store returns an error → retryable error, plans kept, no access | XCTest | `Features/PaywallModelTests.swift:193 testFailedPurchaseIsRetryableAndKeepsPlans`; `Services/RevenueCatAdapterTests.swift:582 testErrorMappingKeepsTheFailureKind` | COVERED |
| NEW-03 | P1 | Pending / ask-to-buy (deferred) | Store defers the transaction → no access, camera stays usable, sheet does not wedge | XCTest | `Features/PremiumGateTests.swift:123 testG7UnknownAndTransientStatesFailOpen` (`.purchasePending` → `.capture`). No test makes the store return `.pending`; `PaywallModel` ignores the state (`PaywallModel.swift:286,332`) and no pending UI is asserted | PARTIAL |
| NEW-04 | P1 | Restore purchases | Signed in, prior purchase; restore grants access, failure is reported not silent | XCTest | `Features/PaywallModelTests.swift:235 testRestoreUsesGatewayAndCanGrantAccess`; `Services/RevenueCatAdapterTests.swift:604 testRestoreFailureKeepsTheFailureKind` | COVERED (model layer) |
| NEW-05 | P1 | Expired entitlement | Subscriber whose entitlement lapsed → paywall + can buy again; capture gated | XCTest | `Features/PaywallModelTests.swift:249 testExpiredEntitlementCanBuyAgain`; `Services/RevenueCatAdapterTests.swift:553 testInactiveEntitlementWithPastExpiryIsExpired`; `Features/PremiumGateTests.swift:134` (`.expired` → paywall) | COVERED |
| TC-PAY-006 | P0 | Second account on same device | A entitled → sign out → sign in B → B is gated until B's own confirmed answer; nothing carried over | XCTest (+ E2E pending) | `Features/PremiumGateModelTests.swift:233 testAnotherAccountIsGatedOnlyAfterItsOwnConfirmedAnswer`, `:261` (B's own entitled captures); `Services/RevenueCatAdapterTests.swift:364,786,817` | PARTIAL (no E2E, no store) |
| NEW-06 | P0 | Gate fail-open: purchases unconfigured / accounts off | Kill switch on, but build cannot sell or accounts off → shutter captures, no paywall | XCTest | `Features/PremiumGateTests.swift:54 testG3UnconfiguredPurchasesAllowCapture`, `:59 testG3AccountsUnavailableAllowCapture`, `:66 testG1IsDecidedBeforeG3`; `Features/PremiumGateDebugOverrideTests.swift:96,107` | COVERED |

## 2. Extract pose (Add pose + consent + job)

| ID | Pri | Case | Preconditions / expected | Layer | Existing coverage | Status |
|---|---|---|---|---|---|---|
| TC-EXT-001 | P0 | Consent cancelled | Add pose → consent sheet → Cancel → no upload, no job, draft kept, asked again next time. Copy: "To extract the pose, your photo is sent to a third-party AI service. The pose created from it is saved privately to your account until you delete your account." | Maestro (drafted) | — consent surface not in `iosApp/` yet (Feature S1); case + flow drafted in `docs/qa/test-cases/extract-jobs.md` | MISSING (blocked on S1 ids `addPose.consent.*`) |
| TC-EXT-002 | P0 | Consent allowed | Allow → one upload → job appears in Jobs > Processing; answer remembered per account (asked once) | Maestro (drafted) | — same as TC-EXT-001 | MISSING (blocked on S1 ids + consent reset) |
| NEW-09 | P1 | Upload failure | Photo too large / wrong type / 5xx → error copy, draft preserved, no job created | XCTest + server | `Features/AddPoseFormTests.swift:88 testSubmitFailurePreservesFormDraftAndSetsError` (offline, invalidImage, invalidMetadata, 5xx, sign-in); `src/services/poseMaterializer.test.ts:133` (upload fails → keys cleaned, rethrow) | COVERED |
| NEW-10 | P1 | Offline submit | Airplane mode on Add pose → "You're offline. Check your connection.", draft kept, retry works online | XCTest | `Features/AddPoseFormTests.swift:88` (offline branch: `isOffline`, copy, draft, 1 attempt) | COVERED |
| TC-EXT-003 | P0 | `extractPoseEnabled` off: Add pose hidden + network blocked | Launch `-AIPoseExtractPoseEnabled false` → no Add pose (Home header, Gallery header, empty Jobs CTA), no submit/retry request | Maestro + XCTest | `maestro/flows/TC-EXT-003-extract-flag-off.yaml`; `DesignSystem/APShellTests.swift:38 testAddPoseIsShownOnlyWhileExtractionIsEnabled`; `Features/GalleryFeatureTests.swift:89 testGalleryAddPoseIsHiddenByTheRemoteFlag` (+`:98` pixel proof); `Features/AddPoseFormTests.swift:139 testExtractKillSwitchBlocksFormAndSubmitThenAllowsWhenEnabled` (submitCallCount stays 0); `Features/JobsServiceTests.swift:262 testExtractKillSwitchBlocksServiceRetryWithoutRequest`; `Services/AppConfigTests.swift:21,26,49,54`; `Services/AppConfigServiceTests.swift:124,428` | COVERED client-side. Server does **not** enforce the flag (no `extractPoseEnabled` in `src/`), so a direct POST is still accepted — known risk, accepted for this release (prod flag ON) |
| NEW-12 | P1 | Job failed + retry | Job fails with an error → row shows the failure, Retry re-queues; retry blocked when extraction is off | XCTest + server | `Features/AddPoseProcessingTests.swift:44 testProcessingLifecycleThroughEvents` (failed → `processingError`, retry called, gone); `src/routes/myExtractJobsRoutes.test.ts:116` (requeued / not_found / not_retryable); `src/worker/job-processor.test.ts:129,153` (requeue vs exhausted) | COVERED (no UI-level flow) |

## 3. Save pose

| ID | Pri | Case | Preconditions / expected | Layer | Existing coverage | Status |
|---|---|---|---|---|---|---|
| TC-SAV-001 | P0 | Signed-out gate on Saved | Accounts on, signed out → More → Saved → sign-in prompt, no saved list | Maestro | `maestro/flows/TC-SAV-001-saved-signed-out.yaml` (`saved.signIn`); copy pinned by `Features/FeatureStateTests.swift:565,575` | COVERED |
| NEW-21 | P0 | Signed-out gate on the detail CTA | Signed out → pose detail → "Save pose" → sign-in prompt; pose not shown as saved | XCTest | — `PosesFeature.swift:1764` sets `pendingSignIn = .savePose`, no test asserts it; no Maestro flow | MISSING |
| TC-SAV-002 | P1 | Save | Signed in → Save pose → label flips only after the server confirms, pose appears in Saved | XCTest (+ E2E pending) | `Features/PoseDetailFeatureTests.swift:725 testToggleSavedFlipsOnlyAfterTheServerConfirms`, `:23 testLocalBookmarkToggleUpdatesViewModelState`; `Features/PosesAdapterTests.swift:462 testBookmarkToggleUpdatesCatalogCacheWithoutRefetching` | COVERED (unit; TC-SAV-002 still pending) |
| TC-SAV-003 | P1 | Unsave | Signed in, saved pose → Unsave → row removed from Saved, paging cursor sane | XCTest (+ E2E pending) | `Features/PoseDetailFeatureTests.swift:283` (unsave after confirmed save, one request each); `Features/PosesAdapterTests.swift:462` (unsave leaves the saved feed without a refetch) | COVERED (unit; TC-SAV-003 still pending) |
| NEW-23 | P1 | Offline save failure → snackbar at the bottom, above the CTA | Offline → tap Save → pose stays unsaved, snackbar "You're offline. Try again when connected." at the bottom above the pinned CTA, auto-dismisses | XCTest | Copy + no local flip: `Features/PoseDetailFeatureTests.swift:361 testToggleSavedOfflineKeepsThePoseUnsavedAndSaysSo`. Placement proved only on the Saved panel, not the detail screen: `DesignSystem/APDetailSavedTests.swift:65 testHostedSavedSurfaceShowsTheUnsaveFailureOnAnEmptyPanel`; dismissal: `:111` | PARTIAL (detail-screen placement unasserted) |
| NEW-24 | P1 | Sync after re-login | Sign out → sign in again → Saved reflects the account (no stale rows, no leakage, server re-read) | XCTest | `Features/PosesSessionBoundaryTests.swift:190 testSavedListIsDroppedAndRereadForTheNextAccount` (A→B); `Features/PosesAdapterTests.swift:1010,1044` (write in flight across a switch); `src/routes/savedRoutes.test.ts:26,39,49` | PARTIAL (same-account sign-out→sign-in not exercised) |

## 4. Job status (Jobs screen)

| ID | Pri | Case | Preconditions / expected | Layer | Existing coverage | Status |
|---|---|---|---|---|---|---|
| TC-JOB-001 | P0 | Finished → private detail | After a succeeded job the Jobs row offers "View pose", which opens the PRIVATE pose detail: "Try this pose" works, no Save button (`poseDetail.saveButton` absent), and the pose appears neither in Saved nor in Community (`status: local`; Saved lists only `published`) | Maestro (drafted) + XCTest + server | `Features/JobsServiceTests.swift:309 testJobMovingFromProcessingToSucceededMovesToFinished`; `Features/JobsScreenModelTests.swift:127`; `Features/Poses/PosesFeature.swift:1655` (`!isPrivate` hides Save); `src/routes/guideReadRoutes.ts:35-48` (owner-only read); `src/db/savedStore.ts:70-120`; `plans/260925-server-authoritative-jobs/phase-02-worker-materialize-pose.md:17` | COVERED (server/app by design; Maestro flow drafted) |
| TC-JOB-002 | P0 | Processing | One queued + one processing job → Processing tab lists both, in-progress count = 2, polling starts on appear | XCTest | `Features/JobsServiceTests.swift:286 testRefreshSplitsInProgressAndFinished` (`activeCount == 1`), `:309`; `Features/JobsSnapshotTests.swift:111 testCaptureJobsProcessingScreenshot` (renders; asserts stub data, not chrome); `src/routes/myExtractJobsRoutes.test.ts:53` (list/filters) | COVERED (service); screen chips/tabs only visually rendered |
| TC-JOB-003 | P0 | Failed | Failed job → Finish tab with the error message, Retry offered, watch terminates | XCTest + server | `Features/JobsServiceTests.swift:131 testDecodeFailedJobStatusWithError`, `:449 testWatchJobTerminatesOnFailed`; `Features/JobsSnapshotTests.swift:129` (failed row); `src/routes/extractJobsRoutes.test.ts:270` (failure details) | COVERED |
| TC-JOB-004 | P1 | Empty | No jobs → "No jobs yet" + Add pose action only while extraction is on | XCTest | `Features/JobsScreenModelTests.swift:162 testJobsScreenEmptyStateWhenStubHasNoRows` — asserts the stub is empty, not the empty-state copy/action; `Features/JobsSnapshotTests.swift:147` renders only | PARTIAL |
| TC-JOB-005 | P1 | Offline | Airplane mode → cached rows stay, "You're offline — statuses update when you're back online." banner, clears when back online | XCTest | `Features/JobsServiceTests.swift:495 testOfflineNetworkErrorPreservesCachedJobsAndSetsOffline`, `:523`, `:420`; banner copy/layout in `Features/Jobs/JobsScreen.swift:184,208` is untested; `Features/JobsSnapshotTests.swift:162` renders only | PARTIAL (state covered, banner not asserted) |
| TC-JOB-006 | P2 | Running-count badge on the More menu, no count text elsewhere | Processing jobs > 0, signed in → one pink badge with the number on the Jobs row; no numbers in other row titles; 0 → badge hidden; signed out → hidden | XCTest | `DesignSystem/APShellTests.swift:45 testMoreMenuRowsCarryNoSubtitleCounts` only proves row titles carry no digits. Badge drawing/hiding (`Features/Poses/APMoreMenu.swift:57,158-167`) and the signed-out zeroing are untested | PARTIAL |

## Prioritised MISSING / gap packets

Ordered P0 → P2. Each packet is one line: what to assert, layer, and what Feature must add.

1. **TC-EXT-001 / TC-EXT-002 — Add-pose consent (P0, MISSING until S1 builds).** Consent is in scope and its code is written (S1, not yet built): copy frozen, ids frozen (`addPose.consent.message` / `addPose.consent.allowButton` / `addPose.consent.cancelButton`), ack per account in UserDefaults (so `clearState: true` resets it), trigger = `addPose.submitButton` with a valid form and no ack. Cases + flows are written in `docs/qa/test-cases/extract-jobs.md`; they turn green once a build carries S1 and `E2E_EMAIL`/`E2E_PASSWORD` are supplied.
2. **NEW-13 — RESOLVED 2026-10-31: server is correct by design.** A finished job materialises a pose with `status: 'local'` and the owner reads it through Jobs → "View pose", which opens the PRIVATE pose detail (Try this pose works, no Save, not in Saved, not in Community). No server change; the acceptance is now a step inside TC-JOB-001 (`docs/qa/test-cases/extract-jobs.md`).
3. **NEW-21 — Signed-out Save pose gate on the detail CTA (P0, MISSING).** XCTest in `Features/PoseDetailFeatureTests.swift`: signed-out tap sets the pending sign-in prompt and never calls the bookmark service; needs a testable seam for `pendingSignIn` (currently `@State` in the detail view) plus a Maestro id on the prompt if E2E is wanted.
4. **TC-PAY-004 / TC-PAY-006 — Purchase E2E (P0, PARTIAL, blocked).** Needs a real Dev RevenueCat key + entitlement id + two products and a `.storekit` file for the Dev scheme (blockers 1–2 of `purchase-e2e-blockers.md`; blockers 3 and 5 there are now stale — the paywall gate and `-AIPosePaywallEnabled` exist). Then extend `maestro/flows` with buy → close → capture and A→sign-out→B.
5. **NEW-23 — Offline save snackbar position on the detail screen (P1, PARTIAL).** Add an `APViewProbe` render of `PoseDetailScreen` with `bookmarkError` set and assert the error glyph rows sit in the bottom third above the pinned CTA (mirror `APDetailSavedTests.swift:65`).
6. **NEW-24 — Same-account sign-out → sign-in sync (P1, PARTIAL).** Add one XCTest: save, sign out, sign in as the same account, Saved re-reads from the server and shows the pose once (no duplicates), reusing `PosesSessionBoundaryTests` fixtures.
7. **NEW-03 — Store-deferred purchase (P1, PARTIAL).** Fake-gateway test returning `.purchasePending` from `purchase()`: no access, sheet stays usable, camera captures; plus whatever copy Product wants while waiting.
8. **TC-JOB-004 / TC-JOB-005 — Jobs empty + offline chrome (P1, PARTIAL).** Assert the empty-state title/action and the offline banner copy through `APViewProbe`/an accessibility query instead of only rendering a stub. Maestro versions are cut (no seeded jobs / no per-app network drop).
9. **TC-JOB-006 — More-menu badge (P2, PARTIAL).** Assert `jobsBadge` is hidden at 0, painted once with the count otherwise, and is `accessibilityHidden` while the row label carries "N active"; confirm with Product that the count bubble also allowed on the Jobs tab (`Features/Jobs/JobsScreen.swift:138`) does not violate "badge only".
