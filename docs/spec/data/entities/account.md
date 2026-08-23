# Account

## Description

Identity của người dùng đã đăng nhập. Dùng cho quyền sở hữu [`Pose`](pose.md) ([FEAT-005](../../../harness/features/FEAT-005-manage-a-pose-guide.md), [FEAT-006](../../../harness/features/FEAT-006-publish-a-pose.md)) và collection [`SavedEntry`](saved-entry.md) ([FEAT-008](../../../harness/features/FEAT-008-use-published-poses.md)).

Admin operator ([FEAT-007](../../../harness/features/FEAT-007-operate-pose-content-from-admin-web.md)) không phải `Account`; Admin dùng Bearer admin secret.
Tuy vậy, mọi [`Pose`](pose.md) — kể cả pose do Admin tạo — vẫn có
`ownerAccountId` **bắt buộc**: với pose admin, request phải chỉ định
`ownerAccountId` của `Account` sở hữu một cách tường minh (authenticated actor =
Admin operator, owner = `Account` được chỉ định).

Visitor chưa đăng nhập được duyệt catalogue ([FEAT-003](../../../harness/features/FEAT-003-browse-and-search-published-poses.md)) nhưng không Save và không sở hữu pose.

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | TEXT (UUID) | PK | Định danh account |
| `displayName` | TEXT | ✓ | Tên hiển thị |
| `createdAt` | DATETIME | ✓ | Thời điểm tạo |

Cơ chế session/credential (email, OAuth, v.v.) nằm ngoài catalogue entity này; API chỉ yêu cầu “signed-in `Account`”. Xem [conventions](../../api/conventions.md).

## Relationships

- Một `Account` 1 — 0..* `Pose` (owner)
- Một `Account` 1 — 0..* `SavedEntry`

## Business Rules

| ID | Rule |
|---|---|
| BR-ACCOUNT-001 | Chỉ signed-in `Account` được Save / Unsave và sở hữu pose. |
| BR-ACCOUNT-002 | Dùng published pose ([FEAT-008](../../../harness/features/FEAT-008-use-published-poses.md)) không cấp quyền owner hay publish. |
| BR-ACCOUNT-003 | Publish / unpublish đòi hỏi owner `Account` của pose, hoặc Admin operator. |
| BR-ACCOUNT-004 | Visitor chọn hành động cần account thì hệ thống yêu cầu đăng nhập; không xác nhận Saved khi chưa có `Account`. |
| BR-ACCOUNT-005 | `ownerAccountId` bắt buộc (non-nullable) trên mọi `Pose`; pose do Admin tạo phải kèm `ownerAccountId` tường minh trong request — xem [API conventions](../../api/conventions.md). |
