# CommunityPose

## Description

Projection công khai của một [`PoseGuide`](pose-guide.md) đã `published`. Catalogue [FEAT-003](../../../harness/features/FEAT-003-browse-and-search-published-poses.md) chỉ đọc entity này. Visibility do [FEAT-006](../../../harness/features/FEAT-006-publish-a-pose.md) quyết định.

Cùng `id` với `PoseGuide`. Public DTO không gồm owner, source asset, hay job.

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | TEXT (UUID) | PK | Trùng `PoseGuide.id` |
| `name` | TEXT | ✓ | Tên pose |
| `imagePath` | TEXT | ✓ | URI render `ready` (camelCase DTO) |
| `thumbnailPath` | TEXT | — | URI thumbnail `ready` nếu có |
| `tags` | TEXT[] | ✓ | Nhãn |
| `difficulty` | TEXT | — | Enum `PoseDifficulty` |
| `description` | TEXT | — | Mô tả |
| `bodyParts` | TEXT[] | ✓ | Phần cơ thể |
| `status` | TEXT | ✓ | Luôn `published` trên public API |
| `uploadedAt` | DATETIME | ✓ | Thời điểm guide vào catalogue |
| `downloadCount` | INTEGER | ✓ (default `0`) | Tăng khi GET detail thành công |

## Relationships

- `CommunityPose.id` = `PoseGuide.id`
- `imagePath` / `thumbnailPath` ← [`MediaAsset`](media-asset.md) role `render` / `thumbnail` với `readiness = ready`
- Được [`SavedEntry.poseId`](saved-entry.md) tham chiếu
- Variant `PoseReferenceKey.Community(id)` trên mobile

## Business Rules

| ID | Rule |
|---|---|
| BR-COMMUNITY-001 | Public list/detail chỉ trả `status = published`. Draft không lộ qua 404. |
| BR-COMMUNITY-002 | `downloadCount` tăng 1 mỗi lần `GET /api/community/poses/:id` thành công. |
| BR-COMMUNITY-003 | Admin đọc được cả `draft` và `published` qua API admin/guide, không qua public catalogue. |
| BR-COMMUNITY-004 | `imagePath` phải là locator render `ready`. Pose chưa có render `ready` không được `published`. |
| BR-COMMUNITY-005 | Title search (`q`) chỉ khớp trên published records; không trả draft. |
| BR-COMMUNITY-006 | Filter `tag` và `difficulty` áp trên published list; kết quả không trùng `id` đang active. |
