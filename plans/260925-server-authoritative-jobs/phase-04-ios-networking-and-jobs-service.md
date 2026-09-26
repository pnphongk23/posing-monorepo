---
phase: 4
title: "iOS networking + jobs service"
status: pending
priority: P1
effort: "4h"
dependencies: [3]
---

# Phase 4: iOS networking + jobs service

## Overview
Give the native app typed access to the job API and a small observable service that owns polling. There is no persistence.

## Requirements
- Functional: submit with draft, list jobs (active/finished, cursor), retry, hide, get guide by id.
- Non-functional: nothing is written to GRDB. Signing out cancels polling and clears the in-memory state. The service subscribes via
  `ServiceLocator.sessionBoundary.observeSessions(onStart:onEvent:)` (`Core/Network/SessionBoundary.swift:144`) and keeps
  the returned task, which it cancels on deinit.

## Architecture
- `Core/Network/APIModels.swift`: add `PoseDraft`, `ExtractionJobListItem` (with `thumbnailUrl`), `ExtractionJobListResponse`
  (`success: Bool`, `data`, `meta.nextCursor`, mirroring the openapi envelope), `GuidePose` (openapi `Pose`) plus the envelope `GuidePoseDetailResponse { let data: GuidePose }`
  (`GET /api/guides/{id}` returns `{ data: Pose }`, like `CommunityPoseDetailResponse` at `APIModels.swift:120`). `getGuide(id:)` decodes the envelope and returns `.data`. Extend `PoseExtractionJobData` with `poseId`, and make
  `result`/`error` decode `null`. **Remove the `success: Bool` field from `PoseExtractionJobStatus`** (`APIModels.swift:40-43`), because
  `GET /api/extract-jobs/:id` returns only `{ data }` (`openapi.yaml` `getExtractJob`, `extractJobsRoutes.ts:27-38`). As it stands, decoding
  fails with `keyNotFound`. The decoding test uses the openapi `queued`/`succeeded`/`failed` examples verbatim.
- `Core/Network/PoseAPIService.swift`: change `startPoseExtraction(imageBytes:fileName:draft:)` to add `name`, repeated `tags` and
  `description` multipart fields through the existing `multipartBody`. Add `listMyExtractJobs(state:cursor:limit:)`, `retryExtractJob(id:)`,
  `hideExtractJob(id:)`, `getGuide(id:)`. Status codes: `APIClient.request` accepts only `[200]` by default (`APIClient.swift:24`), so
  submit and retry pass `acceptedStatus: [202]`, and hide passes `acceptedStatus: [204]` and does **not** decode a body.
