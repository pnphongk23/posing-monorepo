# Module: Community (Public)

Routes public, không yêu cầu auth. Chỉ trả về poses có `status = published`.

## GET /api/community/poses

Lấy danh sách published poses với pagination và filtering.

**Authentication / Permission:** Không yêu cầu.

**Request:** Query params tùy chọn — xem operationId `listCommunityPoses` trong [openapi.yaml](../openapi.yaml).

- `page` (default 1), `limit` (max 100, default 20)
- `difficulty`: `beginner` | `intermediate` | `advanced`
- `tag`: string (exact match trên JSON tags array)

**Response:** `200` paginated list. Xem `listCommunityPoses`.

**Business Rules:**

| ID | Rule |
|---|---|
| BR-COMMUNITY-001 | Chỉ trả về `status = published`. |
| BR-COMMUNITY-006 | Filter `tag` dùng `LIKE %"tag"%` trên JSON string — phân biệt hoa thường. |

**Errors:** `400 BAD_REQUEST` (invalid query params), `500 INTERNAL_SERVER_ERROR`.

---

## GET /api/community/poses/:id

Lấy chi tiết một published pose. Tăng `downloadCount`.

**Authentication / Permission:** Không yêu cầu.

**Request:** Path param `id` (UUID string). Xem operationId `getCommunityPose` trong [openapi.yaml](../openapi.yaml).

**Response:** `200` `{ data: CommunityPose }`. Xem `getCommunityPose`.

**Business Rules:**

| ID | Rule |
|---|---|
| BR-COMMUNITY-002 | `downloadCount` tăng 1 mỗi lần request thành công. |
| BR-COMMUNITY-007 | Nếu pose tồn tại nhưng `status != published`, trả `404` (không leak draft). |

**Errors:** `404 NOT_FOUND`, `500 INTERNAL_SERVER_ERROR`.
