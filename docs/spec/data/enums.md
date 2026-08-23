# Shared Enums

Enum dùng chung trong domain product và API. Tên enum/giá trị tiếng Anh.

## PoseStatus

Dùng cho entity canonical [`Pose`](entities/pose.md).

| Giá trị | Ý nghĩa |
|---|---|
| `local` | Pose chưa public; chỉ owner và Admin thấy. **Trạng thái khởi tạo** của pose vừa tạo (post-extraction) |
| `published` | Có trên public catalogue; list/detail công khai chỉ trả trạng thái này |

> `draft` (legacy) là alias deprecated của `local`. Tài liệu/schema mới dùng `local`;
> migrate `draft` → `local`. `published` giữ nguyên.
>
> **Creation timing:** `Pose` được tạo chỉ sau khi extraction `succeeded`
> (`status = local`); trong lúc extraction chỉ có `ExtractionJob` với `jobId`.
> `poseId` stable khi `local` → `published` (BR-POSE-004).

Publish đòi hỏi skeleton [`MediaAsset`](entities/media-asset.md) `ready` — xem
BR-POSE-002, BR-ASSET-002.

## PoseDifficulty

| Giá trị | Ý nghĩa |
|---|---|
| `beginner` | Người mới |
| `intermediate` | Trung bình |
| `advanced` | Nâng cao |
| _(null)_ | Không gán độ khó |

## MediaAssetRole

`Pose` có đúng ba media role, **materialize tại lúc tạo pose (post-extraction)**, cả ba slot non-nullable:

| Giá trị | Ý nghĩa |
|---|---|
| `original` | Ảnh nguồn người dùng đưa vào extraction (trước đây gọi `source`) |
| `skeleton` | Kết quả extraction dùng lại được (trước đây gọi `render` / `extracted pose image` / `result image`) |
| `thumbnail` | Ảnh thu nhỏ cho catalogue |

## MediaAssetReadiness

| Giá trị | Ý nghĩa |
|---|---|
| `pending` | Chưa có locator đọc được |
| `ready` | Locator đọc được; đủ cho catalogue / Try Pose / publish (với role `skeleton`) |
| `failed` | Không dùng được; không publish, không Try Pose |

## ExtractionJobStatus

| Giá trị | Ý nghĩa |
|---|---|
| `queued` | Chờ xử lý |
| `processing` | Đang extraction |
| `succeeded` | Có kết quả; skeleton asset phải `ready` trước khi publish |
| `failed` | Hết `maxAttempts` hoặc lỗi không retry |

## ApiKeyStatus

| Giá trị | Ý nghĩa |
|---|---|
| `active` | Được chọn cho extraction |
| `disabled` | Tắt thủ công |
| `exhausted` | Hết quota ngày; reset về `active` |