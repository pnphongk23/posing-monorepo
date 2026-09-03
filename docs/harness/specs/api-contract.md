---
schema_version: 1
type: spec
title: API Contract
status: draft
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[data-contract]]"
    - "[[pose-domain-glossary]]"
    - "[[product-feature-inventory]]"
  decisions:
    - "[[DEC-001-extraction-provider-selection-policy|DEC-001]]"
  plans: []
  reports: []
  rules: []
  features:
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
    - "[[FEAT-006-publish-a-pose|FEAT-006]]"
    - "[[FEAT-007-operate-pose-content-from-admin-web|FEAT-007]]"
    - "[[FEAT-008-use-published-poses|FEAT-008]]"
  source_paths:
    - web/services/pose-extract-server/src/app.ts
    - web/services/pose-extract-server/src/routes/adminRoutes.ts
    - web/services/pose-extract-server/src/routes/extractPoseRoutes.ts
    - web/services/pose-extract-server/src/routes/communityRoutes.ts
    - web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts
    - web/services/pose-extract-server/src/routes/jobStatusRoutes.ts
    - web/admin-ui/src/app/api
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt
---

# API Contract

Single source of truth cho **HTTP contract product** của ai-pose: paths, schemas,
status codes, conventions, và semantics theo module. Mô tả hợp đồng **mà Features
yêu cầu**; tên path/field tiếng Anh, mô tả tiếng Việt. URL thật `/api/...`,
không có `/v1/`.

Schemas chi tiết: [`openapi.yaml`](./api/openapi.yaml) (OpenAPI 3.1). Domain model:
[`data-contract.md`](./data-contract.md).

**Creation timing & status codes:** `Pose` được tạo **chỉ sau khi extraction
`succeeded`** — `202 Accepted` là job start (`jobId`, chưa có Pose); `201 Created`
là Pose creation/completion (pose được tạo với `poseId` stable và ba media role
`original`, `skeleton`, `thumbnail` materialize ngay). `ownerAccountId` bắt buộc
trên mọi Pose; response dùng camelCase `poseId`, `ownerAccountId`, `originalUrl`,
`skeletonUrl`, `thumbnailUrl`. `CommunityPose` là published-only DTO.

## Routes theo Feature

