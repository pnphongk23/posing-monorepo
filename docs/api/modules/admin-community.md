# Module: Admin Community

Quản lý community poses từ admin. Tất cả routes yêu cầu `Authorization: Bearer <ADMIN_SECRET>`.

## GET /api/admin/community/poses

Lấy danh sách tất cả poses (cả `draft` và `published`), sort `uploadedAt DESC`.

**Authentication / Permission:** Bearer admin.

**Request:** Query `page` (default 1), `limit` (default 50, max 100). Xem operationId `listAdminCommunityPoses` trong [openapi.yaml](../openapi.yaml).

**Response:** `200` paginated list. Xem `listAdminCommunityPoses`.

**Business Rules:**

| ID | Rule |
|---|---|
| BR-ADMCOM-001 | Route load tất cả draft + published (limit 200 mỗi loại), ghép lại, sort theo `uploadedAt DESC`, rồi paginate in-memory. |

**Errors:** `401 UNAUTHORIZED`, `429 RATE_LIMITED`, `500`.

---

## POST /api/admin/community/poses/upload-url

Lấy presigned upload URL để upload ảnh thẳng lên R2.

**Authentication / Permission:** Bearer admin.

**Request:** JSON body. Xem operationId `createAdminCommunityUploadUrl` trong [openapi.yaml](../openapi.yaml).

- MIME phải là `image/png`, `image/jpeg`, hoặc `image/webp`.

**Response:** `200` `{ data: { uploadUrl, fileKey } }`.

**Business Rules:**

| ID | Rule |
|---|---|
| BR-ADMCOM-002 | Presigned URL expire và phải PUT trực tiếp lên R2, không qua server. Exact TTL là TBD (R2 config). |

**Errors:** `400 BAD_REQUEST`, `401`, `500`.

---

## POST /api/admin/community/poses

Submit pose mới: upload ảnh, enqueue extraction job, tạo community record.

**Authentication / Permission:** Bearer admin.

**Request:** `multipart/form-data`. Xem operationId `createAdminCommunityPose` trong [openapi.yaml](../openapi.yaml).

| Field | Required | Ghi chú |
|---|---|---|
| `image` | ✓ | PNG/JPEG/WEBP, tối đa 10 MB |
| `name` | ✓ | Non-empty string |
| `bodyParts` | ✓ | JSON array string hoặc comma-separated, ít nhất 1 item |
| `tags` | — | JSON array string hoặc comma-separated |
| `difficulty` | — | `beginner`/`intermediate`/`advanced` hoặc null |
| `description` | — | String hoặc null |
| `status` | — | `draft` (default) hoặc `published` |

**Response:** `202` `{ data: { pose: CommunityPose, jobId: string, status: "queued" } }`.

**Business Rules:**

| ID | Rule |
|---|---|
| BR-ADMCOM-003 | Route enqueue extraction job TRƯỚC khi tạo community record; nếu enqueue thất bại → `500 QUEUE_WRITE_FAILED`. |
| BR-ADMCOM-004 | `imagePath` được build từ `R2_PUBLIC_URL + generated fileKey`; không có upload R2 thực tế trong route này. |
| BR-ADMCOM-005 | `202` không có nghĩa là ảnh đã sẵn sàng; worker xử lý async. Không có FK giữa `pose.id` và `jobId` trong schema. |

**Errors:**

| Code | HTTP | Khi nào |
|---|---|---|
| `INVALID_IMAGE` | 400 | File thiếu, không đúng MIME, hoặc > 10 MB |
| `BAD_REQUEST` | 400 | Metadata không hợp lệ (name trống, bodyParts thiếu, v.v.) |
| `UNAUTHORIZED` | 401 | Bearer sai hoặc thiếu |
| `RATE_LIMITED` | 429 | Vượt admin rate limit |
| `QUEUE_WRITE_FAILED` | 500 | Enqueue job thất bại |
