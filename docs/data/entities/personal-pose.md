# PersonalPose

## Description

Pose/reference do người dùng sở hữu, lưu local trên thiết bị. Bảng SQLite tên `Pose` trong SQLDelight schema.

**Status:** `implemented` — Source: `mobile/shared/src/commonMain/sqldelight/com/aipose/Pose.sq`

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | INTEGER (autoincrement) | PK | Local unique ID |
| `name` | TEXT | ✓ | Tên pose |
| `imagePath` | TEXT | ✓ | Đường dẫn render asset (file path hoặc data URI) |
| `thumbnailPath` | TEXT | — | Nullable thumbnail locator |
| `originalImagePath` | TEXT | — | Nullable source image locator |
| `createdAt` | TEXT | ✓ | ISO 8601 timestamp |
| `isMine` | INTEGER | ✓ (default `1`) | `1` = pose của user này; `0` = community pose được cached local |
| `likes` | INTEGER | ✓ (default `0`) | Local like count |

## Relationships

- Được tham chiếu bởi `Photo.poseId`
- Được đại diện bởi `PoseReferenceKey.Personal(id)` trong mobile type system

## Business Rules

| ID | Rule |
|---|---|
| BR-POSE-001 | `isMine = 1` cho poses người dùng tạo; `isMine = 0` cho community poses được insert local. |
| BR-POSE-002 | `PersonalPose` không có server identity; không có FK hoặc sync tới `CommunityPose`. |
| BR-POSE-003 | `insertPoseWithId` cho phép insert với ID cụ thể (dùng khi sync community pose local). |
