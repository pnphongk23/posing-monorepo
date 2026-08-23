# Module: Publish

Chuyển visibility của [`Pose`](../../data/entities/pose.md). [FEAT-006](../../../harness/features/FEAT-006-publish-a-pose.md). Catalogue đọc kết quả qua [community.md](community.md).

Không định nghĩa extraction hay guide mới. Admin Web gọi cùng endpoints ([FEAT-007](../../../harness/features/FEAT-007-operate-pose-content-from-admin-web.md)).

## POST /api/guides/:id/publish

Đưa pose ra public catalogue khi đủ điều kiện. Pose đã tồn tại (tạo sau khi
extraction `succeeded`); publish chỉ đổi `status`, `poseId` giữ nguyên.

**Authentication / Permission:** Owner `Account` hoặc Bearer admin.

**Request:** Path `id`. Body rỗng. OperationId `publishGuide`.

**Response:** `200` `{ data: Pose }` với `status = published`. Public `GET /api/community/poses/:id` bắt đầu trả record.

**Business Rules:**

| ID | Rule |
|---|---|
| BR-PUBLISH-001 | Chỉ publish khi skeleton `MediaAsset` `ready` và locator đọc được. |
| BR-PUBLISH-002 | Thiếu thẩm quyền thì giữ visibility cũ; không tuyên bố đã publish. |
| BR-PUBLISH-003 | `published` trên catalogue đồng nghĩa đã qua cổng readiness — không publish từ `202` queued. |

**Errors:** `401`, `403 FORBIDDEN`, `404`, `409 CONFLICT` (`ASSET_NOT_READY` khi skeleton chưa ready).

---

## POST /api/guides/:id/unpublish

Gỡ khỏi public discovery. Pose về `local` (legacy alias `draft`) cho owner/Admin.

**Authentication / Permission:** Owner hoặc Admin.

**Response:** `200` `{ data: Pose }` với `status = local`. Public list/detail ngừng trả id này (`404` nếu gọi detail).

**Business Rules:**

| ID | Rule |
|---|---|
| BR-PUBLISH-004 | Unpublish không xóa pose. |
| BR-SAVED-004 | Saved collection không trình bày pose đã unpublish như nội dung công khai còn hiệu lực. |

**Errors:** `401`, `403`, `404`.
