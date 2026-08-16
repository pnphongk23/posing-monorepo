# ExtractionJob

## Description

Async job theo dõi trạng thái và payload của quá trình extraction ảnh pose qua Gemini. Worker poll và xử lý jobs theo thứ tự `created_at ASC`.

**Status:** `implemented` — Source: `web/services/pose-extract-server/src/db/schema.sql`, `extractionJobStore.ts`

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | TEXT (UUID) | PK | Server-generated UUID |
| `status` | TEXT | ✓ | Xem enum `ExtractionJobStatus` |
| `source_image_base64` | TEXT | ✓ | Base64 của ảnh nguồn |
| `source_mime_type` | TEXT | ✓ | MIME type của ảnh nguồn |
| `result_image_base64` | TEXT | — | Base64 kết quả khi `status = succeeded` |
| `result_mime_type` | TEXT | — | MIME type kết quả |
| `error_code` | TEXT | — | Error code khi failed hoặc lần attempt cuối |
| `error_message` | TEXT | — | Error message tương ứng |
| `attempts` | INTEGER | ✓ (default `0`) | Số lần đã attempt |
| `max_attempts` | INTEGER | ✓ (default `3`) | Số lần tối đa |
| `locked_at` | DATETIME | — | Timestamp khi worker claim job |
| `lock_token` | TEXT | — | Token để verify ownership của worker |
| `created_at` | DATETIME | ✓ | Thời điểm enqueue |
| `updated_at` | DATETIME | ✓ | Thời điểm cập nhật cuối |

## Relationships

- Không có FK vật lý tới `CommunityPose` (TBD — route tạo cả hai nhưng không lưu FK)
- Không có FK vật lý tới MediaAsset (TBD)

## Business Rules

| ID | Rule |
|---|---|
| BR-JOB-001 | Worker claim job bằng `claimNext`; nếu `locked_at` stale (quá `staleLockSeconds`), job được claim lại. |
| BR-JOB-002 | Khi `attempts >= max_attempts` và fail, `status` chuyển sang `failed`; ngược lại về `queued`. |
| BR-JOB-003 | Chỉ worker đang giữ `lock_token` mới có thể `markSucceeded` hoặc `markFailedOrRequeue`. |
| BR-JOB-004 | `GET /api/admin/jobs/:jobId` trả `result` chỉ khi `status = succeeded`; trả `error` chỉ khi `status = failed`. |
