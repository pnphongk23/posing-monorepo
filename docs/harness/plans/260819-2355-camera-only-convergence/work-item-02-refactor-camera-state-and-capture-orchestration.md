---
work_item: 2
title: Refactor Camera state and capture orchestration
status: pending
priority: P1
effort: L
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 2: Refactor Camera state and capture orchestration

**Kind:** technical

## Tasks

1. Introduce a Camera coordinator (Approach B) with explicit ports:
   - `CameraController` (native bridge) — permission, preview, capture, switch,
     flash, grid, zoom.
   - `ImageStorage` — write JPEG bytes, return path.
   - `PhotoRepository` — insert metadata, query latest, delete.
   - `Clock` — generate timestamps, detect timeout.
   - `IdGenerator` — generate collision-resistant capture IDs.
2. Model the approved state machine:
   - `PermissionRequired` → `PreviewReady` → `Capturing(captureId)` →
     `Persisting(captureId)` → `CaptureSucceeded(photo)` or `Error`.
   - Orthogonal `active`/`inactive` lifecycle inputs.
   - Only one active `captureId`; timeout, backgrounding, or cancellation
     invalidates it; late callbacks are ignored and cleaned up.
3. Refactor `CameraScreen` to render state and dispatch actions only; remove
   direct file/database transaction calls from the composable.
4. Wire the coordinator to existing `CameraController`, `ImageStorage`, and
   `PhotoRepository` instances without changing navigation contracts.
5. Add unit tests for all state transitions:
   - Permission flow (not determined → authorized / denied / restricted).
   - Capture flow (idle → capturing → persisting → succeeded / failed).
   - Duplicate tap prevention.
   - Timeout invalidation.
   - Backgrounding cancellation and foreground re-entry.
   - Late/duplicate callback handling.
6. Add capture→Gallery pipeline unit test: verify that a successful capture
   produces a file + metadata record that would be readable by Gallery.
7. Add thumbnail state update test: verify ThumbnailState.Available is set
   after successful capture with the correct imagePath.

## Scope and affected files

- `mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraState.kt`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraContract.kt`
- New: `mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraCoordinator.kt`
- New: `mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraPorts.kt`
- `mobile/composeApp/src/commonTest/kotlin/com/aipose/camera/` (new tests)

## Success criteria

- UI has no direct file/database transaction and no unbounded capture-in-flight
  state.
- Duplicate tap, timeout, backgrounding, failure, and late callback transitions
  are deterministic and unit tested.
- Existing visible behavior remains unchanged until WI-03 deliberately switches
  it to approved behavior.
- All coordinator state transitions are covered by focused unit tests.
- Capture→Gallery pipeline is testable: successful capture produces file +
  metadata record; thumbnail state updates correctly.

## Risks

- Kotlin/Native callback threading may mutate Compose state off-main; define and
  test dispatch ownership (Main dispatcher for state updates).
- Over-generalizing the coordinator would expand scope; keep it Camera-specific.
- Existing `CameraScreen` is ~380 lines; incremental extraction reduces risk.

## Required evidence

- State transition table (state × event → next state + side effects).
- Focused unit test output showing all transitions pass.
- Capture→Gallery pipeline test output (file + metadata + thumbnail update).
- Compile output for iOS simulator target.
- Review showing no persistence calls remain in UI code.
