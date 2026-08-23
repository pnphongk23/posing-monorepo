# Tài liệu API

Nguồn sự thật cho API contract product. Paths, schemas, status codes nằm trong [`openapi.yaml`](openapi.yaml). Module markdown giải thích semantics và business rules — không duplicate schema.

Tài liệu mô tả **hợp đồng mà Features yêu cầu**. Tên path/field tiếng Anh; mô tả tiếng Việt. URL thật `/api/...`, không có `/v1/`.

Domain có **một entity trung tâm duy nhất**: `Pose` (mô hình hợp nhất của `PoseGuide`/`CommunityPose`/`PersonalPose`). Catalogue công khai là DTO/view đọc kết quả trên các `Pose` `published`.

**Creation timing & status codes:** `Pose` được tạo **chỉ sau khi extraction
`succeeded`** — `202 Accepted` là job start (`jobId`, chưa có Pose); `201 Created`
là Pose creation/completion (pose được tạo với `poseId` stable và ba media role
`original`, `skeleton`, `thumbnail` materialize ngay). `ownerAccountId` bắt buộc
trên mọi Pose; response dùng camelCase `poseId`, `ownerAccountId`, `originalUrl`,
`skeletonUrl`, `thumbnailUrl`. `CommunityPose` là published-only DTO.

## Cấu trúc

| Tệp/Thư mục | Nội dung |
|---|---|
| [`openapi.yaml`](openapi.yaml) | OpenAPI 3.1 — paths, schemas, status codes |
| [`conventions.md`](conventions.md) | URL, auth, pagination, errors, datetime |
| [`modules/`](modules/) | Docs theo domain |
| [`CHANGELOG.md`](CHANGELOG.md) | Lịch sử tài liệu API |

## Routes theo Feature

| Feature | Module | Path prefix |
|---|---|---|
| — | Health | `GET /api/health` |
| [FEAT-003](../../harness/features/FEAT-003-browse-and-search-published-poses.md) | [community.md](modules/community.md) | `GET /api/community/poses` |
| [FEAT-004](../../harness/features/FEAT-004-extract-reusable-pose-images.md) | [extract-pose.md](modules/extract-pose.md) | `POST /api/extract-pose` |
| [FEAT-005](../../harness/features/FEAT-005-manage-a-pose-guide.md) | [guides.md](modules/guides.md) | `/api/guides` |
| [FEAT-006](../../harness/features/FEAT-006-publish-a-pose.md) | [publish.md](modules/publish.md) | `/api/guides/:id/publish`, `/unpublish` |
| [FEAT-007](../../harness/features/FEAT-007-operate-pose-content-from-admin-web.md) | [admin-keys.md](modules/admin-keys.md), [admin-community.md](modules/admin-community.md), [admin-jobs.md](modules/admin-jobs.md) | `/api/admin/*` |
| [FEAT-008](../../harness/features/FEAT-008-use-published-poses.md) | [saved.md](modules/saved.md) | `/api/me/saved` |

Try Pose không có HTTP: chuẩn bị local từ detail published. Capture/gallery không có HTTP.

Admin Web không định nghĩa API riêng: proxy inject Bearer, contract nằm ở các module trên.
