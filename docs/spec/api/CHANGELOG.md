# Changelog — API Documentation

Định dạng: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

## [Unreleased]

### Added
- Product routes: `/api/guides`, publish/unpublish, `/api/me/saved` (FEAT-005, FEAT-006, FEAT-008).
- Query `q` trên `GET /api/community/poses` (title search, FEAT-003).
- Schemas: `PoseGuide`, `MediaAsset`, `SavedEntry`, `GuideAccepted`.
- Module files: `guides.md`, `publish.md`, `saved.md`.
- Security scheme `AccountSession` cho owner và saved collection.

### Changed
- Chuyển cây API vào `docs/spec/api/`.
- OpenAPI version `0.2.0`. Contract mô tả hợp đồng Feature, không chỉ runtime hiện có.
- Admin community POST không nhận `status=published` lúc intake; `202` chỉ là queued.
- Conventions: search, user auth, `202` ≠ complete/public.

### Deprecated
### Removed
### Fixed

## [0.1.0] - 2026-08-16

### Added
- Baseline OpenAPI 3.1 cho routes Express lúc đó.
- conventions.md và modules: health, extract-pose, community, admin-keys, admin-community, admin-jobs.
