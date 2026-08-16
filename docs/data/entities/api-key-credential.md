# ApiKeyCredential

## Description

Provider API key (Gemini) được server dùng cho extraction. Admin quản lý; secret không bao giờ trả về trong public response.

**Status:** `implemented` — Source: `web/services/pose-extract-server/src/db/schema.sql`, `keyStore.ts`

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | TEXT (UUID) | PK | Server-generated UUID |
| `name` | TEXT | ✓ | Label mô tả key |
| `api_key` | TEXT | ✓ | Secret key; bị omit trong mọi API response |
| `status` | TEXT | ✓ (default `'active'`) | Xem enum `ApiKeyStatus` |
| `requests_today` | INTEGER | ✓ (default `0`) | Đếm số request trong ngày |
| `created_at` | DATETIME | ✓ | Thời điểm tạo |
| `last_used_at` | DATETIME | — | Thời điểm sử dụng cuối |

## Relationships

- Một `ApiKeyCredential` có nhiều `ProviderRequestLog` (nullable FK, ON DELETE SET NULL)

## Business Rules

| ID | Rule |
|---|---|
| BR-KEY-001 | `api_key` secret bị loại bỏ (`toPublicKeyRecord`) trong mọi response của admin API. |
| BR-KEY-002 | Khi key bị đánh dấu `exhausted`, `resetDailyCounters` sẽ reset về `active` và `requests_today = 0`. |
| BR-KEY-003 | `KeyPoolManager` chọn key `active` theo vòng; nếu hết key active, trả `AllKeysExhaustedError`. |
| BR-KEY-004 | `GeminiQuotaExceededError` trong extraction tự động mark key là `exhausted` và thử key tiếp theo. |
