# Module: Saved

Collection cá nhân của signed-in [`Account`](../../data/entities/account.md). [FEAT-008](../../../harness/features/FEAT-008-use-published-poses.md).

Try Pose không có HTTP — client tải skeleton published, verify, rồi cầm [`PreparedPoseReference`](../../data/entities/prepared-pose-reference.md). Use không cấp ownership.

## GET /api/me/saved

Danh sách pose đang lưu. Chỉ những pose vẫn `published` được trả như mục công khai còn hiệu lực.

**Authentication / Permission:** Signed-in Account.

**Request:** Query `page`, `limit`. OperationId `listSavedPoses`.

**Response:** `200` paginated DTO public (`CommunityPose`) — **view projection read-only**
(đọc kết quả) của các [`Pose`](../../data/entities/pose.md) `published` được lưu
(cùng `poseId`); không phải entity riêng, không bao gồm pose `local`.

**Errors:** `401 UNAUTHORIZED`.

---

## PUT /api/me/saved/:poseId

Lưu một published pose. Idempotent nếu đã lưu.

**Authentication / Permission:** Signed-in Account.

**Request:** Path `poseId` (UUID `Pose`). OperationId `savePose`.

**Response:** `200` `{ data: SavedEntry }`.

**Business Rules:**

| ID | Rule |
|---|---|
| BR-SAVED-001 | Chỉ pose `published`. `local` (legacy `draft`) → `404` hoặc `409` (không leak). |
| BR-SAVED-002 | Unique (`accountId`, `poseId`); PUT lần hai không tạo bản sao. |
| BR-SAVED-005 | Không cấp quyền owner/publish. |

**Errors:** `401`, `404 NOT_FOUND`.

Visitor gọi Save: client chuyển đăng nhập; API trả `401`, không tạo entry.

---

## DELETE /api/me/saved/:poseId

Unsave. Không đụng pose.

**Authentication / Permission:** Signed-in Account.

**Response:** `204`. OperationId `unsavePose`. Idempotent nếu chưa lưu.

**Errors:** `401`.
