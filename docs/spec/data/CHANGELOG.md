# Changelog — Data Documentation

Định dạng: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

## [Unreleased]

### Added
- Hợp đồng product cho `PoseGuide`, `MediaAsset`, `Account`, `SavedEntry` (FEAT-005, FEAT-006, FEAT-008).
- Enum `MediaAssetRole`, `MediaAssetReadiness`.
- ERD server mô tả aggregate guide, catalogue projection, saved collection.

### Changed
- Chuyển cây data vào `docs/spec/data/`.
- Domain model lấy Features làm nguồn sự thật, không còn mục TBD theo implementation.
- `CommunityPose` là projection published của `PoseGuide`.
- `ExtractionJob` gắn `guideId` và kết quả bền là `MediaAsset` render `ready`.
- Business rules Photo/Gallery theo FEAT-001/002 (atomic capture, xóa file+metadata).

### Deprecated
### Removed
### Fixed

## [0.1.0] - 2026-08-16

### Added
- Tài liệu baseline cho entities theo schema runtime lúc đó.
- Entity files: Photo, PersonalPose, CommunityPose, ExtractionJob, ApiKeyCredential, ProviderRequestLog, PoseReferenceKey, PreparedPoseReference.
- ERD: server, mobile, conceptual.
- Enums: PoseStatus, PoseDifficulty, ApiKeyStatus, ExtractionJobStatus.
