# MediaAsset

## Description

Payload media gắn với một [`Pose`](pose.md). Mỗi `Pose` có đúng **ba** media role:
`original` (nguồn), `skeleton` (kết quả extraction), `thumbnail` (thu nhỏ).
**Cả ba được materialize ngay tại lúc tạo pose (post-extraction)**, và cả ba slot
của Pose (`originalMediaId`, `skeletonMediaId`, `thumbnailMediaId`) đều non-nullable
— không có Pose thiếu asset.
[FEAT-005](../../../harness/features/FEAT-005-manage-a-pose-guide.md) sở hữu
lifecycle asset trong pose. [FEAT-006](../../../harness/features/FEAT-006-publish-a-pose.md)
dùng trạng thái `ready` của skeleton làm điều kiện publish.
[FEAT-008](../../../harness/features/FEAT-008-use-published-poses.md) tải và xác
minh skeleton trước Try Pose.

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `mediaId` | TEXT (UUID) | PK | Định danh asset |
| `poseId` | TEXT (UUID) | ✓ | [`Pose`](pose.md) sở hữu asset |
| `role` | TEXT | ✓ | Enum `MediaAssetRole`: `original` \| `skeleton` \| `thumbnail` |
| `locator` | TEXT | ✓ | URI đọc được (object storage hoặc tương đương) |
| `mimeType` | TEXT | ✓ | `image/png`, `image/jpeg`, hoặc `image/webp` |
| `readiness` | TEXT | ✓ | Enum `MediaAssetReadiness`: `pending` \| `ready` \| `failed` |
| `createdAt` | DATETIME | ✓ | Thời điểm tạo |
| `updatedAt` | DATETIME | ✓ | Thời điểm cập nhật cuối |

## Relationships

- Mỗi `Pose` có đúng một asset mỗi role `original`, `skeleton`, `thumbnail`
  (`Pose.originalMediaId` / `Pose.skeletonMediaId` / `Pose.thumbnailMediaId`
  → `MediaAsset.mediaId`)
- `ExtractionJob` thành công cập nhật hoặc tạo `MediaAsset` role `skeleton`
  thành `ready`
- Public DTO (`Pose` published) trả `skeleton` / `thumbnail` `ready`

## Business Rules

| ID | Rule |
|---|---|
| BR-ASSET-001 | Mỗi `Pose` có đúng một `original` hiện hành. |
| BR-ASSET-002 | Publish chỉ được khi tồn tại `skeleton` với `readiness = ready` và `locator` đọc được. |
| BR-ASSET-003 | `pending` hoặc `failed` không được dùng làm ảnh catalogue hay Try Pose. |
| BR-ASSET-004 | Locator công khai của `Pose` published phải trỏ asset `ready`, không trỏ payload tạm trên job. |
| BR-ASSET-005 | Đúng ba `MediaAsset` (`original`, `skeleton`, `thumbnail`) materialize tại lúc tạo pose; cả ba slot Pose non-nullable từ creation. |