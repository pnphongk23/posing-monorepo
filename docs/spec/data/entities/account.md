# Account

## Description

Identity của người dùng đã đăng nhập. Dùng cho quyền sở hữu [`PoseGuide`](pose-guide.md) ([FEAT-005](../../../harness/features/FEAT-005-manage-a-pose-guide.md), [FEAT-006](../../../harness/features/FEAT-006-publish-a-pose.md)) và collection [`SavedEntry`](saved-entry.md) ([FEAT-008](../../../harness/features/FEAT-008-use-published-poses.md)).

Admin operator ([FEAT-007](../../../harness/features/FEAT-007-operate-pose-content-from-admin-web.md)) không phải `Account`; Admin dùng Bearer admin secret.

Visitor chưa đăng nhập được duyệt catalogue ([FEAT-003](../../../harness/features/FEAT-003-browse-and-search-published-poses.md)) nhưng không Save và không sở hữu guide.

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | TEXT (UUID) | PK | Định danh account |
| `displayName` | TEXT | ✓ | Tên hiển thị |
| `createdAt` | DATETIME | ✓ | Thời điểm tạo |

Cơ chế session/credential (email, OAuth, v.v.) nằm ngoài catalogue entity này; API chỉ yêu cầu “signed-in `Account`”. Xem [conventions](../../api/conventions.md).

## Relationships

- Một `Account` 1 — 0..* `PoseGuide` (owner)
- Một `Account` 1 — 0..* `SavedEntry`

## Business Rules

| ID | Rule |
|---|---|
| BR-ACCOUNT-001 | Chỉ signed-in `Account` được Save / Unsave và sở hữu guide. |
| BR-ACCOUNT-002 | Dùng published pose ([FEAT-008](../../../harness/features/FEAT-008-use-published-poses.md)) không cấp quyền owner hay publish. |
| BR-ACCOUNT-003 | Publish / unpublish đòi hỏi owner `Account` của guide, hoặc Admin operator. |
| BR-ACCOUNT-004 | Visitor chọn hành động cần account thì hệ thống yêu cầu đăng nhập; không xác nhận Saved khi chưa có `Account`. |
