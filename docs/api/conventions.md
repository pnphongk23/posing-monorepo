# API Conventions

Quy ước thực sự áp dụng trong `pose-extract-server` — được verify từ source code.

## URL naming

- Tất cả routes mount trực tiếp trên `/api/...` — không có prefix `/v1/`.
- Public community: `/api/community/poses`
- Admin: `/api/admin/keys`, `/api/admin/community/poses`, `/api/admin/jobs`
- Health: `/api/health`
- Static assets (local dev): `/community/*`

## HTTP methods và status codes

| Trường hợp | Method | Status |
|---|---|---|
| Đọc danh sách | GET | 200 |
| Tạo resource | POST | 201 |
| Tạo async (job) | POST | 202 |
| Cập nhật partial | PATCH | 200 |
| Xóa | DELETE | 204 (empty body) |
| Reset counters | POST | 200 |
| CORS preflight | OPTIONS | 204 |

## Authentication

- Admin routes (`/api/admin/*`): `Authorization: Bearer <ADMIN_SECRET>` trong header.
- Public routes (`GET /api/community/poses`, `GET /api/community/poses/:id`, `POST /api/extract-pose`): không cần auth.
- Next.js admin UI proxy inject Bearer header phía server — browser không gửi secret trực tiếp.

## Rate limiting

- `POST /api/extract-pose`: process-local IP limiter, default 10 requests/60s (`RATE_LIMIT_MAX`, `RATE_LIMIT_WINDOW_MS`).
- Admin keys và admin community: process-local 30 requests/60s. Biến môi trường cho admin limiter không được expose trong `env.ts` — TBD.
- `GET /api/admin/jobs/:jobId` có Bearer auth, **không** gắn admin rate-limit middleware.
- Không có rate limit header trả về client.

## Pagination

Responses trả danh sách theo format:

```json
{
  "data": [ ... ],
  "pagination": { "page": 1, "limit": 20, "total": 42 }
}
```

- `page`: số nguyên dương, default `1`
- `limit`: số nguyên dương, max `100`, default thay đổi theo route (20 public, 50 admin)
- `total`: tổng số records thỏa filter

Không có cursor token hay `X-Total-Count` header.

## Filtering

- `GET /api/community/poses` hỗ trợ: `difficulty` (enum), `tag` (free-form string exact match).
- Không có full-text search hay server-side title search implemented.

## Error envelope

Tất cả lỗi đều theo shape:

```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Mô tả human-readable"
  }
}
```

Lỗi chung từ server middleware:
- `404 NOT_FOUND` — route không tồn tại
- `500 INTERNAL_SERVER_ERROR` — lỗi không xử lý được

Chi tiết error codes per route: xem `openapi.yaml` và module files.

## Datetime

Tất cả datetime fields trả về dạng ISO 8601 string từ SQLite `DATETIME`.

## Next.js proxy routes (không phải API contract riêng)

Admin UI (Next.js) expose các proxy routes sau, forward sang `pose-extract-server`:

| Next.js path | Upstream |
|---|---|
| `POST /api/admin/extract-pose` | Proxy → `POST /api/extract-pose` |
| `GET, POST /api/admin/community/poses` | Proxy → `/api/admin/community/poses` (Bearer inject server-side) |
| `GET, POST /api/admin/keys` | Proxy → `/api/admin/keys` (Bearer inject) |
| `PATCH, DELETE /api/admin/keys/:id` | Proxy → `/api/admin/keys/:id` (Bearer inject) |
| `POST /api/admin/keys/reset` | Proxy → `/api/admin/keys/reset` (Bearer inject) |

Các proxy routes này **không phải API contract riêng** — contract nằm hoàn toàn ở `pose-extract-server`.

## Legacy route (không thuộc openapi.yaml)

`POST /api/extract` trong Next.js admin UI là **legacy/alternate extraction path** dùng Replicate ControlNet.  
Đây không phải là contract của `pose-extract-server` và không được document trong `openapi.yaml`.  
Chưa có Decision nào chọn path extraction nào là canonical.
