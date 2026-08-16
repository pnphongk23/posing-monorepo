# ProviderRequestLog

## Description

Log từng request extraction gọi tới Gemini provider. Dùng cho diagnostic và giám sát usage.

**Status:** `implemented` — Source: `web/services/pose-extract-server/src/db/schema.sql`, `keyStore.ts`

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | INTEGER (autoincrement) | PK | Sequential log ID |
| `key_id` | TEXT (FK nullable) | — | Tham chiếu tới `api_keys.id`; NULL nếu key đã bị xóa |
| `timestamp` | DATETIME | ✓ | Thời điểm ghi log |
| `processing_time_ms` | INTEGER | — | Thời gian xử lý (ms); nullable |
| `success` | INTEGER | ✓ | `1` = thành công, `0` = thất bại |
| `error_code` | TEXT | — | Error code khi thất bại |

## Relationships

- Nhiều `ProviderRequestLog` → một `ApiKeyCredential` (nullable, ON DELETE SET NULL)

## Business Rules

| ID | Rule |
|---|---|
| BR-LOG-001 | Log được ghi cho cả thành công và thất bại trong extraction flow. |
| BR-LOG-002 | `key_id` là NULL khi log được ghi mà không có key, hoặc khi key đã bị xóa. |
| BR-LOG-003 | Không có retention/cleanup policy được implement; TBD. |
