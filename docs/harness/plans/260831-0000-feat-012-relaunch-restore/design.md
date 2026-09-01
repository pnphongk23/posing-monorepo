# FEAT-012 Relaunch Restore — Design

## Quyết định

- Reuse `PreparedPoseReference` làm runtime transport hiện có và `PoseServiceLocator.preparedReference` làm handoff reader; không tạo durable runtime model mới.
- Persist một single-device snapshot nhỏ qua persistence layer hiện có. WI-02 phải xác định implementation path bằng evidence trước khi sửa code.
- Snapshot gồm pose identity cần để resolve render asset (`poseId`, `poseName`, verified local locator khi contract hiện có cho phép) và đúng tám nhóm settings: `facing`, `flash`, `grid`, guide visibility, opacity, line color, overlay position/scale, zoom.
- Restore settings ngay cả khi pose thiếu/invalid. Snapshot corrupt phải fallback an toàn, clear phần pose không hợp lệ, và không crash.
- Repository Maintainer/user decision provenance (verbatim): “choose Option 1, standard SQLDelight — add the snapshot table to the .sq schema plus migration file 1.sqm, upgrade schema 1 -> 2, runtime-managed by the existing SQLDelight driver, and accept forward-only/no downgrade because the app is pre-release.” WI-02 implements this decision with the singleton `CameraSnapshot` table, `settings_json` plus nullable `pose_json`, and no foreign key.
- Select/replace chỉ thay pose snapshot; clear chỉ gỡ pose snapshot/overlay. Cả hai giữ settings; không save, publish, delete, hoặc transfer ownership source Pose.
- Giữ nguyên capture/gallery pipeline, Try Pose verify-before-emit, và overlay rendering đã có.

## State matrix

| State | Persist/restore | Khi invalid hoặc thiếu | Owner / evidence |
| --- | --- | --- | --- |
| `facing` | Có | default hiện có | WI-02 persistence; WI-03 bootstrap; WI-04 relaunch evidence. `CameraUiState.cameraFacing` (`CameraState.kt:14-27`) |
| `flash` | Có | default hiện có | WI-02 persistence; WI-03 bootstrap; WI-04 relaunch evidence. `CameraUiState.flashMode` (`CameraState.kt:14-27`) |
| `grid` | Có | default hiện có | WI-02 persistence; WI-03 bootstrap; WI-04 relaunch evidence. `CameraUiState.isGridVisible` (`CameraState.kt:14-27`) |
| guide visibility | Có | default hiện có | WI-02 persistence; WI-03 bootstrap; WI-04 relaunch evidence. `CameraUiState.isOverlayVisible` (`CameraState.kt:14-27`) |
| opacity | Có | default hiện có | WI-02 persistence; WI-03 bootstrap; WI-04 relaunch evidence. `CameraUiState.overlayOpacity` (`CameraState.kt:14-27`) |
| line color | Có | default hiện có | WI-02 persistence; WI-03 bootstrap; WI-04 relaunch evidence. `CameraUiState.poseLineColor` (`CameraState.kt:14-27`) |
| overlay position/scale | Có | default hiện có | WI-02 persistence; WI-03 bootstrap; WI-04 relaunch evidence. `CameraUiState.overlayOffset/overlayScale` (`CameraState.kt:14-27`) |
| zoom | Có | default hiện có | WI-02 persistence; WI-03 bootstrap; WI-04 relaunch evidence. `CameraZoomUiState.zoomValue` and `setCameraZoomValue` (`CameraLayoutModel.kt:14-25`) |
| pose identity + verified local locator | Có, tùy chọn | không overlay; settings vẫn restore | WI-02 persistence; WI-03 rehydrate. `PreparedPoseReference` (`PreparedPoseReference.kt:24-29`), `PoseServiceLocator.preparedReference` (`PoseServiceLocator.kt:12-21`) |
| permission, in-flight capture, capture result, flash animation, popup visibility, `frameRatio` | Không | không áp dụng | WI-03/WI-04 regression exclusions. `CameraUiState` (`CameraState.kt:14-27`) |

## Reuse boundary

