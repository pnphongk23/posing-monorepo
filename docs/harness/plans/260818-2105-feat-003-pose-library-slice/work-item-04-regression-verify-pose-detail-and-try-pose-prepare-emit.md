---
work_item: 4
title: Regression verify pose-detail and Try Pose prepare+emit
status: completed
priority: P1
effort: M
dependencies:
  - 3
decision_dependencies: []
---

# Work Item 4: Regression verify pose-detail and Try Pose prepare+emit

**Kind:** regression + handoff emit (not overlay / not persistence)

## Tasks

### Regression (2240 / REP-003 read-only)

- Verify personal/community detail load, E2 NOT_FOUND, retryable errors
  (`PoseDetailScreen.kt`, `PoseDetailViewModel.load`).
- Verify personal delete local-only with mutex guard.
- **Do not** refactor detail code unless named regression fails.

### Prepare + emit seam (2105 owns; 2241 consumes)

- Verify `tryPose()` / `prepareReference` for personal and community paths.
- Verify success: `PoseServiceLocator.preparedReference` set + `CameraTab` switch
  (`Navigation.kt:152-156`).
- **Do not** enable Camera overlay (`CameraScreen.kt:173`) or implement durable
  store — Plan 2241.
- Add boundary comment: 2241 WI-03 durable-commit wording is stale vs current emit.

## Scope and affected files

- `mobile/composeApp/.../PoseDetailScreen.kt`
- `mobile/composeApp/.../Navigation.kt`
- `mobile/shared/.../PreparedPoseReference.kt`, `PoseServiceLocator.kt`
- `docs/prototype/screens/pose-detail.html`

## Success criteria

- Detail regression matches DEC-003 **Aligned** / **Partial** rows.
- Prepare failure stays on detail; success emits typed reference (evidence ID
  **E-TRY-EMIT**).
- Overlay render and persistence **not** required.

## Risks

- Misreading emit as full Try Pose / overlay completion.

## Required evidence

- **E-TRY-EMIT**: tests for NOT_FOUND, prepare error, success callback + `preparedReference`.
- **E-2241-BOUNDARY**: documented note that overlay stays disabled.

## Evidence (2026-08-19)

- **E-TRY-EMIT**: `PoseDetailViewModelTest` covers NOT_FOUND, prepare errors, personal/community success emit. `TryPoseCameraHandoffTest` proves `createTryPoseCameraHandoffAction` sets `PreparedPoseReference` + `CameraTab`.
- **E-2241-BOUNDARY**: `CameraScreen.kt:173` verified `if (false)` unchanged. Boundary comment on `createTryPoseCameraHandoffAction` in `Navigation.kt`.
- Full suite: `./gradlew :shared:iosSimulatorArm64Test :composeApp:iosSimulatorArm64Test` green.
