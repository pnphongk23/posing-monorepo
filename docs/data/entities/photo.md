# Photo

## Description

Ảnh do người dùng chụp, lưu local trên thiết bị. Là bản ghi trung tâm của Camera và Gallery feature.

**Status:** `implemented` — Source: `mobile/shared/src/commonMain/sqldelight/com/aipose/Photo.sq`

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | INTEGER (autoincrement) | PK | Local unique ID |
| `imagePath` | TEXT | ✓ | Đường dẫn file local hoặc data URI |
| `poseId` | INTEGER (FK nullable) | — | Tham chiếu tới `Pose.id`; SET NULL khi Pose bị xóa |
| `poseName` | TEXT | ✓ (default `''`) | Snapshot tên pose tại thời điểm chụp |
| `createdAt` | TEXT | ✓ | ISO 8601 timestamp |
| `isFavorite` | INTEGER | ✓ (default `0`) | `0` = false, `1` = true |

## Relationships

- `Photo.poseId` → `PersonalPose.id` (optional, ON DELETE SET NULL)
- Không có FK tới bất kỳ entity server nào

## Business Rules

| ID | Rule |
|---|---|
| BR-PHOTO-001 | Xóa `PersonalPose` không xóa `Photo`; `poseId` được set NULL. |
| BR-PHOTO-002 | `poseName` là snapshot — không tự cập nhật khi pose được rename. |
| BR-PHOTO-003 | `isFavorite` toggle qua query `toggleFavorite`; giá trị là 0 hoặc 1, không phải boolean native. |
