---
title: "Phase 1: Camera surface and contract preservation"
status: todo
---

# Phase 1: Camera surface and contract preservation

## Overview

Redesign the supported CameraScreen composition around the full-bleed preview, HDR-003 top-header affordance, and stable bottom capture rail while retaining the current camera coordinator, permission, lifecycle, capture, thumbnail, and snapshot seams. The guide action becomes the entry to the camera-owned full-screen picker; this phase does not create a new navigation or data contract.

**Owner:** implementer assigned by General Lead after `READY_FOR_WORK`; planning boundary owned by Tiêu Hà. **Priority:** P1. **Dependencies:** none. **Expected files:** modify `mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt`; add focused common tests only if the implementation exposes a testable camera state seam.

## Requirements

- [ ] Preserve `CameraCoordinator` phases, accepted-shutter gating, timeout/cancellation, JPEG verification, metadata failure compensation, and latest-valid-thumbnail semantics.
- [ ] Preserve permission-denied/restricted recovery, background cancellation, foreground restart, and `onDismiss` behavior.
- [ ] Keep grid/flash/flip/zoom/tools/settings behavior and the eight snapshot settings intact; do not change snapshot schema or persistence ownership.
- [ ] Place one accessible image-icon guide control in the top header beside Tools, as SCR-001-01-HDR-003; the bottom rail contains only thumbnail, shutter, and flip.
- [ ] While picker state is active, camera capture controls cannot be triggered underneath it and the native preview session is stopped.
- [ ] On a verified picker return, commit `activeReference`, `CameraUiState.overlaySource`, `PoseServiceLocator.preparedReference`, and existing settings-preserving snapshot persistence in one serialized state transition; snapshot code must not observe an intermediate broken reference.
- [ ] On picker Back or verified selection, call the existing `startPreview()` resume operation only when permission is authorized and the app is foreground; do not invent a `resume()` or preview-ready callback.
- [ ] Serialize picker exit as child unmount first, then the single selection commit (when applicable), then `startPreview()`; no preview start may race child teardown or an AV transition.

## Implementation Steps

1. Map the current `CameraScreen` state and `CameraUiState` transitions before editing; preserve the existing coordinator/controller adapters.
2. Move the guide action from the current bottom-right `CameraUsersButton` to the HDR-003 top header beside Tools, using the existing image icon path and accessible semantics.
3. Add a camera-owned full-screen child state/surface and callbacks for Back and verified selection. Do not route through Home, Search, Gallery, or a new app-level Voyager stack.
4. On child entry, stop preview through the existing `CameraController.stopPreview()` command; keep the coordinator contract and capture truth unchanged.
5. On Back/success, start preview through existing `startPreview()` only for authorized foreground Camera; preserve the current permission/lifecycle guards and settings.
6. Apply selection through one main-thread serialized commit that updates `activeReference`, `CameraUiState.overlaySource`, `PoseServiceLocator.preparedReference`, and existing snapshot persistence as one ordered transition; invalid preparation leaves every existing reference unchanged.
7. Drive both Back and successful selection through the same post-unmount exit effect so `startPreview()` cannot run while the picker is tearing down.

## Todo

- [ ] Confirm no production edits are required in `CameraCoordinator.kt`, `CameraContract.kt`, `CameraSnapshotRepository.kt`, `CameraSnapshotWriter.kt`, `Navigation.kt`, or `App.kt`.
- [ ] Add/adjust only focused common tests needed to prove the state boundary; retain existing regression fixtures.
- [ ] Record the top-header placement and bottom-rail screenshot/semantics evidence.
- [ ] Prove the selection commit cannot expose a state where Camera overlay, active reference, locator handoff, and snapshot input disagree.
- [ ] Prove picker child disposal precedes the single preview restart command on Back and selection.
- [ ] Record any discovered AV session, thermal, or contract contradiction before changing scope.

## Success Criteria

- [ ] Camera UI matches the approved direction: dominant preview, compact top controls with HDR-003 guide entry, and thumbnail/shutter/flip-only bottom rail.
- [ ] Capture and permission tests continue to prove truthful `PreviewReady`/persisted-photo behavior.
- [ ] Entering picker stops preview; returning starts the existing preview command without duplicate session ownership; capture remains gated until the existing ready/permission state permits it.
- [ ] A verified return updates active reference, overlay source, locator handoff, and snapshot input through one serialized transition; failed preparation changes none of them.
- [ ] Returning from picker cannot reopen the picker through Back and cannot lose current camera settings.
- [ ] No source outside the expected implementation write set is changed without General Lead escalation.

## Risks and responses

- **State split:** `activeReference` and `CameraUiState.overlaySource` can diverge; update them in one success path and test invalid/duplicate selection.
- **Handoff split:** `PoseServiceLocator.preparedReference` and snapshot persistence must join the same serialized commit; never publish the locator before the Camera overlay state is ready.
- **Platform drift:** Android support is not configured; keep this implementation iOS/common-source scoped and surface parity as unresolved.
- **Visual-contract drift:** prototype-only controls must not override native camera contracts; use design evidence only for composition and flow.
- **AV session behavior:** the repository proves start/stop bridge mapping but not thermal/interruption behavior; Phase 3 owns physical-device evidence and General Lead decides any unresolved result before implementation acceptance.
