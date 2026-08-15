---
schema_version: 1
title: Feature Gap and Release Readiness Audit
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[product-feature-inventory]]"
    - "[[ui-ux-system]]"
  decisions: []
  plans: []
  reports:
    - "[[REP-001-project-documentation-and-harness-baseline|REP-001]]"
  rules: []
  features:
    - "[[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]"
    - "[[FEAT-002-manage-a-local-photo-gallery|FEAT-002]]"
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
  source_paths:
    - mobile/composeApp
    - mobile/shared
    - mobile/iosApp
    - web/services/pose-extract-server
    - web/admin-ui
type: report
id: REP-002
status: completed
delivered: 2026-08-09
---

# REP-002: Feature Gap and Release Readiness Audit

## Delivered outcome

A read-only audit compared FEAT-001 through FEAT-005 with the current mobile,
backend, worker, admin UI, and test implementations. The review identified one
critical broken delivery pipeline and several high-priority contract, lifecycle,
and recovery gaps. No Feature approval or implementation state was changed.

## Executive verdict

| Feature | Readiness | Primary reason |
| --- | --- | --- |
| FEAT-001 — Capture a Photo on Mobile | Conditional | Capture can remain in flight indefinitely; filenames can collide; file and database persistence are not atomic; frame ratio is UI-only. |
| FEAT-002 — Manage a Local Photo Gallery | Blocked | Delete removes metadata but leaves the image file, and Photos export can report false success. |
| FEAT-003 — Browse and Use Pose References | Blocked | Production JSON/error contracts can reject server responses; load failures are hidden; community selection is not wired. |
| FEAT-004 — Extract Reusable Pose Images | Blocked | Client/server errors disagree, the documented invocation state is stale, and abuse/accounting boundaries are incomplete. |
| FEAT-005 — Administer Extraction and Community Content | Blocked | The asynchronous worker result is not linked or uploaded to the public community asset. |

## Prioritized backlog

### GAP-001 — Community extraction does not produce the published R2 asset

- **Features:** FEAT-003, FEAT-005
- **Severity:** P0 release blocker when community publishing is enabled
- **Confidence:** High
- **Evidence:** `web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts:148-166` enqueues source bytes and creates a pose containing a synthesized public R2 URL. `web/services/pose-extract-server/src/worker/job-processor.ts:20-26` stores extracted base64 only in the job. `web/services/pose-extract-server/src/db/schema.sql:49-64` contains no `pose_id` or `file_key` linkage.
- **Consequence:** A record may be publicly listed while its `imagePath` points to an object that was never uploaded.
- **Next action:** Define a durable job-to-pose/file-key relationship. Upload the result to R2 before marking the job ready, then allow an explicit ready-to-published transition.

### GAP-002 — Production community JSON decoding differs from tests

- **Features:** FEAT-003
- **Severity:** P1
- **Confidence:** High, with one runtime-default caveat recorded below
- **Evidence:** `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PosesScreen.kt:85-88` installs `json()` without an explicit unknown-field policy. `mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt:25-33` models fewer fields than `web/services/pose-extract-server/src/db/communityStore.ts:138-151` returns. The test client explicitly enables `ignoreUnknownKeys` at `PoseApiServiceTest.kt:19-26`, unlike production.
- **Consequence:** A valid server response containing fields such as `description`, `bodyParts`, `status`, `uploadedAt`, or `downloadCount` can fail to deserialize instead of rendering the catalog.
- **Next action:** Share an explicit JSON configuration and add a contract test using the real server response shape.

### GAP-003 — Mobile and server error envelopes conflict

- **Features:** FEAT-003, FEAT-004
- **Severity:** P1
- **Confidence:** High
- **Evidence:** `PoseApiService.kt:48-52` expects root-level `code` and `message`; `web/services/pose-extract-server/src/app.ts:185-200` emits `{ error: { code, message } }`. The current mobile test at `PoseApiServiceTest.kt:55-74` mocks the obsolete flat shape.
- **Consequence:** `ALL_KEYS_EXHAUSTED`, `INVALID_IMAGE`, and other actionable errors become generic HTTP failures, invalidating the documented recovery UX.
- **Next action:** Adopt one shared error DTO and add client tests for actual Express error payloads.

### GAP-004 — Gallery deletion leaves private image files behind

- **Features:** FEAT-001, FEAT-002
- **Severity:** P1
- **Confidence:** High
- **Evidence:** `mobile/shared/src/commonMain/kotlin/com/aipose/data/PhotoRepository.kt:35-37` deletes only the SQL row, while `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/PhotoDetailDialog.kt:164-175` promises permanent deletion.
- **Consequence:** Storage grows with orphan files and the privacy semantics presented to the user are false.
- **Next action:** Assign image lifecycle ownership and implement an observable file-plus-metadata deletion policy, including partial-failure recovery.

