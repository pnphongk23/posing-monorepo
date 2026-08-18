# SavedEntry

## Description

Bản ghi “đã lưu” giữa một signed-in [`Account`](account.md) và một pose đã published. Thuộc [FEAT-008](../../../harness/features/FEAT-008-use-published-poses.md). Không cấp ownership; không thay thế [`PoseGuide`](pose-guide.md).

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | TEXT (UUID) | PK | Định danh entry |
| `accountId` | TEXT (UUID) | ✓ | [`Account`](account.md) đã lưu |
| `poseId` | TEXT (UUID) | ✓ | `PoseGuide` / `CommunityPose` id |
| `savedAt` | DATETIME | ✓ | Thời điểm lưu |

## Relationships

- Nhiều `SavedEntry` → một `Account`
- Nhiều `SavedEntry` → một `CommunityPose` / `PoseGuide` (cùng `id`)
- Unique (`accountId`, `poseId`)

## Business Rules

| ID | Rule |
|---|---|
| BR-SAVED-001 | Chỉ lưu pose đang `published`. Lưu draft bị từ chối. |
| BR-SAVED-002 | Unique một entry cho mỗi cặp account + pose. Lưu lại pose đã lưu là idempotent. |
| BR-SAVED-003 | Unsave xóa entry của account đó; không đụng guide hay catalogue. |
| BR-SAVED-004 | Khi pose bị unpublish hoặc xóa, Saved collection không được trình bày pose đó như nội dung công khai còn hiệu lực. |
| BR-SAVED-005 | Use / Save không cấp quyền sửa, publish, hay xóa guide. |
