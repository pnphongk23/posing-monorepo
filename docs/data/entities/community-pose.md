# CommunityPose

## Description

Metadata của một pose trong catalog cộng đồng, lưu trên server. Record do admin tạo và quản lý; public chỉ thấy những record có `status = published`.

**Status:** `implemented` — Source: `web/services/pose-extract-server/src/db/schema.sql`, `communityStore.ts`

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | TEXT (UUID) | PK | Server-generated UUID |
| `name` | TEXT | ✓ | Tên pose |
| `image_path` | TEXT | ✓ | URL đầy đủ tới R2 asset (camelCase DTO: `imagePath`) |
| `thumbnail_path` | TEXT | — | Nullable thumbnail URL (camelCase DTO: `thumbnailPath`) |
| `tags` | TEXT | ✓ (default `'[]'`) | JSON array string (camelCase DTO: `tags: string[]`) |
| `difficulty` | TEXT | — | Nullable; xem enum `PoseDifficulty` |
| `description` | TEXT | — | Nullable mô tả |
| `body_parts` | TEXT | ✓ (default `'[]'`) | JSON array string (camelCase DTO: `bodyParts: string[]`) |
| `status` | TEXT | ✓ (default `'draft'`) | Xem enum `PoseStatus` |
| `uploaded_at` | DATETIME | ✓ | Server timestamp khi tạo |
| `download_count` | INTEGER | ✓ (default `0`) | Tăng mỗi lần gọi GET detail (public) |

## Relationships

- Không có FK vật lý tới `ExtractionJob` (TBD)
- Không có FK vật lý tới bất kỳ asset table nào (TBD)
- `image_path` chứa URL dạng string trỏ tới R2 storage

## Business Rules

| ID | Rule |
|---|---|
| BR-COMMUNITY-001 | Public API chỉ trả về poses có `status = published`. |
| BR-COMMUNITY-002 | `download_count` tăng 1 mỗi lần gọi `GET /api/community/poses/:id` thành công. |
| BR-COMMUNITY-003 | Admin có thể đọc cả `draft` và `published`. |
| BR-COMMUNITY-004 | Không có update/delete/unpublish route trong server route set hiện tại. |
| BR-COMMUNITY-005 | `image_path` được build từ `R2_PUBLIC_URL` + generated key tại thời điểm tạo; không link FK tới extraction job result. |
