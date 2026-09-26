---
phase: 5
title: "iOS Add Pose + Jobs UI"
status: pending
priority: P1
effort: "1.5d"
dependencies: [4]
---

# Phase 5: iOS Add Pose + Jobs UI

## Overview
Build SCR-004-01 Add Pose and SCR-005-01 Jobs in SwiftUI, plus the Poses header entry, matching the prototype
(`docs/prototype/screens/add-pose.html`, `jobs.html`, `poses-list.html`) and the Basic Design docs.

## Requirements
- Poses header: `Add pose` plus a `Jobs` button with an active-count badge (hidden at 0). Both buttons stay **visible** when signed out.
  A signed-out tap opens the existing sign-in prompt, and the badge is hidden while signed out. `SignInIntent`
  (`Features/Support/SignIn.swift:5-16`) gains the cases `addPose` ("Add your own pose.") and `openJobs` ("See your pose jobs.").
  Unlike Saved (whose `NavigationLink` always pushes and gates inside `SavedPosesScreen`), these two buttons are gated at the tap site.
  `PosesScreen` gains `@State private var pendingSignIn: SignInIntent?` and `@State private var route: PosesRoute?`
  (`.addPose` / `.jobs`), plus two hidden `NavigationLink(isActive:)` bindings derived from `route`. The app wraps screens in
  `NavigationStack` on iOS 16+ and `NavigationView(.stack)` on iOS 15 (`AIPoseNavigation.swift:11-13`), and `NavigationLink(isActive:)` works under both;
  `.navigationDestination` is iOS 16+ only and is not used.
  A tap sets `route` when signed in, or `pendingSignIn` when signed out. `.signInPrompt($pendingSignIn) { intent in route = intent == .addPose ? .addPose : .jobs }`
  pushes the screen after sign-in. This is the same modifier pattern `PoseDetailScreen` uses (`PosesFeature.swift:601,630`).
- `JobsScreen` is pushed from the Poses navigation stack and receives the same `PosesViewModel` instance, which it forwards to
  `PoseDetailScreen(pose:model:onTryPose:isPrivate: true)`. The initializer gains `isPrivate: Bool = false`, so existing call sites are unchanged.
- Add Pose: Photo Library picker (`PHPickerViewController` wrapped in `UIViewControllerRepresentable`, iOS 14+; the deployment target
  stays 15.0, see D12), required name, required tags, optional description, and a Submit button that is disabled until the form is valid.
  After a 202, the processing surface shows the source photo with honest status copy and two actions: `View jobs` (primary) and `Done`.
  Leaving never cancels anything. There is no Cancel label.
- Add Pose **submit failure** (SCR-004-01 ST-003, E1): the user stays on the form, and the photo, name, tags and description are all kept.
  The error shows inline and the Submit button re-enables. Copy per case:
  - offline (`URLError`): the offline message; Submit is disabled until the connection is back.
  - 400 `INVALID_IMAGE` / 413: a photo error with a prompt to choose another photo.
  - 400 `INVALID_METADATA`: a field-level error.
  - 5xx: "Couldn't send. Try again."
  - `signInRequired`: the sign-in prompt, after which the form is still intact.
  There is never an automatic resubmit.
- Add Pose **processing surface states**, driven by `watchJob` events:
  - `Queued` / `Processing`: indeterminate status.
  - `.offline`: an inline offline note; polling continues.
  - `failed`: the `Failed` label, the error copy, and a `Retry` button (disabled while offline). Retry calls `jobsService.retry`, then starts a new `watchJob` (A2, DTL-006).
  - `succeeded`: `Ready` with `View pose` and `Done`.
  - `.gone`: "This job was removed." with `Done`.
- Jobs: nav title `Jobs`, tabs `Processing` / `Finish`, a Finish filter (`All results` / `Success` / `Fail`), rows showing the thumbnail
  (placeholder when null), name, status label and a single trailing action. Swipe-to-remove works only on Finish rows, behind a confirm sheet. The empty state reads "No jobs yet" with an `Add pose` CTA.
  The offline banner reads "You're offline — statuses update when you're back online.", and Retry is disabled while offline.
- `View pose` → `getGuide(id)` → map to `NativePose` → push the existing `PoseDetailScreen` with `isPrivate: true` (D13).
  `PoseDetailScreen`'s `.task` (`PosesFeature.swift:~636`) skips `model.confirmPublished` when `isPrivate` is set, because `PoseServiceAdapter.pose(id:)`
  (`PoseServiceAdapter.swift:701-714`) only searches community and saved poses and would flag a private pose as unavailable. Private poses also
  hide bookmark and publish affordances that do not apply to them.
