# Module: Pose Guides

Lifecycle [`PoseGuide`](../../data/entities/pose-guide.md). [FEAT-005](../../../harness/features/FEAT-005-manage-a-pose-guide.md). Extraction: [FEAT-004](../../../harness/features/FEAT-004-extract-reusable-pose-images.md). Publish: [modules/publish.md](publish.md).

Owner `Account` hoặc Admin operator.

## GET /api/guides

Danh sách guide của caller (My Poses). Admin có thể liệt kê theo owner.

**Authentication / Permission:** Signed-in Account hoặc Bearer admin.

**Request:** Query `page`, `limit`. OperationId `listGuides`.

**Response:** `200` paginated `PoseGuide`.

---

## POST /api/guides

Tạo guide `draft`, gắn source asset, enqueue `ExtractionJob`.

**Authentication / Permission:** Signed-in Account hoặc Bearer admin.

**Request:** `multipart/form-data` — operationId `createGuide`.

| Field | Required | Ghi chú |
|---|---|---|
| `image` | ✓ | PNG/JPEG/WEBP, tối đa 10 MB |
| `name` | ✓ | Non-empty |
| `bodyParts` | ✓ | Ít nhất 1 item |
| `tags` | — | |
| `difficulty` | — | enum hoặc omit |
| `description` | — | |

**Response:** `202` `{ data: { guide: PoseGuide, jobId, status: "queued" } }`.

**Business Rules:**

| ID | Rule |
|---|---|
| BR-GUIDE-001 | `202` = queued, không phải ready/public. |
| BR-GUIDE-002 | Không public cho đến khi render `MediaAsset` `ready`. |

**Errors:** `400 INVALID_IMAGE` / `BAD_REQUEST`, `401`, `413`, `500 QUEUE_WRITE_FAILED`.

Admin intake `POST /api/admin/community/poses` phải tạo cùng `PoseGuide` (không model thứ hai) — [admin-community.md](admin-community.md).

---

## GET /api/guides/:id

Đọc một guide (metadata, assets, current job). Không phải public catalogue.

**Authentication / Permission:** Owner hoặc Admin.

**Response:** `200` `{ data: PoseGuide }`. OperationId `getGuide`.

**Errors:** `401`, `403 FORBIDDEN`, `404`.

---

## PATCH /api/guides/:id

Sửa metadata (`name`, `description`, `tags`, `difficulty`, `bodyParts`). Không đổi visibility.

**Authentication / Permission:** Owner hoặc Admin.

**Response:** `200` `{ data: PoseGuide }`. OperationId `updateGuide`.

---

## POST /api/guides/:id/retry

Retry job `failed` còn trong chính sách retry, hoặc requeue job hiện tại theo BR-JOB-002.

**Authentication / Permission:** Owner hoặc Admin.

**Response:** `202` `{ data: { guide, jobId, status: "queued" } }`. OperationId `retryGuideJob`.

---

## POST /api/guides/:id/re-extract

Tạo `ExtractionJob` mới từ source hiện hành. Không tạo guide mới.

**Authentication / Permission:** Owner hoặc Admin.

**Response:** `202`. OperationId `reExtractGuide`.

---

## POST /api/guides/:id/revert

Khôi phục render `ready` trước đó. Không publish hộ.

**Authentication / Permission:** Owner hoặc Admin.

**Response:** `200` `{ data: PoseGuide }`. OperationId `revertGuide`.

**Errors:** `409 CONFLICT` nếu không có render trước để revert.

---

## DELETE /api/guides/:id

Xóa terminal. Gỡ khỏi catalogue nếu đang published; Saved không còn trình bày như public.

**Authentication / Permission:** Owner hoặc Admin.

**Response:** `204`. OperationId `deleteGuide`.

**Business Rules:** BR-GUIDE-005.
