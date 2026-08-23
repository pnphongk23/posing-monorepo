# Module: Pose Guides

Lifecycle [`Pose`](../../data/entities/pose.md). [FEAT-005](../../../harness/features/FEAT-005-manage-a-pose-guide.md). Extraction: [FEAT-004](../../../harness/features/FEAT-004-extract-reusable-pose-images.md). Publish: [modules/publish.md](publish.md).

Owner `Account` hoặc Admin operator.

## GET /api/guides

Danh sách pose của caller (My Poses). Admin có thể liệt kê theo owner.

**Authentication / Permission:** Signed-in Account hoặc Bearer admin.

**Request:** Query `page`, `limit`. OperationId `listGuides`.

**Response:** `200` paginated `Pose`.

---

## POST /api/guides

Tạo `Pose` `local` **sau khi extraction `succeeded`** (post-extraction), kèm luôn
thông tin metadata. Không nhận ảnh — ảnh đã nộp qua
[`POST /api/extract-pose`](extract-pose.md) (`202` + `jobId`) từ trước.

**Authentication / Permission:** Signed-in Account (owner = session account) hoặc
Bearer admin (phải kèm `ownerAccountId` tường minh — authenticated actor khác owner).

**Request:** `application/json` — operationId `createGuide`.

| Field | Required | Ghi chú |
|---|---|---|
| `jobId` | ✓ | `jobId` của `ExtractionJob` đã `succeeded` (correlation key; chưa có Pose trước đó) |
| `ownerAccountId` | admin | Bắt buộc khi gọi bằng Admin Bearer; bỏ qua với `AccountSession` (owner = session) |
| `name` | ✓ | Non-empty |
| `bodyParts` | ✓ | Ít nhất 1 item |
| `tags` | — | |
| `difficulty` | — | enum hoặc omit |
| `description` | — | |

**Response:** `201 Created` `{ data: { pose: Pose } }` — pose được tạo với `poseId`
stable, `status = local`, và **ba `MediaAsset` (`original`, `skeleton`, `thumbnail`)
materialize ngay** trong response dưới dạng `originalUrl` / `skeletonUrl` /
`thumbnailUrl`.

**Business Rules:**

| ID | Rule |
|---|---|
| BR-GUIDE-001 | `202` (job start) ≠ Pose tồn tại; pose chỉ được tạo sau khi job `succeeded` (`201`). |
| BR-GUIDE-002 | Không public cho đến khi skeleton `MediaAsset` `ready`. |
| BR-GUIDE-003 | `jobId` chưa `succeeded` thì từ chối tạo pose (`400 JOB_NOT_SUCCEEDED` / `404`). |

**Errors:** `400 JOB_NOT_SUCCEEDED` / `BAD_REQUEST`, `401`, `404`, `500`.

Admin intake `POST /api/admin/community/poses` dùng cùng hợp đồng (tạo cùng
`Pose`, không model thứ hai) — [admin-community.md](admin-community.md).

---

## GET /api/guides/:id

Đọc một pose (metadata, assets, current job). Không phải public catalogue.

**Authentication / Permission:** Owner hoặc Admin.

**Response:** `200` `{ data: Pose }`. OperationId `getGuide`.

**Errors:** `401`, `403 FORBIDDEN`, `404`.

---

## PATCH /api/guides/:id

Sửa metadata (`name`, `description`, `tags`, `difficulty`, `bodyParts`). Không đổi visibility.

**Authentication / Permission:** Owner hoặc Admin.

**Response:** `200` `{ data: Pose }`. OperationId `updateGuide`.

---

## POST /api/guides/:id/retry

Retry job `failed` còn trong chính sách retry, hoặc requeue job hiện tại theo BR-JOB-002.

**Authentication / Permission:** Owner hoặc Admin.

**Response:** `202` `ExtractionJobAccepted` `{ success, data: { jobId, status: "queued" }, meta: { pollUrl } }` —
job start, không tạo Pose mới. OperationId `retryGuideJob`.

---

## POST /api/guides/:id/re-extract

Tạo `ExtractionJob` mới từ source hiện hành. Không tạo pose mới.

**Authentication / Permission:** Owner hoặc Admin.

**Response:** `202` `ExtractionJobAccepted` (job start). OperationId `reExtractGuide`.

---

## POST /api/guides/:id/revert

Khôi phục skeleton `ready` trước đó. Không publish hộ.

**Authentication / Permission:** Owner hoặc Admin.

**Response:** `200` `{ data: Pose }`. OperationId `revertGuide`.

**Errors:** `409 CONFLICT` nếu không có skeleton trước để revert.

---

## DELETE /api/guides/:id

Xóa terminal. Gỡ khỏi catalogue nếu đang published; Saved không còn trình bày như public.

**Authentication / Permission:** Owner hoặc Admin.

**Response:** `204`. OperationId `deleteGuide`.

**Business Rules:** BR-GUIDE-005.