| Feature | Module | Path prefix |
|---|---|---|
| — | [Health](#health) | `GET /api/health` |
| FEAT-003 | [Community](#community-public) | `GET /api/community/poses` |
| FEAT-004 | [Extract Pose](#extract-pose) | `POST /api/extract-pose` |
| FEAT-005 | [Pose Guides](#pose-guides) | `/api/guides` |
| FEAT-006 | [Publish](#publish) | `/api/guides/:id/publish`, `/unpublish` |
| FEAT-007 | [Admin Keys](#admin-keys), [Admin Community](#admin-community), [Admin Jobs](#admin-jobs) | `/api/admin/*` |
| FEAT-008 | [Saved](#saved) | `/api/me/saved` |

Try Pose không có HTTP: chuẩn bị local từ detail published. Capture/gallery không
có HTTP. Admin Web không định nghĩa API riêng: proxy inject Bearer, contract nằm
ở các module trên.

## Conventions

### URL naming

- Mọi business route mount `/api/...`. Không có prefix `/v1/`.
- Public catalogue: `/api/community/poses`
- Pose (model hợp nhất thành `Pose`): `/api/guides`
- Signed-in collection: `/api/me/saved`
- Admin: `/api/admin/keys`, `/api/admin/community/poses`, `/api/admin/jobs`
- Health: `/api/health`
- Direct extract: `/api/extract-pose`

### HTTP methods và status codes

| Trường hợp | Method | Status |
|---|---|---|
| Đọc | GET | 200 |
| **Job start** (enqueue extraction, retry, re-extract) | POST | **202** |
| **Pose creation/completion** (post-extraction) | POST | **201** |
| Cập nhật partial | PATCH | 200 |
| Publish / unpublish / revert (đổi trạng thái) | POST | 200 |
| Xóa | DELETE | 204 (empty body) |
| Upsert saved | PUT | 200 |
| Reset counters | POST | 200 |

`202` = đã nhận job, chưa complete, chưa public, **chưa có `Pose`**. `201` =
`Pose` được tạo với `poseId` stable và ba media role materialize ngay.

### Authentication

| Actor | Cơ chế | Routes |
|---|---|---|
| Visitor | Không auth | `GET /api/community/poses`, `GET /api/community/poses/:id`, `POST /api/extract-pose`, `GET /api/health` |
| Signed-in `Account` | Session của Account | `/api/me/saved`, `/api/guides` (owner) |
| Admin operator | `Authorization: Bearer <ADMIN_SECRET>` | `/api/admin/*`; Admin cũng gọi `/api/guides` và publish |

**authenticated actor vs owner:** `ownerAccountId` là **bắt buộc** trên mọi
`Pose`. Với `AccountSession`, owner = session account (không gửi trong body).
Với Admin `Bearer`, request tạo pose phải kèm `ownerAccountId` tường minh.
Secret admin không bao giờ gửi từ browser.

### Rate limiting

- `POST /api/extract-pose`: giới hạn theo IP.
- `/api/admin/keys` và `/api/admin/community/*`: giới hạn admin.
- `GET /api/admin/jobs/:jobId` có Bearer, không gắn admin rate-limit (cần poll).

### Pagination

```json
{
  "data": [ ... ],
  "pagination": { "page": 1, "limit": 20, "total": 42 }
}
```

`page` default `1`; `limit` max `100` (default 20 public, 50 admin); `total` =
tổng record thỏa filter.

### Filtering và search

`GET /api/community/poses`: `difficulty` (enum `PoseDifficulty`), `tag` (khớp
tag), `q` (tìm theo title trên published records). Không trả pose `local`
(legacy `draft`) trên public search/list.

### Error envelope

```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Mô tả human-readable"
  }
}
```

Lỗi chung: `401 UNAUTHORIZED`, `403 FORBIDDEN`, `404 NOT_FOUND`,
`409 CONFLICT` (eligibility), `500 INTERNAL_SERVER_ERROR`.

### Datetime

ISO 8601 strings.

### Next.js proxy (không phải contract riêng)

Admin UI forward sang `pose-extract-server`. Contract chỉ nằm ở Express.

| Next.js path | Upstream |
|---|---|
| `POST /api/admin/extract-pose` | `POST /api/extract-pose` |
| `GET, POST /api/admin/community/poses` | `/api/admin/community/poses` |
| `GET, POST /api/admin/keys` | `/api/admin/keys` |
| `PATCH, DELETE /api/admin/keys/:id` | `/api/admin/keys/:id` |
| `POST /api/admin/keys/reset` | `/api/admin/keys/reset` |
| Job poll | `GET /api/admin/jobs/:jobId` |

### Legacy route

`POST /api/extract` trên Next.js (Replicate) không thuộc contract này. Direct
extract canonical là `POST /api/extract-pose` (FEAT-004).

## Health

### GET /api/health

Kiểm tra trạng thái server. Không auth, không query/body. Response xem operationId
`getHealth` trong `openapi.yaml`.

```json
{ "status": "ok", "uptime": 123.4, "version": "1.0.0" }
```

## Community (Public)

Catalogue published `Pose` (FEAT-003). Không auth. Chỉ `status = published`.
Catalogue là **DTO/view đọc kết quả** (`CommunityPose`) lọc các `Pose` có
`status = published` — DTO published-only: `poseId` (cùng `Pose.poseId`),
`status` luôn `published`; không lộ `ownerAccountId`, `originalUrl`, hay job.

### GET /api/community/poses

Danh sách published, pagination, filter, tìm theo title.

- Query: `page` (default 1), `limit` (max 100, default 20), `difficulty`,
  `tag`, `q` (tìm theo `name`, case-insensitive substring trên published records)
- Response: `200` `{ data: CommunityPose[], pagination }` — operationId `listCommunityPoses`

| ID | Rule |
|---|---|
| BR-COMMUNITY-001 | Chỉ `published`. |
| BR-COMMUNITY-005 | `q` không trả pose `local`. |
| BR-COMMUNITY-006 | Kết quả không trùng `poseId` active trên một trang. |

**Errors:** `400 BAD_REQUEST`, `500 INTERNAL_SERVER_ERROR`.

### GET /api/community/poses/:id

Chi tiết một published pose. Tăng `downloadCount`.

- Path `id` (UUID); operationId `getCommunityPose`
- Response: `200` `{ data: CommunityPose }`

| ID | Rule |
|---|---|
| BR-COMMUNITY-002 | `downloadCount` +1 khi thành công. |
| BR-COMMUNITY-007 | Tồn tại nhưng không `published` → `404` (không leak pose `local`). |
| BR-COMMUNITY-004 | `skeletonUrl` là locator skeleton `ready`; `thumbnailUrl` non-nullable. |

**Errors:** `404 NOT_FOUND`, `500 INTERNAL_SERVER_ERROR`.

## Extract Pose

Một ảnh nguồn → một ảnh pose dùng lại được (FEAT-004). Persistence thuộc caller
hoặc `Pose` (FEAT-005); route này không publish. Kết quả job (`result`) là ảnh
**skeleton**. Engine xử lý được chọn toàn cục bởi Admin qua FEAT-009 + DEC-001;
caller không chọn provider.

**Creation timing:** `POST /api/extract-pose` chỉ **enqueue job** (`202` +
`jobId`) — **không tạo `Pose`** tại đây. `Pose` (với `poseId` stable) chỉ được tạo
sau khi job `succeeded`, qua `POST /api/guides` (owner) hoặc admin intake (`201`).

### POST /api/extract-pose (async — canonical)

- Không auth. Rate limit theo IP.
- Request: `multipart/form-data`, field `image` (JPEG/PNG, tối đa 10 MB).
  OperationId `extractPose`.
- Response: `202 Accepted`

```json
{
  "success": true,
  "data": { "jobId": "<uuid>", "status": "queued" },
  "meta": { "pollUrl": "/api/extract-jobs/<uuid>" }
}
```

| ID | Rule |
|---|---|
| BR-EXTRACT-001 | Chọn key `active`; hết quota thì đánh `exhausted` và xoay key. |
| BR-EXTRACT-002 | Hết key `active` → `503 ALL_KEYS_EXHAUSTED` (pre-queue) hoặc job `error_code` `PROVIDER_CREDENTIALS_EXHAUSTED`. |
| BR-EXTRACT-003 | Mỗi attempt ghi `ProviderRequestLog`. |
| BR-EXTRACT-005 | Provider thất bại thì không tuyên bố usable image. |
| BR-EXTRACT-006 | Ảnh không hợp lệ / quá lớn thì không enqueue job. |
| BR-EXTRACT-007 | Worker dùng engine toàn cục tại thời điểm `claimNext`. |

**Pre-queue errors:** `INVALID_IMAGE` 400, `IMAGE_TOO_LARGE` 413, `RATE_LIMITED` 429.

### GET /api/extract-jobs/:jobId

- Không auth. Rate limit theo IP. OperationId (poll).
- Response: `200` khi job tồn tại; `result` chỉ khi `status === "succeeded"`;
  `error` (object `{ code, message }`) chỉ khi `status === "failed"`.

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

Sau `succeeded`, client dùng `jobId` để **tạo `Pose`** (`POST /api/guides`, `201`).

**Job `error_code` values (provider-neutral):** `PROVIDER_QUOTA_EXCEEDED`,
`PROVIDER_CREDENTIALS_EXHAUSTED`, `PROVIDER_ERROR`, `PROVIDER_AUTH_REQUIRED`,
`PROVIDER_TIMEOUT`, `PROVIDER_CLI_FAILED`. Deprecated aliases (một release):
`GEMINI_QUOTA_EXCEEDED` → `PROVIDER_QUOTA_EXCEEDED`; `GEMINI_ERROR` →
`PROVIDER_ERROR`.

### Legacy sync contract (deprecated)

Trước Plan 260816-2240, `POST /api/extract-pose` trả `200` đồng bộ
`{ success, data: { imageBase64, mimeType, processingTimeMs }, meta: { keyUsed, quotaRemaining } }`.

**Deprecated sync errors:** `GEMINI_QUOTA_EXCEEDED` 429, `ALL_KEYS_EXHAUSTED` 503,
`GEMINI_ERROR` 500, `INTERNAL_SERVER_ERROR` 500.

## Pose Guides

Lifecycle `Pose` (FEAT-005). Owner `Account` hoặc Admin operator.

### GET /api/guides

Danh sách pose của caller (My Poses). Admin có thể liệt kê theo owner.
Signed-in Account hoặc Bearer admin. Query `page`, `limit`. OperationId
`listGuides`. Response: `200` paginated `Pose`.

### POST /api/guides

Tạo `Pose` `local` **sau khi extraction `succeeded`** (post-extraction). Không
nhận ảnh — ảnh đã nộp qua `POST /api/extract-pose` (`202` + `jobId`).

- Request JSON — operationId `createGuide`:

| Field | Required | Ghi chú |
|---|---|---|
| `jobId` | ✓ | `jobId` của `ExtractionJob` đã `succeeded` |
| `ownerAccountId` | admin | Bắt buộc khi gọi bằng Admin Bearer; bỏ qua với `AccountSession` |
| `name` | ✓ | Non-empty |
| `bodyParts` | ✓ | Ít nhất 1 item |
| `tags` / `difficulty` / `description` | — | |

- Response: `201 Created` `{ data: { pose: Pose } }` — `poseId` stable, `status =
  local`, ba `MediaAsset` materialize ngay (`originalUrl`/`skeletonUrl`/`thumbnailUrl`).

| ID | Rule |
|---|---|
| BR-GUIDE-001 | `202` (job start) ≠ Pose tồn tại; pose chỉ tạo sau khi job `succeeded` (`201`). |
| BR-GUIDE-002 | Không public cho đến khi skeleton `MediaAsset` `ready`. |
| BR-GUIDE-003 | `jobId` chưa `succeeded` thì từ chối tạo pose (`400 JOB_NOT_SUCCEEDED` / `404`). |

**Errors:** `400 JOB_NOT_SUCCEEDED` / `BAD_REQUEST`, `401`, `404`, `500`.

### GET /api/guides/:id

Đọc một pose (metadata, assets, current job). Owner hoặc Admin. `200` `{ data: Pose }`.

### PATCH /api/guides/:id

Sửa metadata (`name`, `description`, `tags`, `difficulty`, `bodyParts`). Không đổi
visibility. Owner/Admin. `200` `{ data: Pose }`.

### POST /api/guides/:id/retry

Retry job `failed` còn trong chính sách, hoặc requeue job hiện tại (BR-JOB-002).
Owner/Admin. `202` `ExtractionJobAccepted` — job start, không tạo Pose mới.

### POST /api/guides/:id/re-extract

Tạo `ExtractionJob` mới từ source hiện hành. Không tạo pose mới. Owner/Admin. `202`.

### POST /api/guides/:id/revert

Khôi phục skeleton `ready` trước đó. Không publish hộ. Owner/Admin. `200`.
`409 CONFLICT` nếu không có skeleton trước để revert.

### DELETE /api/guides/:id

Xóa terminal. Gỡ khỏi catalogue nếu đang published; Saved không trình bày như
public. Owner/Admin. `204`.

## Publish

Chuyển visibility của `Pose` (FEAT-006). Không định nghĩa extraction hay guide
mới. Admin Web gọi cùng endpoints.

### POST /api/guides/:id/publish

Đưa pose ra public catalogue khi đủ điều kiện. Publish chỉ đổi `status`, `poseId`
giữ nguyên. Owner `Account` hoặc Bearer admin. Body rỗng. `200` `{ data: Pose }`
với `status = published`.

| ID | Rule |
|---|---|
| BR-PUBLISH-001 | Chỉ publish khi skeleton `MediaAsset` `ready` và locator đọc được. |
| BR-PUBLISH-002 | Thiếu thẩm quyền thì giữ visibility cũ. |
| BR-PUBLISH-003 | Không publish từ `202` queued. |

**Errors:** `401`, `403`, `404`, `409 CONFLICT` (`ASSET_NOT_READY`).

### POST /api/guides/:id/unpublish

Gỡ khỏi public discovery. Pose về `local` cho owner/Admin. `200` `{ data: Pose }`
với `status = local`; public list/detail ngừng trả id (`404`). Không xóa pose
(BR-PUBLISH-004); Saved không trình bày như public (BR-SAVED-004).

## Saved

Collection cá nhân của signed-in `Account` (FEAT-008). Try Pose không có HTTP —
client tải skeleton published, verify, rồi cầm `PreparedPoseReference`.

### GET /api/me/saved

Danh sách pose đang lưu; chỉ pose vẫn `published` được trả như mục công khai còn
hiệu lực. Signed-in Account. `200` paginated DTO public (`CommunityPose`) — view
projection read-only.

### PUT /api/me/saved/:poseId

Lưu một published pose. Idempotent nếu đã lưu. Signed-in Account.

| ID | Rule |
|---|---|
| BR-SAVED-001 | Chỉ pose `published`. |
| BR-SAVED-002 | Unique (`accountId`, `poseId`); PUT lần hai không tạo bản sao. |
| BR-SAVED-005 | Không cấp quyền owner/publish. |

**Errors:** `401`, `404`.

### DELETE /api/me/saved/:poseId

Unsave. Không đụng pose. Signed-in Account. `204`. Idempotent. `401`.

## Admin Keys

Quản lý Gemini API keys. Tất cả routes: `Authorization: Bearer <ADMIN_SECRET>`
(và admin rate-limit).

- `GET /api/admin/keys` — `200` `{ data: ApiKeyPublic[] }`, `apiKey` bị loại bỏ.
- `POST /api/admin/keys` — `201` `{ data: ApiKeyPublic }`; secret bị loại bỏ.
- `PATCH /api/admin/keys/:id` — `200`; status phải `active`/`disabled`/`exhausted` (BR-KEY-005).
- `DELETE /api/admin/keys/:id` — `204`.
- `POST /api/admin/keys/reset` — `200` `{ data: { updated } }`; keys `exhausted`
  về `active`, `disabled` không đổi (BR-KEY-002).

## Admin Community

Intake và listing community từ Admin Web (FEAT-007). Không tạo model
pose/publication riêng. Tất cả routes: `Authorization: Bearer <ADMIN_SECRET>`.

### GET /api/admin/community/poses

Danh sách mọi `Pose` (`local` và `published`), mới nhất trước. Trả canonical
`Pose` (PoseResponse), không phải `CommunityPose` DTO; `ownerAccountId` xuất hiện
trên mỗi pose. Admin rate-limit. Query `page`, `limit` (default 50, max 100).

### POST /api/admin/community/poses/upload-url

Presigned URL để PUT ảnh lên object storage. JSON body. MIME: `image/png`,
`image/jpeg`, `image/webp`. `200` `{ data: { uploadUrl, fileKey } }`.

### POST /api/admin/community/poses

Tạo `Pose` `local` **sau khi extraction `succeeded`** — cùng hợp đồng hai pha với
`POST /api/guides` (admin acting as operator). Ảnh nộp trước qua
`POST /api/extract-pose`; route này không nhận ảnh. Không nhận `status = published`.

| Field | Required | Ghi chú |
|---|---|---|
| `jobId` | ✓ | `jobId` của `ExtractionJob` đã `succeeded` |
| `ownerAccountId` | ✓ | **Bắt buộc** — Admin dùng Bearer (không session account) |
| `name` / `bodyParts` | ✓ | Non-empty / ≥ 1 item |
| `tags` / `difficulty` / `description` | — | |

**Response:** `201 Created` `{ data: { pose: Pose } }` — `poseId` stable,
`status = local`, ba `MediaAsset` materialize ngay.

| ID | Rule |
|---|---|
| BR-ADMCOM-003 | Pose chỉ tạo khi job `succeeded`; job chưa thành công thì không tuyên bố ready. |
| BR-GUIDE-001 | `202` (job start) ≠ Pose tồn tại. |
| BR-ADMCOM-006 | Admin Web không định nghĩa extraction/pose/publication thứ hai. |
| BR-ADMCOM-007 | `ownerAccountId` bắt buộc cho pose admin-created. |

**Errors:** `400 JOB_NOT_SUCCEEDED`/`BAD_REQUEST`, `401`, `429`, `500`.

## Admin Jobs

Trạng thái async extraction job (FEAT-005, FEAT-007). Bearer admin. Không gắn
admin rate-limit — Admin Web phải poll được.

### GET /api/admin/jobs/:jobId

- Path `jobId` (UUID). OperationId `getAdminJob`.
- Response: `200`; `result` chỉ khi `status = succeeded`; `error` chỉ khi
  `status = failed`. Job `succeeded` ≠ catalogue public: phải **tạo `Pose`** sau
  đó (qua `POST /api/guides` / admin intake, `201`) và skeleton `MediaAsset`
  `ready` trước publish.

| ID | Rule |
|---|---|
| BR-JOB-004 | `result` và `error` mutually exclusive theo status. |
| BR-ADMJOB-001 | UI không đổi `202` submission thành complete/public khi poll. |
| BR-ADMJOB-002 | `succeeded` phải dẫn tới bước tạo `Pose` (`201`) và skeleton `ready` trước publish; poll job không tạo pose. |

**Errors:** `401 UNAUTHORIZED`, `404 JOB_NOT_FOUND`, `500`.