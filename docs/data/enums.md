# Shared Enums

Enum dùng chung trong schema/API. `PoseStatus` và `PoseDifficulty` có trên server và mobile DTO; `ApiKeyStatus` và `ExtractionJobStatus` chỉ trên server.

## PoseStatus

Source: `schema.sql`, `communityStore.ts`, `PoseApiService.kt`

| Giá trị | Ý nghĩa |
|---|---|
| `draft` | Pose chưa publish; chỉ visible trong admin |
| `published` | Pose visible với public; route `/api/community/poses` chỉ trả về trạng thái này |

## PoseDifficulty

Source: `schema.sql`, `communityStore.ts`, `PoseApiService.kt`

| Giá trị | Ý nghĩa |
|---|---|
| `beginner` | Cấp độ người mới |
| `intermediate` | Cấp độ trung bình |
| `advanced` | Cấp độ nâng cao |
| _(null)_ | Không xác định độ khó |

## ApiKeyStatus

Source: `schema.sql`, `keyStore.ts`

| Giá trị | Ý nghĩa |
|---|---|
| `active` | Key đang hoạt động, được chọn để extraction |
| `disabled` | Key bị vô hiệu hóa thủ công |
| `exhausted` | Key đã hết quota ngày; reset hàng ngày về `active` |

## ExtractionJobStatus

Source: `schema.sql`, `extractionJobStore.ts`

| Giá trị | Ý nghĩa |
|---|---|
| `queued` | Job chờ worker xử lý |
| `processing` | Worker đang giữ lock và xử lý |
| `succeeded` | Extraction thành công; `result_image_base64` có giá trị |
| `failed` | Đã hết `max_attempts`; `error_code` và `error_message` được ghi |
