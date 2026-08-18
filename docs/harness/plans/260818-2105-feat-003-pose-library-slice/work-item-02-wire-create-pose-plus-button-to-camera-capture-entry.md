---
work_item: 2
title: Wire Create Pose (+) to Camera capture entry
status: pending
priority: P1
effort: S
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 2: Wire Create Pose (+) to Camera capture entry

**Kind:** navigation / Camera capture entry (Option A)

## Tasks

- Replace `onExtractPoseClick = {}` at `Navigation.kt:129` with `CameraTab` switch
  matching prototype `poses-list.html:49` → `camera-live.html`.
- Ensure toolbar `+` (`PosesScreen.kt:195-208`) and empty-state Create Pose CTA
  (`PosesScreen.kt:259-262`) share the same callback.
- **Do not** call `PoseApiService.extractPose`, enqueue jobs, or claim FEAT-004
  extraction in acceptance or docs.
- Add navigation test: Create Pose → `CameraTab`.

## Scope and affected files

- `mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PosesScreen.kt` (callback only)
- `mobile/composeApp/src/commonTest/kotlin/com/aipose/ui/` (navigation test)

## Success criteria

- Tapping Create Pose (+) or empty-state CTA switches to Camera tab for capture.
- No `{}` no-op for `onExtractPoseClick`.
- **Negative:** no `extractPose` API invocation as part of this WI.

## Risks

- Scope creep into FEAT-004 async extraction (future slice / Plan 260816).

## Required evidence

- Evidence ID **E-CAM-ENTRY**: navigation test Create Pose → `CameraTab`.
- Manual note: user on Camera capture screen; extraction **not** claimed.