- `Features/Jobs/JobsService.swift` (`@MainActor final class`, `ObservableObject`):
  - `@Published inProgress: [JobRow]`, `finished: [JobRow]`, `activeCount: Int`, `isOffline: Bool`, `loadState`.
  - `JobRow` maps each server status to a label and action: queued→`Queued`/none, processing→`Processing`/none,
    failed→`Failed`/`Retry`, succeeded→`Ready`/`View pose`. Nothing else exists.
  - **Guest guard:** every entry point first checks `ServiceLocator.sessionBoundary.hasStoredSession()` (`SessionBoundary.swift:29`) and
    makes no network call without a session. Read and poll paths (`refresh`, `startPolling`, `watchJob`) set `activeCount = 0`, clear both lists and return.
    Write paths (`submit`, `retry`, `hide`) **throw `JobsError.signInRequired`**, and the UI answers that with the sign-in prompt. Otherwise a guest would hit a 401 → `clearForUnauthorized()` / `.signInRequired`
    (`APIClient.swift:51-78`). This matches how `SavedPosesScreen` gates itself (`PosesFeature.swift:1088-1127`).
  - `refresh()` calls `GET /api/me/extract-jobs?limit=50` **without** a `state` filter and splits the rows client-side into
    `inProgress` (queued/processing) and `finished` (succeeded/failed), so a transition shows up in one refresh (D9).
  - `startPolling()` / `stopPolling()`: a 5 s `Task` loop calling `refresh()`. It stops on cancel or on sign-out, and a second `startPolling` is a no-op.
  - `watchJob(id:) -> AsyncStream<JobWatchEvent>` polls `GET /api/extract-jobs/:id` every 5 s. Its events are `.status(PoseExtractionJobData)`,
    `.offline` and `.online`. A transient `URLError` emits `.offline` and **keeps polling**; the next success emits `.online`. The stream finishes only on
    `succeeded`/`failed`, on task cancellation, or on sign-out. A 404 (the job was hidden elsewhere) finishes it with a terminal `.gone` event.
    The Add Pose processing surface uses it to get `poseId` or the error.
  - `retry(_:)` → `POST …/retry` (202). The caller then starts a **new** `watchJob` for the same id, because the previous stream finished at `failed`.
    `hide(_:)`, and `submit(image:draft:) async throws -> String` (jobId), which throws on non-202, on `URLError` and on `signInRequired`.
  - Offline: a `URLError` network failure sets `isOffline=true` and **clears** both lists, matching the normative empty-offline state in
    `scr-005-01-jobs.md` and `docs/prototype/scripts/jobs.js`. Retry and hide are disabled while offline.
  - Expose it as `ServiceLocator.jobsService` (lazy, `@MainActor`). On a session change it resets itself via the subscription above.
- Existing `Pose.currentJobId` column: leave it unchanged (no migration).

## Related Code Files
- Modify: `mobile/iosApp/iosApp/Core/Network/APIModels.swift`, `PoseAPIService.swift`, `ServiceLocator.swift`
- Create: `mobile/iosApp/iosApp/Features/Jobs/JobsService.swift`
- Create: `mobile/iosApp/iosAppTests/Features/JobsServiceTests.swift`
- Regenerate: `project.yml` already globs `iosApp/` and `iosAppTests/`, but the checked-in `iosApp.xcodeproj` only picks up new files after
  `cd mobile/iosApp && xcodegen generate`. Run it before every `xcodebuild test` in Phases 4–6, and commit the regenerated project.

## Implementation Steps
1. Add the models, with decoding tests. The openapi example payloads live as **inline Swift string constants** in
   `iosAppTests/Features/JobsFixtures.swift`, not as bundled `.json` files: `project.yml:69-72` whitelists only the sqlite/sql fixtures, so JSON resources
   would not be bundled. The Phase 5 stubbed API reuses the same constants. Also add a guest-guard test: with no stored session, `refresh()` issues no request.
2. Add the API methods, and a multipart test that asserts the `name`/`tags`/`description` parts exist.
3. Add `JobsService` behind a protocol-backed API so tests can stub it. Tests cover status mapping, the active count, stopping polling
   on `stopPolling` and on sign-out, a job moving from `processing` to `succeeded` between two refreshes ending up in `finished`,
   `watchJob` terminating on `succeeded`/`failed`, `watchJob` emitting `.offline` then `.online` across a transient `URLError` without finishing,
   `watchJob` finishing with `.gone` on 404, offline clearing the lists, `retry` moving a row to in-progress after refresh, `hide` removing a row
   (a stubbed 204 with an empty body succeeds), and the write paths throwing `signInRequired` for a guest without sending a request.

## Success Criteria
- [ ] `xcodebuild test -workspace mobile/iosApp/iosApp.xcworkspace -scheme Dev -destination 'platform=iOS Simulator,name=<available iPhone>'`
      passes, with the new tests listed in the output. The scheme is `Dev`, per `project.yml` schemes `Dev`/`Prod`.
- [ ] `grep -rn "JobRecord\|localIntentId" mobile/iosApp` returns nothing.

## Risk Assessment
- The simulator name differs on the dev machine → use `xcrun simctl list devices available` and record the destination that was actually used.
- The polling task leaks when a view disappears → the service owns a single task handle, and `startPolling` is idempotent. A test covers this.