### GAP-005 — Capture persistence does not guarantee one file and one record

- **Features:** FEAT-001, FEAT-002
- **Severity:** P1
- **Confidence:** High
- **Evidence:** `mobile/shared/src/iosMain/kotlin/com/aipose/data/ImageStorage.kt:40-45` uses second-resolution filenames. `mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt:330-339` writes the file before inserting metadata without rollback. `mobile/composeApp/src/iosMain/kotlin/com/aipose/camera/IOSCameraController.kt:94-104` has no callback timeout.
- **Consequence:** Rapid captures can overwrite a file, database failure can orphan a file, and a missing native callback can disable capture indefinitely.
- **Next action:** Use collision-resistant identifiers, return the inserted record directly, define compensation for partial persistence, and add a bounded capture timeout.

### GAP-006 — Community enqueue and pose creation are not atomic

- **Features:** FEAT-005
- **Severity:** P1
- **Confidence:** High
- **Evidence:** `adminCommunityRoutes.ts:146-168` enqueues before creating the community record and maps every thrown error to `QUEUE_WRITE_FAILED`.
- **Consequence:** A pose creation failure leaves an orphan job that the worker may process, while the response reports an inaccurate failure category.
- **Next action:** Use one transaction or a reconciliable state machine and return errors that identify the failed operation.

### GAP-007 — Worker claiming and terminal recovery are unsafe under concurrency

- **Features:** FEAT-005
- **Severity:** P1
- **Confidence:** High from static SQL analysis
- **Evidence:** `web/services/pose-extract-server/src/db/extractionJobStore.ts:59-83` selects and updates separately, and its update accepts any queued or processing row without preserving the stale-lock predicate. `markSucceeded` and `markFailedOrRequeue` ignore zero-row updates. Jobs at maximum attempts are excluded from future claims without a crash-recovery transition to failed.
- **Consequence:** Multiple workers can bill/process the same job, lost locks can be reported as success, and a final-attempt crash can leave a job processing forever.
- **Next action:** Make claim atomic, condition updates on the expected state/token, check affected-row counts, and add terminal stale-job reconciliation.

### GAP-008 — Extraction job images have no retention or cleanup policy

- **Features:** FEAT-004, FEAT-005
- **Severity:** P1
- **Confidence:** High
- **Evidence:** `schema.sql:49-64` stores source and result images as base64. No TTL, deletion, compaction, or post-upload cleanup path was found in the job store or worker.
- **Consequence:** Sensitive user imagery is retained indefinitely and the SQLite database can grow without a bound.
- **Next action:** Define retention by job state, remove image payloads after durable publication or expiry, and add an operational cleanup check.

### GAP-009 — Community failure, pagination, and selection behavior are incomplete

- **Features:** FEAT-003
- **Severity:** P2
- **Confidence:** High
- **Evidence:** `PosesScreen.kt:114-148` drops load exceptions, ignores the `refresh` argument, derives `hasMore` from page size instead of `pagination.total`, and appends without deduplication. `mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt:117-127` does not provide `onCommunityPoseClick`.
- **Consequence:** Network failure is presented as an empty catalog, duplicate IDs may collide in the grid, and tapping a community pose has no outcome.
- **Next action:** Model an explicit recoverable error, use server pagination metadata, deduplicate by ID, and define community detail/use navigation.

### GAP-010 — FEAT-004 understates the production mobile extraction path

- **Features:** FEAT-003, FEAT-004
- **Severity:** P2 documentation drift
- **Confidence:** High
- **Evidence:** FEAT-004 says no production screen invokes extraction, but `PosesScreen.kt:263-273` opens the image picker and calls `onPickImageResult`; `PosesScreen.kt:152-177` invokes the API and stores the result.
- **Consequence:** Scope, readiness, and test expectations are based on an obsolete implementation description.
- **Next action:** Revise FEAT-004 to describe the partial production entry point and its current error/storage behavior.

### GAP-011 — Camera ratio and lifecycle controls overstate native behavior

- **Features:** FEAT-001
- **Severity:** P2
- **Confidence:** High
- **Evidence:** `CameraScreen.kt:121-123` changes frame ratio only in Compose state. `mobile/iosApp/iosApp/CameraViewController.swift:64-73` treats `start` and `stop` as no-ops although `IOSCameraPreview.kt:34-38` sends them as lifecycle commands.
- **Consequence:** UI and documentation imply camera behavior that the native bridge does not apply.
- **Next action:** Implement the native behavior or remove/disable the controls and narrow the Feature contract.

### GAP-012 — Extraction validation and cost controls are incomplete

