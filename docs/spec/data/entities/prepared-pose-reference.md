# PreparedPoseReference

## Description

Hợp đồng transport trên mobile khi Try Pose thành công
([FEAT-008](../../../harness/features/FEAT-008-use-published-poses.md)). Xác nhận
skeleton đã sẵn sàng trước khi rời detail vào Camera. Không persist qua relaunch.

Sử dụng ID đơn giản `poseId` (UUID) + `mediaId` (UUID); không còn
`PoseReferenceKey.Personal|Community`.

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `poseId` | String (UUID) | ✓ | Identity canonical [`Pose`](pose.md) đã chọn |
| `mediaId` | String (UUID) | ✓ | `MediaAsset.mediaId` của skeleton |
| `name` | String | ✓ | Tên hiển thị |
| `skeletonLocator` | String | ✓ | Skeleton đã verify: data URI hoặc absolute local path. Không bao giờ remote URL. |

## Relationships

- `poseId` → [`Pose.poseId`](pose.md)
- `mediaId` → [`MediaAsset.mediaId`](media-asset.md) role `skeleton` `ready`
- Skeleton nguồn từ `MediaAsset` `ready`

## Business Rules

| ID | Rule |
|---|---|
| BR-PREPREF-001 | `skeletonLocator` chỉ local/data URI sau bước prepare. |
| BR-PREPREF-002 | Không persist qua relaunch. Chọn pose khác thì thay reference in-memory. |
| BR-PREPREF-003 | Verify ảnh phải pass trước khi emit. Thất bại thì ở lại detail, không mở Camera với pose lỗi. |
| BR-PREPREF-004 | Try Pose không cấp ownership hay quyền publish. |