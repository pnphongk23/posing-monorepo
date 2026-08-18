# Photo

## Description

Ảnh still do Photographer chụp trên mobile, lưu local trên thiết bị. Bản ghi trung tâm của [FEAT-001](../../../harness/features/FEAT-001-capture-a-photo-on-mobile.md) (capture) và [FEAT-002](../../../harness/features/FEAT-002-manage-a-local-photo-gallery.md) (gallery). Không có HTTP API.

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | INTEGER | PK | Local unique ID |
| `imagePath` | TEXT | ✓ | Đường dẫn file local đọc được |
| `poseId` | INTEGER | — | Optional FK tới [`PersonalPose`](personal-pose.md) tại thời điểm chụp |
| `poseName` | TEXT | ✓ (default `''`) | Snapshot tên pose lúc chụp |
| `createdAt` | TEXT | ✓ | ISO 8601 |
| `isFavorite` | INTEGER | ✓ (default `0`) | `0` false, `1` true |

## Relationships

- `Photo.poseId` → `PersonalPose.id` (optional, ON DELETE SET NULL)
- Không FK tới entity server

## Business Rules

| ID | Rule |
|---|---|
| BR-PHOTO-001 | Một capture được chấp nhận tạo đúng một `Photo` và một file ảnh đọc được. Thiếu một trong hai thì không được báo thành công. |
| BR-PHOTO-002 | Capture bị tắt cho đến khi camera permission được cấp. |
| BR-PHOTO-003 | Xóa photo chỉ hoàn tất khi metadata và file thuộc sở hữu đều đã gỡ. File còn lại thì không được báo xóa xong. |
| BR-PHOTO-004 | Favorite, delete, export chỉ hiện success sau khi hành động đã xác nhận. |
| BR-PHOTO-005 | Metadata trỏ file không đọc được thì UI placeholder + recovery; không crash, không giả render hợp lệ. |
| BR-PHOTO-006 | Xóa `PersonalPose` không xóa `Photo`; `poseId` SET NULL. `poseName` là snapshot, không đổi theo rename. |
