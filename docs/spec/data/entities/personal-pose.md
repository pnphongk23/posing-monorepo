# PersonalPose

## Description

Pose/reference cá nhân lưu local trên thiết bị. Dùng trong gallery ([FEAT-002](../../../harness/features/FEAT-002-manage-a-local-photo-gallery.md)) và khi mobile persist kết quả extraction ([FEAT-004](../../../harness/features/FEAT-004-extract-reusable-pose-images.md)). Không đồng bộ lên [`CommunityPose`](community-pose.md).

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | INTEGER | PK | Local unique ID |
| `name` | TEXT | ✓ | Tên pose |
| `imagePath` | TEXT | ✓ | Locator render local (file path hoặc data URI) |
| `thumbnailPath` | TEXT | — | Thumbnail local |
| `originalImagePath` | TEXT | — | Ảnh nguồn local |
| `createdAt` | TEXT | ✓ | ISO 8601 |
| `isMine` | INTEGER | ✓ (default `1`) | `1` do user tạo; `0` bản cache community (nếu có) |
| `likes` | INTEGER | ✓ (default `0`) | Đếm local |

## Relationships

- Được `Photo.poseId` tham chiếu
- Variant `PoseReferenceKey.Personal(id)` trên mobile

## Business Rules

| ID | Rule |
|---|---|
| BR-POSE-001 | `PersonalPose` không có server identity và không FK tới `CommunityPose`. |
| BR-POSE-002 | `isMine = 1` cho pose user tạo trên máy; không nhầm với pose cộng đồng published. |
| BR-POSE-003 | Persist kết quả FEAT-004 trên mobile tạo `PersonalPose` local; không publish hộ. |
