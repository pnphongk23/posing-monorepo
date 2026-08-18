# Module: Admin Community

Intake và listing community từ Admin Web. [FEAT-007](../../../harness/features/FEAT-007-operate-pose-content-from-admin-web.md) gọi [FEAT-005](../../../harness/features/FEAT-005-manage-a-pose-guide.md); không tạo model guide/publication riêng.

Tất cả routes: `Authorization: Bearer <ADMIN_SECRET>`.

## GET /api/admin/community/poses

Danh sách mọi guide/pose (`draft` và `published`), mới nhất trước.

**Authentication / Permission:** Bearer admin.

**Request:** `page`, `limit` (default 50, max 100). OperationId `listAdminCommunityPoses`.

**Response:** `200` paginated. Admin thấy đủ metadata vận hành; public catalogue không dùng route này.

**Errors:** `401 UNAUTHORIZED`, `429 RATE_LIMITED`, `500`.

---

## POST /api/admin/community/poses/upload-url

Presigned URL để PUT ảnh lên object storage.

**Authentication / Permission:** Bearer admin.

**Request:** JSON. OperationId `createAdminCommunityUploadUrl`. MIME: `image/png`, `image/jpeg`, `image/webp`.

**Response:** `200` `{ data: { uploadUrl, fileKey } }`.

**Errors:** `400 BAD_REQUEST`, `401`, `500`.

---

## POST /api/admin/community/poses

Submit pose: tạo [`PoseGuide`](../../data/entities/pose-guide.md) `draft`, enqueue [`ExtractionJob`](../../data/entities/extraction-job.md). Cùng hợp đồng với `POST /api/guides` (admin acting as operator).

**Authentication / Permission:** Bearer admin.

**Request:** `multipart/form-data`. OperationId `createAdminCommunityPose`.

| Field | Required | Ghi chú |
|---|---|---|
| `image` | ✓ | PNG/JPEG/WEBP, tối đa 10 MB |
| `name` | ✓ | Non-empty |
| `bodyParts` | ✓ | Ít nhất 1 item |
| `tags` | — | |
| `difficulty` | — | |
| `description` | — | |

Không nhận `status = published` trên intake. Publish là [publish.md](publish.md) sau khi render `ready`.

**Response:** `202` `{ data: { pose: CommunityPose \| PoseGuide, jobId, status: "queued" } }`.

**Business Rules:**

| ID | Rule |
|---|---|
| BR-ADMCOM-003 | Enqueue job và tạo guide phải cùng một đơn vị chấp nhận; một phía fail thì không tuyên bố ready. |
| BR-GUIDE-001 | `202` queued, không complete, không public. |
| BR-ADMCOM-006 | Admin Web không định nghĩa extraction/guide/publication thứ hai. |

**Errors:** `400 INVALID_IMAGE` / `BAD_REQUEST`, `401`, `429`, `500 QUEUE_WRITE_FAILED`.
