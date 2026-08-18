# PoseGuide

## Description

Aggregate do Pose Guide Owner quản lý: metadata, media, lịch sử extraction, và visibility. Đây là đơn vị làm việc của [FEAT-005](../../../harness/features/FEAT-005-manage-a-pose-guide.md). Khi `status = published`, cùng `id` xuất hiện trên catalogue công khai dưới dạng [`CommunityPose`](community-pose.md).

Publication / unpublish thuộc [FEAT-006](../../../harness/features/FEAT-006-publish-a-pose.md). Extraction thuộc [FEAT-004](../../../harness/features/FEAT-004-extract-reusable-pose-images.md); guide tái sử dụng hợp đồng đó, không định nghĩa extraction riêng.

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | TEXT (UUID) | PK | Định danh guide; trùng `CommunityPose.id` khi published |
| `ownerAccountId` | TEXT (UUID) | ✓ | [`Account`](account.md) sở hữu guide |
| `name` | TEXT | ✓ | Tên hiển thị |
| `description` | TEXT | — | Mô tả |
| `tags` | TEXT[] | ✓ (default `[]`) | Nhãn lọc catalogue |
| `difficulty` | TEXT | — | Enum `PoseDifficulty` |
| `bodyParts` | TEXT[] | ✓ | Ít nhất một phần cơ thể |
| `status` | TEXT | ✓ (default `draft`) | Enum `PoseStatus` |
| `sourceAssetId` | TEXT (UUID) | ✓ | [`MediaAsset`](media-asset.md) role `source` |
| `renderAssetId` | TEXT (UUID) | — | [`MediaAsset`](media-asset.md) role `render`; bắt buộc `ready` trước khi publish |
| `thumbnailAssetId` | TEXT (UUID) | — | [`MediaAsset`](media-asset.md) role `thumbnail` |
| `currentJobId` | TEXT (UUID) | — | [`ExtractionJob`](extraction-job.md) đang theo dõi |
| `createdAt` | DATETIME | ✓ | Thời điểm tạo |
| `updatedAt` | DATETIME | ✓ | Thời điểm cập nhật cuối |

## Relationships

- `PoseGuide.ownerAccountId` → `Account.id`
- `PoseGuide` 1 — 1..* `MediaAsset` (roles `source`, `render`, `thumbnail`)
- `PoseGuide` 1 — 0..* `ExtractionJob` (lịch sử; `currentJobId` trỏ job hiện tại)
- `PoseGuide.id` = `CommunityPose.id` khi `status = published`
- Admin operator ([FEAT-007](../../../harness/features/FEAT-007-operate-pose-content-from-admin-web.md)) tạo/sửa guide qua cùng model này

## Business Rules

| ID | Rule |
|---|---|
| BR-GUIDE-001 | Một lần submit hợp lệ tạo một `PoseGuide` `draft` và một `ExtractionJob` `queued`. `202` chỉ có nghĩa đã nhận vào hàng đợi, không phải guide sẵn sàng. |
| BR-GUIDE-002 | Không được tuyên bố guide public khi render `MediaAsset` chưa `ready`. |
| BR-GUIDE-003 | Retry / re-extract tạo hoặc tái xếp `ExtractionJob` gắn cùng `PoseGuide`; không tạo guide mới. |
| BR-GUIDE-004 | Revert khôi phục render `ready` trước đó; không publish hộ. |
| BR-GUIDE-005 | Xóa terminal gỡ guide khỏi catalogue, ngắt `SavedEntry` khỏi nội dung công khai, và không để lại job/asset được trình bày như guide còn sống. |
| BR-GUIDE-006 | Chỉ owner `Account` hoặc Admin operator được sửa metadata, retry, re-extract, revert, xóa. |
