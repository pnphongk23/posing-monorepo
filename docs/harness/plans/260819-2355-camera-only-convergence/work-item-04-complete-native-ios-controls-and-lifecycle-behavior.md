---
work_item: 4
title: Complete native iOS controls and lifecycle behavior
status: pending
priority: P1
effort: L
dependencies:
  - 3
decision_dependencies: []
---

# Work Item 4: Complete native iOS controls and lifecycle behavior

**Kind:** technical

## Tasks

1. Evolve `CameraController` results to explicit success/failure/cancellation
   with capture identity; marshal callbacks onto the owned UI/state dispatcher.
   - `capture()` returns `CaptureResult.Success(bytes, captureId)` or
     `CaptureResult.Failure(reason)` or `CaptureResult.Timeout`.
   - Eliminate the undifferentiated empty-bytes signal.
2. Implement effective `startPreview()` / `stopPreview()` bridge commands:
   - Currently the Swift bridge treats these as no-ops.
   - Wire to `CameraManager` session start/stop in `CameraViewController.swift`.
3. Implement app foreground/background handling:
   - Post `inactive` to coordinator when app backgrounds.
   - Cancel active capture on backgrounding.
   - Restart preview on foreground re-entry; restore control state.
   - Release hardware locks on interruption.
4. Ensure facing, zoom, flash, grid, and approved frame-ratio behavior reach
   the native layer:
   - `switchCamera()` must toggle `AVCaptureDevice` position (front/back).
   - `setFlashMode()` must set torch/flash on the active device.
   - `setGridVisible()` must toggle the grid overlay in the native preview.
   - `setZoomFactor()` must apply to the native capture device.
   - Frame ratio: if approved as user control, wire to native; if developer-only,
     document and disable the UI control.
5. Report native configuration/capture failures rather than using empty bytes.
6. Add bridge-level tests/fakes where possible and real-iPhone scenarios for
   every physical control claim.
7. Ensure native capture bytes flow correctly into the capture→Gallery pipeline:
   non-empty bytes on success, empty/error on failure, capture identity
   preserved throughout.

## Scope and affected files

- `mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraContract.kt`
- `mobile/composeApp/src/iosMain/kotlin/com/aipose/camera/CameraContract.ios.kt`
- `mobile/composeApp/src/iosMain/kotlin/com/aipose/camera/IOSCameraController.kt`
- `mobile/composeApp/src/iosMain/kotlin/com/aipose/camera/IOSCameraPreview.kt`
- `mobile/iosApp/iosApp/CameraViewController.swift`
- iOS app lifecycle wiring only where required for Camera ownership.

## Success criteria

- Start/stop are not no-ops; interruption/re-entry yields one healthy preview
  and no stuck capture.
- Each exposed control has observable native/captured-output evidence on a real
  iPhone; unsupported hardware states produce truthful UI.
- Simulator behavior is explicitly a fixture/unsupported result and never counts
  as successful physical capture.
- Flash availability is modeled per device/facing; not all modes promised
  unconditionally.
- Native capture bytes feed correctly into the capture→Gallery pipeline (non-
  empty bytes on success, capture identity preserved).

## Risks

- MijickCamera API/version constraints and native session threading must be
  verified from resolved dependency source before implementation.
- Flash availability varies by facing/device; model capability rather than
  promising all modes unconditionally.
- Notification-center bridge (Kotlin ↔ Swift) threading must dispatch to Main
  for Compose state updates.

## Required evidence

- Resolved native dependency/API citations (MijickCamera version, API surface).
- iOS compile/build logs for arm64 and simulator targets.
- Lifecycle recording (background/foreground transitions).
- Real-device control matrix (each control × state → observed output).
- Crash-list delta.
