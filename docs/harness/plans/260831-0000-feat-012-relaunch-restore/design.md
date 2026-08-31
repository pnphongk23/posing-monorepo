# FEAT-012 Relaunch Restore — Design

## Quyết định

- Reuse `PreparedPoseReference` làm runtime transport hiện có và `PoseServiceLocator.preparedReference` làm handoff reader; không tạo durable runtime model mới.
- Persist một single-device snapshot nhỏ qua persistence layer hiện có. WI-02 phải xác định implementation path bằng evidence trước khi sửa code.
- Snapshot gồm pose identity cần để resolve render asset (`poseId`, `poseName`, verified local locator khi contract hiện có cho phép) và đúng tám nhóm settings: `facing`, `flash`, `grid`, guide visibility, opacity, line color, overlay position/scale, zoom.
- Restore settings ngay cả khi pose thiếu/invalid. Snapshot corrupt phải fallback an toàn, clear phần pose không hợp lệ, và không crash.
- Select/replace chỉ thay pose snapshot; clear chỉ gỡ pose snapshot/overlay. Cả hai giữ settings; không save, publish, delete, hoặc transfer ownership source Pose.
- Giữ nguyên capture/gallery pipeline, Try Pose verify-before-emit, và overlay rendering đã có.

## State matrix

| State | Persist/restore | Khi invalid hoặc thiếu |
| --- | --- | --- |
| `facing` | Có | default hiện có |
| `flash` | Có | default hiện có |
| `grid` | Có | default hiện có |
| guide visibility | Có | default hiện có |
| opacity | Có | default hiện có |
| line color | Có | default hiện có |
| overlay position/scale | Có | default hiện có |
| zoom | Có | default hiện có |
| pose identity + verified local locator | Có, tùy chọn | không overlay; settings vẫn restore |
| permission, in-flight capture, capture result, flash animation, popup visibility, `frameRatio` | Không | không áp dụng |

## Reuse boundary

Không mở rộng sang Saved Poses hoặc Albums, không thêm `ActivePoseReference`, account sync, history, cloud sync, hay dependency mới. Nếu persistence hiện có không đủ, WI-02 phải dừng ở evidence/decision cần thiết; không tự invent architecture.

## Verification ledger

| Claim | Status | Evidence |
| --- | --- | --- |
| Existing transport/handoff contract | Verified baseline | `PreparedPoseReference.kt`, `PoseServiceLocator.kt`, `Navigation.kt`, `PoseDetailScreen.kt` |
| Existing session Camera state and eight settings | Verified baseline | `CameraState.kt`, `CameraLayoutModel.kt`, `CameraContract.kt`, `CameraScreen.kt` |
| Durable snapshot implementation | Unresolved | WI-02 |
| Cold relaunch matrix and real iPhone evidence | Unresolved | WI-04 |
