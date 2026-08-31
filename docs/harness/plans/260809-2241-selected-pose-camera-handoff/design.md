# Pose and Camera Settings Relaunch Restore — Design

Ponytail comparison (minimal reuse, no new dependency unless evidence bắt buộc).

## Approaches considered

### A — Session-only (current on `main`)

**Observed:** `PoseServiceLocator.preparedReference` + `remember(preparedReference)`
khởi tạo `CameraUiState` (`CameraScreen.kt:104-114`). Zoom trong
`CameraZoomUiState` riêng (`115-117`). Mất toàn bộ khi process death.

**Pros:** đơn giản, đã ship overlay/handoff. **Cons:** không đáp ứng FEAT-012
cold relaunch.

### B — Minimal single-device persisted snapshot (recommended)

Một snapshot nhỏ trên device (ví dụ preferences/DataStore/SQLDelight bảng có
sẵn — **Unresolved:** chọn store cụ thể ở WI-02, reuse existing mobile
persistence nếu có):

| Field group | Persist | Restore |
| --- | --- | --- |
| Pose (optional) | `poseId`, `poseName`, verified `skeletonPath` hoặc managed local copy key | Rebuild `PreparedPoseReference` |
| Settings (always when changed) | facing, flash, grid, overlay visible, opacity, line color, offset x/y, scale, zoom | Map vào `CameraUiState` + `CameraZoomUiState` + native controller (`setFlashMode`, `setGridVisible`, `setZoomFactor`, `switchCamera` as needed) |

Atomic write: pose + settings commit cùng version/schema; corrupt → clear pose
portion và/hoặc fallback defaults (**FEAT-012** E1/E2).

**Pros:** đúng scope FEAT-012; không contract mới; không account sync.
**Cons:** cần managed local copy khi `skeletonPath` là data URI lớn — copy vào
app-managed file trước persist (**Inferred** từ BR-PREPREF-001).

### C — Account / history sync

Cloud hoặc account-backed history cho poses và settings.

**Rejected:** explicit out-of-scope FEAT-012 FR-006; không dependency mới.

## Recommended invariants

1. **Transport:** `PreparedPoseReference` remains the handoff type; relaunch
   rehydrates into `PoseServiceLocator.preparedReference` (or equivalent single
   reader) — **không** introduce `ActivePoseReference`.
2. **Settings independence:** restore settings even when pose portion missing/
   invalid.
3. **Replace:** new Try Pose overwrites pose snapshot only; settings preserved.
4. **Clear:** removes pose snapshot/overlay only; settings and source Pose record
   untouched; no save/publish.
5. **Transient exclusion:** permission, capture phase, flash animation, popup open
   state — không persist.
6. **frameRatio:** explicit out-of-scope until user-facing control approved
   (FEAT-012 BR-004).
7. **Capture:** `CameraCoordinator`, shutter, persistence pipeline — no semantic
   change; overlay remains visual-only.

## Out of scope

- New runtime model or third-party dependency for persistence (unless WI-02 proves
  existing stack insufficient — must cite path).
- Account sync, multi-device history.
- Auto-save / publish / ownership side effects on clear or restore.
- Re-implementing overlay rendering (already **Observed** on `main`).

## Affected symbols (current evidence)

| Symbol / area | Path | Role |
| --- | --- | --- |
| `CameraUiState` | `CameraState.kt:14-27` | Settings restore target |
| `CameraZoomUiState` | `CameraLayoutModel.kt:14-25` | Zoom restore |
| `CameraScreen` init + controls | `CameraScreen.kt:104-124`, `134-168`, `248-287`, `310-381` | Wire restore + persist hooks |
| `CameraFacing`, `FlashMode` | `CameraContract.kt:13-22` | Enum values |
| `PreparedPoseReference` | `PreparedPoseReference.kt:25-29` | Rehydrate transport |
| `PoseServiceLocator` | `PoseServiceLocator.kt:12-21` | Session holder |
| `createTryPoseCameraHandoffAction` | `Navigation.kt:285-291` | Select/replace entry |
| `PoseDetailScreen.tryPose` | `PoseDetailScreen.kt:317-351` | Verify before emit |
