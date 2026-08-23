# Module: Admin Jobs

Trạng thái async extraction job. [FEAT-005](../../../harness/features/FEAT-005-manage-a-pose-guide.md), [FEAT-007](../../../harness/features/FEAT-007-operate-pose-content-from-admin-web.md).

Bearer admin. Không gắn admin rate-limit — Admin Web phải poll được.

## GET /api/admin/jobs/:jobId

**Authentication / Permission:** Bearer admin.

**Request:** Path `jobId` (UUID). OperationId `getAdminJob`.

**Response:** `200`. `result` chỉ khi `status = succeeded`; `error` chỉ khi `status = failed`.

Khi `succeeded`, Pose vẫn chưa tồn tại/quy đổi: phải **tạo [`Pose`](../../data/entities/pose.md)
sau đó** (qua `POST /api/guides` / admin intake, `201`) và có skeleton
[`MediaAsset`](../../data/entities/media-asset.md) `ready` trước khi publish.
Job `succeeded` ≠ catalogue public.

**Business Rules:**

| ID | Rule |
|---|---|
| BR-JOB-004 | `result` và `error` mutually exclusive theo status. |
| BR-JOB-001 | Phân biệt `queued`, `processing`, `succeeded`, `failed`. |
| BR-ADMJOB-001 | UI không đổi `202` submission thành complete/public khi poll. |
| BR-ADMJOB-002 | `succeeded` phải dẫn tới bước tạo `Pose` (`201`) và skeleton `ready` trước publish; poll job không tạo pose. |

**Errors:** `401 UNAUTHORIZED`, `404 JOB_NOT_FOUND`, `500`.