- Accessibility: 44pt targets, Dynamic Type, reduced motion respected, VoiceOver labels on the badge and row actions.

## Architecture
- `Features/Jobs/AddPoseScreen.swift`, `Features/Jobs/JobsScreen.swift`, `Features/Jobs/JobRowView.swift`. Use the existing
  `AIPoseDesignSystem` / `AIPoseComponents` tokens; add no new design tokens.
- Polling lifecycle: `JobsScreen.onAppear → startPolling`, `onDisappear → stopPolling`. The Add Pose processing surface consumes
  `jobsService.watchJob(id:)` inside a `.task`, which SwiftUI cancels on disappear.
  `PosesScreen` calls `jobsService.refresh()` on appear and on `scenePhase == .active` to update the badge.
- Image upload: downscale to a longest side of ≤2048 px and encode JPEG q≈0.85 so it stays under the 10 MB limit.
- The `GuidePoseMapper` (`GuidePose → NativePose`) goes next to `CommunityPoseMapper` in `PoseServiceAdapter.swift`. It sets `NativePose.imageURL`
  (`FeatureService.swift:12-19`, which the detail hero renders) from `skeletonUrl`, resolved with `CommunityPoseMapper.resolveURL` when relative.
  It maps `name`, takes `category` from the first tag (or "" when there are none), splits `description` into `instructions` by line (or `[]`), and sets `isSaved=false`.

## Related Code Files
- Create: `mobile/iosApp/iosApp/Features/Jobs/AddPoseScreen.swift`, `JobsScreen.swift`, `JobRowView.swift`
- Create: `mobile/iosApp/iosApp/Features/Jobs/PhotoLibraryPicker.swift` (PHPicker wrapper)
- Modify: `mobile/iosApp/iosApp/Features/Support/SignIn.swift` (`addPose`, `openJobs` intents plus copy) and the existing post-sign-in resume routing
- Modify: `mobile/iosApp/iosApp/Features/Poses/PosesFeature.swift` (header entry, `PoseDetailScreen.isPrivate`), `PoseServiceAdapter.swift` (mapper),
  `Core/DesignSystem/AIPoseNavigation.swift` (routes) if routing lives there
- Create: `mobile/iosApp/iosAppTests/Features/AddPoseFormTests.swift`, `AddPoseProcessingTests.swift`, `JobsScreenModelTests.swift`
- Update: prototype-parity harness reference shots only if the harness already covers the Poses header (`scripts/` parity tool)

## Implementation Steps
1. Add the header entry and badge, wired to `JobsService.activeCount`.
2. Add Pose form: validation model plus tests (trimmed name, 1–10 tags, description ≤500), picker, downscale, submit, processing surface.
   `AddPoseFormTests` also cover submit failure for offline, 400, 413, 5xx and `signInRequired`: the draft and photo are kept, the right error state shows,
   and no resubmit happens. `AddPoseProcessingTests` drive a stubbed `watchJob` through queued→processing→failed→Retry (a new watch)→succeeded, plus
   `.offline`/`.online` and `.gone`, and assert the visible state and actions at each step.
3. Jobs screen: tabs, filter, rows, swipe-to-remove with confirm, empty and offline states.
4. View pose navigation through `getGuide`, plus the `isPrivate` detail path and a test proving a private pose never enters `unavailableState`.
5. Capture simulator screenshots with `JobsService` backed by a stubbed API (test-target fixtures, not shipped in the app) for
   Add Pose, processing, Jobs Processing, Jobs Finish (Ready + Failed), empty and offline. The live-server walkthrough belongs to Phase 6.

## Success Criteria
- [ ] `xcodebuild test -scheme Dev` (same destination as Phase 4) passes.
- [ ] Simulator screenshots saved in `plans/260925-server-authoritative-jobs/screens/`. Visual parity with the prototype has been
      checked side by side (390×844).
- [ ] No labels outside the four row states, and no Cancel label anywhere. The unit test checks the row label/action mapping. The only dismiss
      control on the hide-confirm sheet uses the prototype's label (`docs/prototype/screens/jobs.html`), and it never cancels a job.

## Risk Assessment
- The stubbed API drifts from the real contract → the stub decodes the same inline openapi-derived constants (`JobsFixtures.swift`) as the Phase 4 decoding tests.
- PHPicker needs no photo-library permission prompt. Verify on the simulator.
