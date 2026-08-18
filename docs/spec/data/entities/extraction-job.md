# ExtractionJob

## Description

Job theo dõi một lần extraction ảnh pose ([FEAT-004](../../../harness/features/FEAT-004-extract-reusable-pose-images.md)). Khi gắn với [`PoseGuide`](pose-guide.md), job thuộc lifecycle guide ([FEAT-005](../../../harness/features/FEAT-005-manage-a-pose-guide.md)). Direct `POST /api/extract-pose` trả kết quả đồng bộ cho caller; persistence thuộc caller/guide, không phải job này.

Admin và owner theo dõi job qua [FEAT-007](../../../harness/features/FEAT-007-operate-pose-content-from-admin-web.md) / FEAT-005. `202` queued không phải completion.

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | TEXT (UUID) | PK | Server-generated UUID |
| `guideId` | TEXT (UUID) | — | [`PoseGuide`](pose-guide.md) khi job thuộc guide flow; null với extract đồng bộ không persist |
| `status` | TEXT | ✓ | Enum `ExtractionJobStatus` |
| `sourceAssetId` | TEXT (UUID) | — | [`MediaAsset`](media-asset.md) nguồn khi có guide |
| `resultAssetId` | TEXT (UUID) | — | [`MediaAsset`](media-asset.md) render khi `succeeded` |
| `errorCode` | TEXT | — | Khi `failed` |
| `errorMessage` | TEXT | — | Khi `failed` |
| `attempts` | INTEGER | ✓ (default `0`) | Số lần đã thử |
| `maxAttempts` | INTEGER | ✓ (default `3`) | Trần retry |
| `createdAt` | DATETIME | ✓ | Enqueue |
| `updatedAt` | DATETIME | ✓ | Cập nhật cuối |

Payload nguồn/kết quả tạm thời có thể sống trên job trong lúc `processing`; khi `succeeded`, kết quả bền phải là `MediaAsset` `ready` gắn guide — không lấy base64 job làm catalogue.

## Relationships

- Nhiều `ExtractionJob` → một `PoseGuide` (`guideId`)
- Job `succeeded` tạo/cập nhật `MediaAsset` role `render` `ready` và gán `PoseGuide.renderAssetId`
- Dùng `ApiKeyCredential` gián tiếp qua FEAT-004; mỗi attempt ghi [`ProviderRequestLog`](provider-request-log.md)

## Business Rules

| ID | Rule |
|---|---|
| BR-JOB-001 | Trạng thái quan sát được: `queued`, `processing`, `succeeded`, `failed`. |
| BR-JOB-002 | Còn lượt `attempts < maxAttempts` thì failure được requeue; hết lượt thì `failed`. |
| BR-JOB-003 | `succeeded` mà chưa có `MediaAsset` render `ready` thì guide chưa đủ điều kiện publish. |
| BR-JOB-004 | `GET` job: `result` chỉ khi `succeeded`; `error` chỉ khi `failed`. |
| BR-JOB-005 | Không tuyên bố usable image khi provider thất bại hoặc job chưa `succeeded`. |
