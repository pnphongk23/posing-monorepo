# Pose

## Description

Entity trung tâm và **duy nhất** của domain product: một pose dùng lại được, với
một `poseId` UUID ổn định từ lúc tạo cho tới khi `published`. `Pose` là khối làm
việc của Pose Owner ([FEAT-005](../../../harness/features/FEAT-005-manage-a-pose-guide.md))
và là đối tượng trên catalogue công khai khi `status = published`
([FEAT-003](../../../harness/features/FEAT-003-browse-and-search-published-poses.md),
[FEAT-006](../../../harness/features/FEAT-006-publish-a-pose.md)).

**Creation timing:** `Pose` được tạo **chỉ sau khi extraction `succeeded`**.
Không tồn tại `Pose` persisted trước khi extraction thành công. Trong lúc
extraction, công việc được theo dõi bằng [`ExtractionJob`](extraction-job.md)
dưới `jobId` (correlation key); khi extraction thành công, `Pose` được tạo với
`poseId` (UUID) ổn định, `status = local`, và **cả ba** `MediaAsset` (`original`,
`skeleton`, `thumbnail`) được materialize ngay tại lúc tạo (non-nullable).

Không tồn tại entity song song `PoseGuide`, `CommunityPose`, hay `PersonalPose`
trong canonical model. Catalogue công khai là **view/DTO đọc kết quả** lọc các
`Pose` có `status = published`, không phải entity riêng. Đổi trạng thái công khai
chỉ thay đổi `status`, không tạo entity thứ hai; `poseId` giữ nguyên
`local` → `published`.

`ownerAccountId` là **bắt buộc (non-nullable) trên mọi `Pose`**, kể cả pose do
Admin tạo: pose local (mobile) và pose admin đều được tạo cho một account đã
xác thực. Authenticated actor có thể khác owner trong API headers — với
`AccountSession` thì owner là session account; với Admin `Bearer` thì request
phải kèm `ownerAccountId` tường minh (xem [`account.md`](account.md) và
[API conventions](../../api/conventions.md)).

Extraction thuộc [FEAT-004](../../../harness/features/FEAT-004-extract-reusable-pose-images.md);
`Pose` tái sử dụng hợp đồng đó. API response của local/admin endpoints dùng
`PoseResponse` (canonical `Pose`) với các URL camelCase
`originalUrl` / `skeletonUrl` / `thumbnailUrl` — projection từ locator của ba
`MediaAsset` (xem [openapi.yaml](../../api/openapi.yaml)).

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `poseId` | TEXT (UUID) | PK | Định danh duy nhất, gán **một lần tại lúc tạo (post-extraction)**, ổn định từ `local` tới `published` |
| `ownerAccountId` | TEXT (UUID) | ✓ | [`Account`](account.md) sở hữu pose — **bắt buộc trên mọi Pose** (mobile + admin) |
| `name` | TEXT | ✓ | Tên hiển thị |
| `description` | TEXT | — | Mô tả |
| `tags` | TEXT[] | ✓ (default `[]`) | Nhãn lọc catalogue |
| `difficulty` | TEXT | — | Enum `PoseDifficulty` |
| `bodyParts` | TEXT[] | ✓ | Ít nhất một phần cơ thể |
| `status` | TEXT | ✓ (default `local`) | Enum `PoseStatus`: `local` \| `published`; `local` là trạng thái khởi tạo |
| `originalMediaId` | TEXT (UUID) | ✓ | [`MediaAsset`](media-asset.md) role `original` — materialize tại lúc tạo |
| `skeletonMediaId` | TEXT (UUID) | ✓ | [`MediaAsset`](media-asset.md) role `skeleton` — materialize tại lúc tạo; bắt buộc `ready` trước khi publish |
| `thumbnailMediaId` | TEXT (UUID) | ✓ | [`MediaAsset`](media-asset.md) role `thumbnail` — materialize tại lúc tạo |
| `currentJobId` | TEXT (UUID) | — | [`ExtractionJob`](extraction-job.md) đã tạo skeleton hiện tại (job được theo dõi bằng `jobId` trước khi pose tồn tại) |
| `createdAt` | DATETIME | ✓ | Thời điểm tạo (sau extraction success) |
| `updatedAt` | DATETIME | ✓ | Thời điểm cập nhật cuối |

> API response (`PoseResponse`) thay ba media id bằng URL camelCase:
> `originalUrl`, `skeletonUrl`, `thumbnailUrl` (locator của các `MediaAsset`
> tương ứng) — cộng `poseId`, `ownerAccountId`, `currentJobId`.

## Relationships

- `Pose.ownerAccountId` → `Account.id` (bắt buộc)
- `Pose` 1 — **3** `MediaAsset` (roles `original`, `skeleton`, `thumbnail`), cả ba
  non-nullable, materialize tại lúc tạo;
  `originalMediaId` / `skeletonMediaId` / `thumbnailMediaId` → `MediaAsset.mediaId`
- `Pose` 1 — 0..* `ExtractionJob` (lịch sử; `currentJobId` trỏ job hiện tại; job
  đứng trước pose trong luồng dùng `jobId`)
- `Pose` 1 — 0..* `SavedEntry` (`poseId`) khi `published`
- `Photo.poseId` → `Pose.poseId` (optional, mobile local — chỉ khi pose đã tồn tại)
- Public catalogue = view lọc `Pose` có `status = published` (DTO `CommunityPose`)
- Admin operator ([FEAT-007](../../../harness/features/FEAT-007-operate-pose-content-from-admin-web.md))
  tạo/sửa pose qua cùng model này (kèm `ownerAccountId` tường minh)

## Business Rules

| ID | Rule |
|---|---|
| BR-POSE-001 | Submit ảnh hợp lệ chỉ enqueue một `ExtractionJob` (`202` + `jobId`) — **không tạo `Pose`**. `Pose` được tạo **chỉ sau khi extraction `succeeded`** (thường qua `POST /api/guides` / admin intake trả `201 Created`). |
| BR-POSE-002 | Không được tuyên bố pose public khi skeleton `MediaAsset` chưa `ready`. |
| BR-POSE-003 | Retry / re-extract tạo hoặc tái xếp `ExtractionJob` gắn cùng `Pose`; không tạo pose mới. |
| BR-POSE-004 | `poseId` gán một lần tại tạo (post-extraction) và giữ nguyên khi `status` chuyển `local` → `published`; publish không tạo entity thứ hai. |
| BR-POSE-005 | Xóa terminal gỡ pose khỏi catalogue, ngắt `SavedEntry` khỏi nội dung công khai, và không để lại job/asset được trình bày như pose còn sống. |
| BR-POSE-006 | Chỉ owner `Account` hoặc Admin operator được sửa metadata, retry, re-extract, revert, xóa. |
| BR-POSE-007 | Catalogue công khai chỉ trả `status = published`; đây là view/DTO, không phải entity lưu trữ riêng. |
| BR-POSE-008 | `ownerAccountId` bắt buộc trên mọi `Pose`; pose do Admin tạo (Bearer, không có session account) phải chỉ định `ownerAccountId` của `Account` sở hữu trong request. |
| BR-POSE-009 | Đúng ba `MediaAsset` (`original`, `skeleton`, `thumbnail`) materialize tại lúc tạo pose; `originalMediaId`, `skeletonMediaId`, `thumbnailMediaId` đều non-nullable từ creation. |