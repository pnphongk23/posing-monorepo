# Changelog — API Documentation

Định dạng: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

## [Unreleased]

### Added
- Product routes: `/api/guides`, publish/unpublish, `/api/me/saved` (FEAT-005, FEAT-006, FEAT-008).
- Query `q` trên `GET /api/community/poses` (title search, FEAT-003).
- Schemas: `Pose` (was `PoseGuide`), `MediaAsset`, `SavedEntry`, `PoseCreated` (was `PoseAccepted` / `GuideAccepted`), `ExtractionJobAccepted`.
- Module files: `guides.md`, `publish.md`, `saved.md`.
- Security scheme `AccountSession` cho owner và saved collection.

### Changed
- Chuyển cây API vào `docs/spec/api/`.
- OpenAPI version `0.5.0`. Unify API về canonical `Pose` entity và lifecycle `local` → `published`.
- **Creation timing:** `202 Accepted` = job start chỉ (`jobId`, chưa có `Pose`); `201 Created` = Pose creation/completion sau khi extraction `succeeded` (`POST /api/guides`, admin intake; request JSON `jobId` + metadata).
- `MediaAssetRole`: `source` → `original`, `render` → `skeleton`.
- `Pose` response: camelCase `poseId`, `ownerAccountId`, `originalUrl`, `skeletonUrl`, `thumbnailUrl` — ba media role non-nullable, materialize tại lúc tạo pose.
- `CommunityPose` là **published-only** DTO/view của `Pose` published (field `poseId`; `status` luôn `published`; `thumbnailUrl` non-nullable); admin list trả canonical `Pose`.
- `ownerAccountId` bắt buộc trên mọi Pose; pose admin-created phải chỉ định `ownerAccountId` tường minh.
- Thuật ngữ extraction-result chuyển sang `skeleton`. **(Legacy/deprecated terms: `render`, `extracted pose image`, `result image`)**.
- Admin community POST không nhận `status=published` lúc intake; `202` chỉ là queued.
- Conventions: search, user auth, `202` ≠ complete/public; bảng status codes tách `202` (job start) / `201` (pose creation).

### Deprecated
- `draft` (PoseStatus) → alias legacy của `local`.
- `PoseGuide`, `GuideAccepted`, `PoseAccepted`, `renderAssetId` → identifiers/schema cũ.

### Deprecated
### Removed
### Fixed

## [0.1.0] - 2026-08-16

### Added
- Baseline OpenAPI 3.1 cho routes Express lúc đó.
- conventions.md và modules: health, extract-pose, community, admin-keys, admin-community, admin-jobs.
