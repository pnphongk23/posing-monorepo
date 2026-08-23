# Module: Admin Community

Intake và listing community từ Admin Web. [FEAT-007](../../../harness/features/FEAT-007-operate-pose-content-from-admin-web.md) gọi [FEAT-005](../../../harness/features/FEAT-005-manage-a-pose-guide.md); không tạo model pose/publication riêng.

Tất cả routes: `Authorization: Bearer <ADMIN_SECRET>`.

## GET /api/admin/community/poses

Danh sách mọi [`Pose`](../../data/entities/pose.md) (`local` — legacy alias `draft` — và `published`), mới nhất trước. Trả canonical `Pose` (PoseResponse), không phải `CommunityPose` DTO — đây là endpoint admin/local, không phải public catalogue. `ownerAccountId` xuất hiện trên mỗi pose.

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

Tạo [`Pose`](../../data/entities/pose.md) `local` **sau khi extraction `succeeded`**
(post-extraction) — cùng hợp đồng hai pha với `POST /api/guides` (admin acting as operator).
Ảnh được nộp trước qua `POST /api/extract-pose` (`202` + `jobId`); route này không nhận ảnh.

**Authentication / Permission:** Bearer admin.

**Request:** `application/json`. OperationId `createAdminCommunityPose`.

| Field | Required | Ghi chú |
|---|---|---|
| `jobId` | ✓ | `jobId` của `ExtractionJob` đã `succeeded` (correlation key; chưa có Pose trước đó) |
| `ownerAccountId` | ✓ | **Bắt buộc** — Admin dùng Bearer (không có session account), nên owning `Account` phải chỉ định tường minh |
| `name` | ✓ | Non-empty |
| `bodyParts` | ✓ | Ít nhất 1 item |
| `tags` | — | |
| `difficulty` | — | |
| `description` | — | |

Không nhận `status = published` trên intake. Publish là [publish.md](publish.md) sau khi skeleton `ready`.

**Response:** `201 Created` `{ data: { pose: Pose } }` — pose tạo với `poseId`
stable, `status = local`, ba `MediaAsset` (`original`, `skeleton`, `thumbnail`)
materialize ngay (`originalUrl` / `skeletonUrl` / `thumbnailUrl`).

**Business Rules:**

| ID | Rule |
|---|---|
| BR-ADMCOM-003 | Pose chỉ được tạo khi job `succeeded`; job chưa thành công thì không tuyên bố ready. |
| BR-GUIDE-001 | `202` (job start) ≠ Pose tồn tại; pose tạo sau `succeeded` (`201`). |
| BR-ADMCOM-006 | Admin Web không định nghĩa extraction/pose/publication thứ hai. |
| BR-ADMCOM-007 | `ownerAccountId` bắt buộc cho pose admin-created (authenticated actor = Admin operator, owner = `Account` chỉ định). |

**Errors:** `400 JOB_NOT_SUCCEEDED` / `BAD_REQUEST`, `401`, `429`, `500`.
