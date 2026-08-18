# Module: Community (Public)

Catalogue published poses. [FEAT-003](../../../harness/features/FEAT-003-browse-and-search-published-poses.md). Không auth. Chỉ `status = published`.

Save / Try Pose: [FEAT-008](../../../harness/features/FEAT-008-use-published-poses.md). Publication: [FEAT-006](../../../harness/features/FEAT-006-publish-a-pose.md).

## GET /api/community/poses

Danh sách published, pagination, filter, tìm theo title.

**Authentication / Permission:** Không.

**Request:** Query — operationId `listCommunityPoses` trong [openapi.yaml](../openapi.yaml).

- `page` (default 1), `limit` (max 100, default 20)
- `difficulty`: `beginner` \| `intermediate` \| `advanced`
- `tag`: khớp tag
- `q`: tìm theo `name` (title), case-insensitive substring trên published records

**Response:** `200` `{ data: CommunityPose[], pagination }`.

**Business Rules:**

| ID | Rule |
|---|---|
| BR-COMMUNITY-001 | Chỉ `published`. |
| BR-COMMUNITY-005 | `q` không trả draft. |
| BR-COMMUNITY-006 | Kết quả không trùng `id` đang active trên một trang response. |

**Errors:** `400 BAD_REQUEST`, `500 INTERNAL_SERVER_ERROR`.

Failure catalogue: client giữ kết quả đã xác nhận và cho retry; không hiện nội dung chưa xác nhận như published.

---

## GET /api/community/poses/:id

Chi tiết một published pose. Tăng `downloadCount`.

**Authentication / Permission:** Không.

**Request:** Path `id` (UUID). OperationId `getCommunityPose`.

**Response:** `200` `{ data: CommunityPose }`.

**Business Rules:**

| ID | Rule |
|---|---|
| BR-COMMUNITY-002 | `downloadCount` +1 khi thành công. |
| BR-COMMUNITY-007 | Tồn tại nhưng không `published` → `404` (không leak draft). |
| BR-COMMUNITY-004 | `imagePath` là locator render `ready`. |

**Errors:** `404 NOT_FOUND`, `500 INTERNAL_SERVER_ERROR`.
