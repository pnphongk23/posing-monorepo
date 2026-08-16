# Module: Admin Jobs

Xem trạng thái async extraction job. Yêu cầu `Authorization: Bearer <ADMIN_SECRET>`.

## GET /api/admin/jobs/:jobId

Lấy trạng thái và kết quả của một extraction job.

**Authentication / Permission:** Bearer admin. **Không có rate limit middleware** (khác admin-keys và admin-community).

**Request:** Path param `jobId` (UUID). Xem operationId `getAdminJob` trong [openapi.yaml](../openapi.yaml).

**Response:** `200`. Schema: operationId `getAdminJob` trong [openapi.yaml](../openapi.yaml).

- `result` chỉ có giá trị khi `status = succeeded`
- `error` chỉ có giá trị khi `status = failed`

**Business Rules:**

| ID | Rule |
|---|---|
| BR-JOB-004 | `result` và `error` là mutually exclusive và đều nullable tùy theo status. |

**Errors:** `401 UNAUTHORIZED`, `404 JOB_NOT_FOUND`, `500 INTERNAL_SERVER_ERROR`.
