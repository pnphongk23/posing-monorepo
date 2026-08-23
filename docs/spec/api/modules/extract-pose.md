# Module: Extract Pose

Một ảnh nguồn → một ảnh pose dùng lại được. [FEAT-004](../../../harness/features/FEAT-004-extract-reusable-pose-images.md).

Persistence thuộc caller hoặc [`Pose`](../../data/entities/pose.md) ([FEAT-005](../../../harness/features/FEAT-005-manage-a-pose-guide.md)). Route này không publish.

Kết quả job (`result`) là ảnh **skeleton** — ảnh pose dùng lại được do AI chiết tách từ ảnh nguồn.

Engine xử lý được chọn toàn cục bởi Admin qua [FEAT-009](../../../harness/features/FEAT-009-configure-extraction-provider.md) và [DEC-001](../../../harness/decisions/DEC-001-extraction-provider-selection-policy.md); caller không chọn provider.

**Creation timing:** `POST /api/extract-pose` chỉ **enqueue job** (`202` + `jobId`)
— **không tạo `Pose`** tại đây. `Pose` (với `poseId` stable) chỉ được tạo sau khi
job `succeeded`, qua `POST /api/guides` (owner) hoặc admin intake (`201 Created`)
— xem [guides.md](guides.md). `jobId` là correlation key trong lúc extraction.

## Phase 1 contract (async)

Canonical extract enqueue một `ExtractionJob` và trả `202 Accepted`; client poll job status cho đến khi `succeeded` hoặc `failed`. Mobile async client **ngoài phạm vi** Plan 260816-2240 — server contract được ghi nhận tại đây.

### POST /api/extract-pose

**Authentication / Permission:** Không. Rate limit theo IP.

**Request:** `multipart/form-data`, field `image` (JPEG hoặc PNG, tối đa 10 MB). OperationId `extractPose` trong [openapi.yaml](../openapi.yaml).

**Response:** `202 Accepted`

```json
{
  "success": true,
  "data": { "jobId": "<uuid>", "status": "queued" },
  "meta": { "pollUrl": "/api/extract-jobs/<uuid>" }
}
```

**Business Rules:**

| ID | Rule |
|---|---|
| BR-EXTRACT-001 | Chọn key `active` (engine `gemini_native`); hết quota thì đánh `exhausted` và xoay key. |
| BR-EXTRACT-002 | Hết key `active` → `503 ALL_KEYS_EXHAUSTED` (pre-queue) hoặc job `error_code` `PROVIDER_CREDENTIALS_EXHAUSTED`. |
| BR-EXTRACT-003 | Mỗi attempt ghi [`ProviderRequestLog`](../../data/entities/provider-request-log.md). |
| BR-EXTRACT-005 | Provider thất bại thì không tuyên bố usable image. |
| BR-EXTRACT-006 | Ảnh không hợp lệ / quá lớn thì không enqueue job. |
| BR-EXTRACT-007 | Worker dùng engine toàn cục tại thời điểm `claimNext` (DEC-001 B1). |

**Pre-queue errors (HTTP):**

| Code | HTTP | Khi nào |
|---|---|---|
| `INVALID_IMAGE` | 400 | Thiếu file, MIME không hỗ trợ, format lỗi |
| `IMAGE_TOO_LARGE` | 413 | > 10 MB |
| `RATE_LIMITED` | 429 | Vượt IP limit |

### GET /api/extract-jobs/:jobId

**Authentication / Permission:** Không. Rate limit theo IP.

**Response:** `200` khi job tồn tại

```json
{
  "success": true,
  "data": {
    "jobId": "<uuid>",
    "status": "queued | processing | succeeded | failed",
    "result": { "imageBase64": "...", "mimeType": "image/png" },
    "error": { "code": "PROVIDER_ERROR", "message": "..." },
    "updatedAt": "2026-08-17T12:00:00.000Z"
  }
}
```

`result` chỉ có khi `status === "succeeded"`. Trường `error` (object `{ code, message }`) chỉ có khi `status === "failed"`.

Sau khi `succeeded`, client dùng `jobId` này để **tạo `Pose`** (`POST /api/guides`,
`201`) — `Pose` chưa tồn tại trong lúc extraction.

**Job `error_code` values (provider-neutral):**

| Code | Khi nào |
|---|---|
| `PROVIDER_QUOTA_EXCEEDED` | Provider quota exhausted |
| `PROVIDER_CREDENTIALS_EXHAUSTED` | Không còn active key (Gemini) |
| `PROVIDER_ERROR` | Provider lỗi chung |
| `PROVIDER_AUTH_REQUIRED` | Higgsfield credentials missing/expired |
| `PROVIDER_TIMEOUT` | CLI hoặc provider timeout |
| `PROVIDER_CLI_FAILED` | Higgsfield CLI spawn/parse failure |

**Deprecated aliases (một release):** `GEMINI_QUOTA_EXCEEDED` → `PROVIDER_QUOTA_EXCEEDED`; `GEMINI_ERROR` → `PROVIDER_ERROR`. Clients nên migrate sang `PROVIDER_*`.

## Legacy sync contract (deprecated)

Trước Plan 260816-2240, `POST /api/extract-pose` trả `200` đồng bộ:

```json
{ "success": true, "data": { "imageBase64", "mimeType", "processingTimeMs }, "meta": { "keyUsed", "quotaRemaining" } }
```

**Deprecated sync errors:**

| Code | HTTP | Khi nào |
|---|---|---|
| `GEMINI_QUOTA_EXCEEDED` | 429 | Quota, không còn key khác — alias của `PROVIDER_QUOTA_EXCEEDED` |
| `ALL_KEYS_EXHAUSTED` | 503 | Không còn active key |
| `GEMINI_ERROR` | 500 | Provider lỗi không phải quota — alias của `PROVIDER_ERROR` |
| `INTERNAL_SERVER_ERROR` | 500 | Lỗi không xử lý được |

Legacy `POST /api/extract` (Next.js / Replicate) không thuộc module này — [conventions.md](../conventions.md).