Không mở rộng sang Saved Poses hoặc Albums, không thêm `ActivePoseReference`, account sync, history, cloud sync, hay dependency mới. Nếu persistence hiện có không đủ, WI-02 phải dừng ở evidence/decision cần thiết; không tự invent architecture.

## Verification ledger

| Claim | Status | Evidence |
| --- | --- | --- |
| Existing transport/handoff contract | Verified | `PreparedPoseReference.kt:24-29`, `PoseServiceLocator.kt:12-21`, `Navigation.createTryPoseCameraHandoffAction` (`Navigation.kt:293-299`), `PoseDetailViewModel.tryPose` (`PoseDetailScreen.kt:322-335`) |
| Existing session Camera state and eight settings | Verified | `CameraUiState` (`CameraState.kt:14-27`), `CameraZoomUiState`/`setCameraZoomValue` (`CameraLayoutModel.kt:14-25`), controls and overlay consumers (`CameraScreen.kt:83-141`, `248-287`, `310-337`, `358-380`) |
| Durable snapshot implementation | Verified | WI-02; standard SQLDelight `CameraSnapshot.sq` plus `1.sqm`, schema 1→2, existing driver; `CameraSnapshotRepositoryTest` passed 6/6 on iOS Simulator |
| Select/replace/clear and relaunch integration | Verified (iOS Simulator); physical lifecycle not covered | WI-03 completed; WI-04 simulator evidence, device `FEAT012-Test-iPhone` / `6257BF4A-4EED-4421-AED1-C28606526D21`, iOS 26.1. Clear-state composition regression is guarded by `CameraUiState.withoutPose()` plus `CameraSnapshotIntegrationTest.clearPoseStatePreservesChangedSettingsAndZoom`; full Compose lifecycle is not covered because no Compose UI test infrastructure exists. |
| Cold relaunch matrix and real iPhone evidence | Simulator evidence recorded; physical criterion Unresolved | WI-04; physical terminate-from-app-switcher → relaunch → Camera was not verified. `Tôi không thể xác minh điều này hoạt động vì không có iPhone thật; chỉ có iOS Simulator` |

WI-04 declared user decision provenance (verbatim): `Có iphone rồi đó. dùng simulator giúp tôi nhé`. User hiện có iPhone thật nhưng chọn hoàn tất lần này bằng iOS Simulator; simulator evidence does not substitute for physical-device evidence, and physical verification remains a follow-up.

## Requirement ownership matrix

| Requirement | Owner Work Items | Required evidence |
| --- | --- | --- |
| FR-001 settings independent of pose | WI-01, WI-02, WI-03, WI-04 | Matrix; round-trip tests; bootstrap/integration evidence; real-device matrix |
| FR-002 valid pose rehydrates `PreparedPoseReference` | WI-01, WI-02, WI-03, WI-04 | Transport contract; persistence test; integration and device evidence |
| FR-003 invalid/corrupt pose does not crash and preserves settings | WI-01, WI-02, WI-03, WI-04 | Corrupt snapshot test; safe fallback; device/log evidence |
| FR-004 replace preserves settings | WI-01, WI-03, WI-04 | Integration test/evidence and device matrix |
| FR-005 clear removes pose only and preserves ownership/settings | WI-01, WI-03, WI-04 | Integration test/evidence and device matrix |
| FR-006 single-device, no sync/history | WI-01, WI-02 | Design boundary and persistence implementation evidence |
| FR-007 capture/gallery semantics unchanged | WI-01, WI-03, WI-04 | Baseline regression and real-device capture evidence |
| BR-001 verify-before-emit | WI-01, WI-03, WI-04 | `tryPose`/handoff evidence and regression |
| BR-002 clear does not save/publish/transfer ownership | WI-01, WI-03, WI-04 | Integration evidence and regression |
| BR-003 transient state excluded | WI-01, WI-03, WI-04 | Exclusion matrix and regression |
| BR-004 `frameRatio` excluded | WI-01, WI-03, WI-04 | Exclusion matrix and regression |
| NFR-001 empty/partial/corrupt snapshot does not crash | WI-01, WI-02, WI-03, WI-04 | Matrix; corrupt/partial tests; device evidence |
