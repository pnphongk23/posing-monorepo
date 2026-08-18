# PreparedPoseReference

## Description

Hợp đồng transport trên mobile khi Try Pose thành công ([FEAT-008](../../../harness/features/FEAT-008-use-published-poses.md)). Xác nhận render đã sẵn sàng trước khi rời detail vào Camera. Không persist qua relaunch.

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `key` | PoseReferenceKey | ✓ | Identity đã chọn |
| `name` | String | ✓ | Tên hiển thị |
| `renderLocator` | String | ✓ | Render đã verify: data URI hoặc absolute local path. Không bao giờ remote URL. |

## Relationships

- `key` → [`PoseReferenceKey`](pose-reference-key.md)
- Render nguồn từ [`MediaAsset`](media-asset.md) `ready` (community) hoặc file local (`PersonalPose`)

## Business Rules

| ID | Rule |
|---|---|
| BR-PREPREF-001 | `renderLocator` chỉ local/data URI sau bước prepare. |
| BR-PREPREF-002 | Không persist qua relaunch. Chọn pose khác thì thay reference in-memory. |
| BR-PREPREF-003 | Verify ảnh phải pass trước khi emit. Thất bại thì ở lại detail, không mở Camera với guide lỗi. |
| BR-PREPREF-004 | Try Pose không cấp ownership hay quyền publish. |
