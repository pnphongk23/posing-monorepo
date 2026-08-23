# Changelog — Data Documentation

Định dạng: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

## [Unreleased]

### Added
- Canonical `Pose` entity duy nhất (`entities/pose.md`) với `poseId` (UUID) ổn định từ lúc tạo (post-extraction) tới published.
- Glossary canonical: `docs/harness/specs/pose-domain-glossary.md` — đánh số phân cấp (1., 1.1…).
- Ba media role canonical: `original`, `skeleton`, `thumbnail` — materialize tại lúc tạo pose, non-nullable.

### Changed
- **Creation timing:** `Pose` chỉ được tạo sau khi extraction `succeeded`; trong lúc extraction chỉ có `ExtractionJob` với `jobId` (correlation key). `ExtractionJob.poseId` nullable tới khi pose tạo.
- **Mandatory owner:** `ownerAccountId` bắt buộc (non-nullable) trên mọi `Pose`, kể cả pose admin; authenticated actor (Admin Bearer) có thể khác owner.
- Unify domain: bỏ entity song song `PoseGuide`, `CommunityPose`, `PersonalPose`; catalogue công khai là view/DTO (`CommunityPose` published-only, field `poseId`).
- `MediaAssetRole`: `source` → `original`, `render` → `skeleton`.
- `PoseStatus`: `draft` → `local` (deprecated alias).
- `ExtractionJob` gắn `poseId` (was `guideId`); kết quả bền là `MediaAsset` skeleton `ready`.
- ID đơn giản `poseId` / `mediaId` (+ `jobId` làm correlation key); bỏ `PoseReferenceKey.Personal|Community` khỏi canonical model.
- Thuật ngữ extraction-result chuyển sang `skeleton`. **(Legacy/deprecated terms: `render`, `extracted pose image`, `result image`)**.

### Deprecated
- `PoseGuide` → alias của `Pose`.
- `PersonalPose`, `PoseReferenceKey`, `CommunityPose`(entity) → deprecate; chuyển sang `Pose` + view/DTO.

### Deprecated
### Removed
### Fixed

## [0.1.0] - 2026-08-16

### Added
- Tài liệu baseline cho entities theo schema runtime lúc đó.
- Entity files: Photo, PersonalPose, CommunityPose, ExtractionJob, ApiKeyCredential, ProviderRequestLog, PoseReferenceKey, PreparedPoseReference.
- ERD: server, mobile, conceptual.
- Enums: PoseStatus, PoseDifficulty, ApiKeyStatus, ExtractionJobStatus.