- **Features:** FEAT-004
- **Severity:** P2
- **Confidence:** Medium to high
- **Evidence:** `extractPoseRoutes.ts:25-41` validates declared MIME type but not image magic bytes. The route is public and uses an in-memory per-IP limiter. `geminiService.ts:184-188` places the provider key in the request query string. No idempotency, global concurrency bound, or client-disconnect cancellation was found.
- **Consequence:** Spoofed uploads, horizontally scaled rate-limit bypass, duplicate provider charges, and credential exposure through URL logging remain possible depending on deployment configuration.
- **Next action:** Add content validation, a shared abuse boundary, bounded concurrency/idempotency, cancellation semantics, and a provider-auth transport review.

## Missing edge cases and acceptance coverage

### FEAT-001

- Native callback timeout and duplicate/late callback.
- Low disk, file write success followed by database failure, and application termination between the two writes.
- Two captures in the same second.
- Permission changes in Settings, app foreground/background transitions, and camera interruption.
- Device-level proof that frame, grid, flash, facing, and zoom affect the captured output.

### FEAT-002

- Missing file with retained metadata and explicit repair/delete behavior.
- File deletion failure versus metadata deletion failure.
- Photos permission denied, limited-library state, and `performChangesAndWait` operation error.
- Large gallery behavior, invalid timestamps, and local-time date grouping.

### FEAT-003

- Server responses with additional fields.
- Initial request failure versus a valid empty catalog.
- Failure during load-more while retaining existing items.
- Duplicated/removed items between pages and an exact-multiple final page.
- Community card selection, missing remote image, and retry behavior.

### FEAT-004

- MIME spoofing, malformed or unpadded base64, and semantically invalid generated images.
- Provider success followed by usage-accounting failure.
- Client disconnect, timeout, cancellation, concurrent duplicate requests, and all-key exhaustion.
- Supported MIME consistency between mobile, direct extraction, and admin community submission.

### FEAT-005

- Publish request before job success and failure after a record is already published.
- Worker crash after upload but before database update, or after provider billing but before result persistence.
- Duplicate/stale worker claims, retry backoff, and maximum-attempt crash recovery.
- Orphan pose, job, and R2 object reconciliation.
- Source/result retention, deletion, and privacy auditability.
- Admin UI job polling and truthful queued/processing/succeeded/failed messaging.

## Cross-feature ownership decisions

- FEAT-001 and FEAT-002 must share one photo lifecycle invariant covering file creation, metadata creation, export, and deletion.
- FEAT-003 and FEAT-004 need one versioned mobile/server DTO and error-envelope contract.
- FEAT-003 and FEAT-005 must define when a community pose becomes publicly browseable and who owns broken-asset remediation.
- FEAT-004 and FEAT-005 currently represent direct-provider and browser-worker extraction paths; the canonical path, fallback policy, accounting, and support boundary need an explicit Decision.
- FEAT-005 must own the complete asynchronous state machine across admin UI, API, queue, worker, R2, and public catalog instead of assigning success independently at each boundary.

## Verification evidence

- Two read-only AGY reviews ran with `gemini-3.1-pro-high`; a corrective run was used because the first report under-covered per-feature readiness and edge cases.
- Every P0/P1 finding above was independently checked against the cited implementation.
- `npm test -- --run src/routes/adminCommunityRoutes.test.ts src/db/extractionJobStore.test.ts src/worker/job-processor.test.ts src/routes/communityRoutes.test.ts src/routes/extractPoseRoutes.test.ts` in `web/services/pose-extract-server` — 2 discovered test files and 17 tests passed. The suites do not exercise job-to-R2 publication or worker claim concurrency.
- `./gradlew :shared:iosSimulatorArm64Test` — failed during test compilation because `kotlinx.coroutines.test.runTest` is unresolved in `PoseApiServiceTest.kt`.
- Tôi không thể xác minh điều này hoạt động vì camera capture và Photos export chưa được chạy trên thiết bị iOS thật; simulator capture returns empty image data by design.

## Remaining uncertainty

- The exact `kotlinx.serialization` defaults used by the resolved production dependency should be confirmed with an executable contract test; the production/test configuration mismatch is confirmed regardless.
- Deployment topology determines the practical exploitability of `trust proxy` and the per-IP limiter; the current design remains process-local.
- No evidence was found that the public community route is currently exposed to production users. GAP-001 remains a release blocker before it is exposed.

## Changed files

- `docs/harness/reports/REP-002-feature-gap-and-release-readiness-audit.md` — this audit report.
- Harness retrieval index and graph artifacts are regenerated after validation.

## Plan variance

No approved Plan governed this read-only assessment. All five Features remain in draft state, and no approval authority was inferred or changed.

## Repeated friction

- The existing mobile API tests do not compile because their coroutine test dependency is unavailable.
- Backend tests pass while omitting the cross-service pipeline where the highest-severity defect exists.
- The first delegated audit produced correct but incomplete coverage, requiring the single permitted corrective review and independent source verification.
