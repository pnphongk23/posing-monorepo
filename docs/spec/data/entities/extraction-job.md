# ExtractionJob

## Description

Job theo dõi một lần extraction ảnh pose ([FEAT-004](../../../harness/features/FEAT-004-extract-reusable-pose-images.md)).
`id` của job chính là **`jobId`** — correlation key dùng trong lúc extraction:
submit enqueue job và trả `202` + `jobId` mà **chưa có [`Pose`](pose.md)**.
Khi job `succeeded`, hệ thống tạo `Pose` (stable `poseId`), materialize ba
`MediaAsset`, và back-fill `poseId` của job (nullable tới lúc đó).

Khi gắn với [`Pose`](pose.md), job thuộc lifecycle pose
([FEAT-005](../../../harness/features/FEAT-005-manage-a-pose-guide.md)).
`POST /api/extract-pose` trả **async `202 Accepted` + `jobId`** cho caller
(persistence thuộc caller/pose, không phải job này); **sau khi job `succeeded`
mới tạo `Pose` (`201 Created`)** — job chưa succeed không tạo pose.

Admin và owner theo dõi job qua [FEAT-007](../../../harness/features/FEAT-007-operate-pose-content-from-admin-web.md)
/ FEAT-005. `202` queued không phải completion.

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | TEXT (UUID) | PK | `jobId` — server-generated UUID; correlation key khi pose chưa tồn tại |
| `poseId` | TEXT (UUID) | — | [`Pose`](pose.md) khi job thuộc pose flow; **NULL cho tới khi extraction `succeeded` và `Pose` được tạo**; null với extract đồng bộ không persist |
| `status` | TEXT | ✓ | Enum `ExtractionJobStatus` |
| `sourceMediaId` | TEXT (UUID) | — | [`MediaAsset`](media-asset.md) original khi có pose |
| `skeletonMediaId` | TEXT (UUID) | — | [`MediaAsset`](media-asset.md) skeleton khi `succeeded` |
| `errorCode` | TEXT | — | Khi `failed` |
| `errorMessage` | TEXT | — | Khi `failed` |
| `attempts` | INTEGER | ✓ (default `0`) | Số lần đã thử |
| `maxAttempts` | INTEGER | ✓ (default `3`) | Trần retry |
| `createdAt` | DATETIME | ✓ | Enqueue |
| `updatedAt` | DATETIME | ✓ | Cập nhật cuối |

Payload nguồn/kết quả tạm thời có thể sống trên job trong lúc `processing`; khi
`succeeded`, kết quả bền phải là `MediaAsset` skeleton `ready` gắn pose — không
lấy base64 job làm catalogue. `Pose` được tạo mới **sau** `succeeded`, không phải
lúc enqueue (`202` ≠ pose tồn tại).

## Relationships

- Nhiều `ExtractionJob` → một `Pose` (`poseId`, nullable tới khi pose tạo)
- Job `succeeded` → hệ thống tạo `Pose` và materialize ba `MediaAsset` (`original`,
  `skeleton`, `thumbnail`); job cập nhật `skeletonMediaId` và `Pose.skeletonMediaId`
- Dùng `ApiKeyCredential` gián tiếp qua FEAT-004; mỗi attempt ghi
  [`ProviderRequestLog`](provider-request-log.md)

## Business Rules

| ID | Rule |
|---|---|
| BR-JOB-001 | Trạng thái quan sát được: `queued`, `processing`, `succeeded`, `failed`. |
| BR-JOB-002 | Còn lượt `attempts < maxAttempts` thì failure được requeue; hết lượt thì `failed`. |
| BR-JOB-003 | `succeeded` mà chưa có `MediaAsset` skeleton `ready` thì pose chưa đủ điều kiện publish. |
| BR-JOB-004 | `GET` job: `result` chỉ khi `succeeded`; `error` chỉ khi `failed`. |
| BR-JOB-005 | Không tuyên bố usable image khi provider thất bại hoặc job chưa `succeeded`. |
| BR-JOB-006 | Không tồn tại `Pose` persisted trước khi job `succeeded`; lúc đó chỉ có `jobId` làm correlation key. `Pose` (với `poseId` stable) được tạo sau `succeeded`. |