# Shared Enums

Enum dùng chung trong domain product và API. Tên enum/giá trị tiếng Anh.

## PoseStatus

Dùng cho [`PoseGuide`](entities/pose-guide.md) và projection [`CommunityPose`](entities/community-pose.md).

| Giá trị | Ý nghĩa |
|---|---|
| `draft` | Guide chưa public; chỉ owner và Admin thấy |
| `published` | Có trên public catalogue; list/detail công khai chỉ trả trạng thái này |

Publish đòi hỏi render [`MediaAsset`](entities/media-asset.md) `ready` — xem BR-GUIDE-002, BR-ASSET-002.

## PoseDifficulty

| Giá trị | Ý nghĩa |
|---|---|
| `beginner` | Người mới |
| `intermediate` | Trung bình |
| `advanced` | Nâng cao |
| _(null)_ | Không gán độ khó |

## MediaAssetRole

| Giá trị | Ý nghĩa |
|---|---|
| `source` | Ảnh nguồn đưa vào extraction |
| `render` | Ảnh pose dùng lại được sau extraction |
| `thumbnail` | Ảnh thu nhỏ cho catalogue |

## MediaAssetReadiness

| Giá trị | Ý nghĩa |
|---|---|
| `pending` | Chưa có locator đọc được |
| `ready` | Locator đọc được; đủ cho catalogue / Try Pose / publish (với role `render`) |
| `failed` | Không dùng được; không publish, không Try Pose |

## ExtractionJobStatus

| Giá trị | Ý nghĩa |
|---|---|
| `queued` | Chờ xử lý |
| `processing` | Đang extraction |
| `succeeded` | Có kết quả; render asset phải `ready` trước khi publish |
| `failed` | Hết `maxAttempts` hoặc lỗi không retry |

## ApiKeyStatus

| Giá trị | Ý nghĩa |
|---|---|
| `active` | Được chọn cho extraction |
| `disabled` | Tắt thủ công |
| `exhausted` | Hết quota ngày; reset về `active` |
