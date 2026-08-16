# Module: Extract Pose

## POST /api/extract-pose

Gửi ảnh JPEG/PNG, nhận ảnh đã extract pose qua Gemini (synchronous).

**Authentication / Permission:** Không yêu cầu auth. Rate limit: IP-based, default 10 req/60s.

**Request:** `multipart/form-data`, field `image` (JPEG hoặc PNG, tối đa 10 MB). Xem operationId `extractPose` trong [openapi.yaml](../openapi.yaml).

**Response:** `200` với `{ success, data: { imageBase64, mimeType, processingTimeMs }, meta: { keyUsed, quotaRemaining } }`. Xem operationId `extractPose`.

**Business Rules:**

| ID | Rule |
|---|---|
| BR-EXTRACT-001 | Route chọn key `active` từ pool; nếu key trả `GeminiQuotaExceeded`, tự động mark `exhausted` và thử key tiếp theo. |
| BR-EXTRACT-002 | Nếu tất cả key đều `exhausted`, trả `503 ALL_KEYS_EXHAUSTED`. |
| BR-EXTRACT-003 | Mỗi attempt ghi một `ProviderRequestLog` (success hoặc fail). |
| BR-EXTRACT-004 | `quotaRemaining` trong meta là ước tính `~N%` dựa trên `requestsToday`; không phải giá trị chính xác từ provider. |

**Errors:**

| Code | HTTP | Khi nào |
|---|---|---|
| `INVALID_IMAGE` | 400 | File thiếu, MIME không phải JPEG/PNG, hoặc format lỗi |
| `IMAGE_TOO_LARGE` | 413 | File > 10 MB |
| `RATE_LIMITED` | 429 | Vượt IP rate limit |
| `GEMINI_QUOTA_EXCEEDED` | 429 | Quota key bị vượt (khi retry không thể dùng key khác) |
| `ALL_KEYS_EXHAUSTED` | 503 | Không còn active key |
| `GEMINI_ERROR` | 500 | Provider Gemini lỗi không phải quota |
| `INTERNAL_SERVER_ERROR` | 500 | Lỗi không xử lý được |
