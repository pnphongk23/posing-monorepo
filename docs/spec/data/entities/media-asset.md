# MediaAsset

## Description

Payload media gắn với một [`PoseGuide`](pose-guide.md): ảnh nguồn, render extraction, hoặc thumbnail. [FEAT-005](../../../harness/features/FEAT-005-manage-a-pose-guide.md) sở hữu lifecycle asset trong guide. [FEAT-006](../../../harness/features/FEAT-006-publish-a-pose.md) dùng trạng thái `ready` của render làm điều kiện publish. [FEAT-008](../../../harness/features/FEAT-008-use-published-poses.md) tải và xác minh render trước Try Pose.

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | TEXT (UUID) | PK | Định danh asset |
| `guideId` | TEXT (UUID) | ✓ | [`PoseGuide`](pose-guide.md) sở hữu asset |
| `role` | TEXT | ✓ | Enum `MediaAssetRole`: `source` \| `render` \| `thumbnail` |
| `locator` | TEXT | ✓ | URI đọc được (object storage hoặc tương đương) |
| `mimeType` | TEXT | ✓ | `image/png`, `image/jpeg`, hoặc `image/webp` |
| `readiness` | TEXT | ✓ | Enum `MediaAssetReadiness`: `pending` \| `ready` \| `failed` |
| `createdAt` | DATETIME | ✓ | Thời điểm tạo |
| `updatedAt` | DATETIME | ✓ | Thời điểm cập nhật cuối |

## Relationships

- Nhiều `MediaAsset` → một `PoseGuide`
- `ExtractionJob` thành công cập nhật hoặc tạo `MediaAsset` role `render` thành `ready`
- Public [`CommunityPose.imagePath`](community-pose.md) / `thumbnailPath` trỏ locator của render / thumbnail `ready`

## Business Rules

| ID | Rule |
|---|---|
| BR-ASSET-001 | Mỗi `PoseGuide` có đúng một `source` hiện hành. |
| BR-ASSET-002 | Publish chỉ được khi tồn tại `render` với `readiness = ready` và `locator` đọc được. |
| BR-ASSET-003 | `pending` hoặc `failed` không được dùng làm ảnh catalogue hay Try Pose. |
| BR-ASSET-004 | Locator public của `CommunityPose` phải trỏ asset `ready`, không trỏ payload tạm trên job. |
