# Module: Admin Jobs

Trạng thái async extraction job. [FEAT-005](../../../harness/features/FEAT-005-manage-a-pose-guide.md), [FEAT-007](../../../harness/features/FEAT-007-operate-pose-content-from-admin-web.md).

Bearer admin. Không gắn admin rate-limit — Admin Web phải poll được.

## GET /api/admin/jobs/:jobId

**Authentication / Permission:** Bearer admin.

**Request:** Path `jobId` (UUID). OperationId `getAdminJob`.

**Response:** `200`. `result` chỉ khi `status = succeeded`; `error` chỉ khi `status = failed`.

Khi `succeeded`, Admin/owner vẫn phải có render [`MediaAsset`](../../data/entities/media-asset.md) `ready` trước khi publish. Job `succeeded` ≠ catalogue public.

**Business Rules:**

| ID | Rule |
|---|---|
| BR-JOB-004 | `result` và `error` mutually exclusive theo status. |
| BR-JOB-001 | Phân biệt `queued`, `processing`, `succeeded`, `failed`. |
| BR-ADMJOB-001 | UI không đổi `202` submission thành complete/public khi poll. |

**Errors:** `401 UNAUTHORIZED`, `404 JOB_NOT_FOUND`, `500`.
