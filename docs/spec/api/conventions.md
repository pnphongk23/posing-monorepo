# API Conventions

Quy ước product cho `pose-extract-server`. Chi tiết schema: [`openapi.yaml`](openapi.yaml).

## URL naming

- Mọi business route mount `/api/...`. Không có prefix `/v1/`.
- Public catalogue: `/api/community/poses`
- Pose (`PoseGuide` cũ — model hợp nhất thành `Pose`): `/api/guides`
- Signed-in collection: `/api/me/saved`
- Admin: `/api/admin/keys`, `/api/admin/community/poses`, `/api/admin/jobs`
- Health: `/api/health`
- Direct extract: `/api/extract-pose`

## HTTP methods và status codes

| Trường hợp | Method | Status |
|---|---|---|
| Đọc | GET | 200 |
| **Job start** (enqueue extraction, retry, re-extract) | POST | **202** |
| **Pose creation/completion** (post-extraction: `POST /api/guides`, admin intake) | POST | **201** |
| Cập nhật partial | PATCH | 200 |
| Publish / unpublish / revert (đổi trạng thái, không tạo pose) | POST | 200 |
| Xóa | DELETE | 204 (empty body) |
| Upsert saved | PUT | 200 |
| Reset counters | POST | 200 |

`202` = đã nhận job, chưa complete, chưa public, **chưa có `Pose`**. `201` = `Pose`
được tạo với `poseId` stable và ba media role (`original`, `skeleton`, `thumbnail`)
materialize ngay — pose chỉ tồn tại sau khi extraction `succeeded`.

## Authentication

| Actor | Cơ chế | Routes |
|---|---|---|
| Visitor | Không auth | `GET /api/community/poses`, `GET /api/community/poses/:id`, `POST /api/extract-pose`, `GET /api/health` |
| Signed-in `Account` | Session của Account (cơ chế cụ thể ngoài catalogue này) | `/api/me/saved`, `/api/guides` (owner) |
| Admin operator | `Authorization: Bearer <ADMIN_SECRET>` | `/api/admin/*`; Admin cũng được gọi `/api/guides` và publish như operator |

**authenticated actor vs owner:** `ownerAccountId` là **bắt buộc** (non-nullable)
trên mọi `Pose`. Với `AccountSession` (mobile/local), owner = session account và
không gửi trong body. Với Admin `Bearer` (không có session account), request tạo
pose phải kèm `ownerAccountId` tường minh — authenticated actor (Admin operator)
khác owner (`Account` được chỉ định).

Secret admin không bao giờ gửi từ browser. Next.js Admin Web inject Bearer phía server — xem mục proxy.

Visitor chọn Save thì client yêu cầu đăng nhập; không xác nhận Saved khi chưa có Account.

## Rate limiting

- `POST /api/extract-pose`: giới hạn theo IP.
- `/api/admin/keys` và `/api/admin/community/*`: giới hạn admin.
- `GET /api/admin/jobs/:jobId` có Bearer, không gắn admin rate-limit (cần poll).

Không có rate-limit header bắt buộc trên response.

## Pagination

```json
{
  "data": [ ... ],
  "pagination": { "page": 1, "limit": 20, "total": 42 }
}
```

- `page`: số nguyên dương, default `1`
- `limit`: số nguyên dương, max `100` (default 20 public, 50 admin)
- `total`: tổng record thỏa filter

## Filtering và search

`GET /api/community/poses`:

- `difficulty`: enum `PoseDifficulty`
- `tag`: khớp tag
- `q`: tìm theo title trên published records ([FEAT-003](../../harness/features/FEAT-003-browse-and-search-published-poses.md))

Không trả pose `local` (legacy `draft`) trên public search/list.

## Error envelope

```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Mô tả human-readable"
  }
}
```

Lỗi chung: `401 UNAUTHORIZED`, `403 FORBIDDEN`, `404 NOT_FOUND`, `409 CONFLICT` (eligibility), `500 INTERNAL_SERVER_ERROR`.

## Datetime

ISO 8601 strings.

## Next.js proxy (không phải contract riêng)

Admin UI forward sang `pose-extract-server`. Contract chỉ nằm ở Express.

| Next.js path | Upstream |
|---|---|
| `POST /api/admin/extract-pose` | `POST /api/extract-pose` |
| `GET, POST /api/admin/community/poses` | `/api/admin/community/poses` |
| `GET, POST /api/admin/keys` | `/api/admin/keys` |
| `PATCH, DELETE /api/admin/keys/:id` | `/api/admin/keys/:id` |
| `POST /api/admin/keys/reset` | `/api/admin/keys/reset` |
| Job poll | `GET /api/admin/jobs/:jobId` |

Admin Web ([FEAT-007](../../harness/features/FEAT-007-operate-pose-content-from-admin-web.md)) phải poll job và không đổi `202` thành “xong/public”.

## Legacy route

`POST /api/extract` trên Next.js (Replicate) không thuộc contract này. Direct extract canonical là `POST /api/extract-pose` ([FEAT-004](../../harness/features/FEAT-004-extract-reusable-pose-images.md)).
