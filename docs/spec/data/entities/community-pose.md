# CommunityPose (deprecated as entity — public DTO/view)

## Description

> **Deprecated as entity.** `CommunityPose` không còn là entity lưu trữ riêng.
> Nó là **DTO / filtered view** đọc kết quả trên canonical [`Pose`](pose.md)
> với `status = published`. Không có bảng/entity `CommunityPose` độc lập trong
> canonical model. Catalogue [FEAT-003](../../../harness/features/FEAT-003-browse-and-search-published-poses.md)
> chỉ đọc view này. Visibility do [FEAT-006](../../../harness/features/FEAT-006-publish-a-pose.md)
> quyết định qua `Pose.status`.

Cùng `poseId` với `Pose` nguồn (DTO dùng field `poseId` thay vì `id`).
**`CommunityPose` là read-only published DTO** — chỉ đại diện `status = 'published'`;
**không đại diện pose `local`** và không có storage riêng. Admin/local endpoints đọc
canonical [`Pose`](pose.md) (không qua DTO này). Public DTO không gồm owner,
original asset, hay job. `skeletonUrl` và `thumbnailUrl` đều là
project của các `MediaAsset` tương ứng (skeleton/thumbnail materialize tại lúc tạo).

## Fields (DTO — projection của Pose published)

| Field | Type | Required | Description |
|---|---|---|---|
| `poseId` | TEXT (UUID) | PK | `Pose.poseId` (DTO dùng `poseId`, không dùng `id`) |
| `name` | TEXT | ✓ | Tên pose |
| `skeletonUrl` | TEXT | ✓ | Locator skeleton `ready` (camelCase DTO) |
| `thumbnailUrl` | TEXT | ✓ | Locator thumbnail `ready` — non-nullable (ba media slot materialize tại tạo pose) |
| `tags` | TEXT[] | ✓ | Nhãn |
| `difficulty` | TEXT | — | Enum `PoseDifficulty` |
| `description` | TEXT | — | Mô tả |
| `bodyParts` | TEXT[] | ✓ | Phần cơ thể |
| `status` | TEXT | ✓ | Luôn `published` trên public API |
| `uploadedAt` | DATETIME | ✓ | Thời điểm pose vào catalogue |
| `downloadCount` | INTEGER | ✓ (default `0`) | Tăng khi GET detail thành công |

## Relationships

- View/DTO trên [`Pose`](pose.md) (`status = published`), cùng `poseId`
- `skeletonUrl` / `thumbnailUrl` ← [`MediaAsset`](media-asset.md) role `skeleton` / `thumbnail` với `readiness = ready`
- Được [`SavedEntry.poseId`](saved-entry.md) tham chiếu
- Không lộ `ownerAccountId`, `originalUrl`, hay job

## Business Rules

| ID | Rule |
|---|---|
| BR-COMMUNITY-001 | Public list/detail chỉ trả `status = published`. Draft/local không lộ qua 404. |
| BR-COMMUNITY-002 | `downloadCount` tăng 1 mỗi lần `GET /api/community/poses/:id` thành công. |
| BR-COMMUNITY-003 | Admin đọc canonical `Pose` (cả `local` và `published`) qua API admin/pose; `CommunityPose` DTO chỉ đại diện `status = 'published'`, không đại diện pose `local`. |
| BR-COMMUNITY-004 | `skeletonUrl` phải là locator skeleton `ready`. Pose chưa có skeleton `ready` không được `published`. |
| BR-COMMUNITY-005 | Title search (`q`) chỉ khớp trên published records; không trả local/draft. |
| BR-COMMUNITY-006 | Filter `tag` và `difficulty` áp trên published list; kết quả không trùng `poseId` đang active. |
| BR-COMMUNITY-007 | `CommunityPose` là view/DTO; không có storage riêng — xem glossary mục 1.2. |
| BR-COMMUNITY-008 | DTO published-only: `status` luôn `published`; DTO không bao giờ đại diện pose `local`. |