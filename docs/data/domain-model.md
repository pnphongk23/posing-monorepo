# Domain Model

Tổng quan các thực thể, phân loại, và trạng thái triển khai.

## Thực thể implemented (có source code)

| Entity | Layer | Source |
|---|---|---|
| Photo | Mobile SQLite (local) | `Photo.sq` |
| PersonalPose | Mobile SQLite (local) | `Pose.sq` |
| CommunityPose | Server SQLite | `schema.sql`, `communityStore.ts` |
| ExtractionJob | Server SQLite | `schema.sql`, `extractionJobStore.ts` |
| ApiKeyCredential | Server SQLite | `schema.sql`, `keyStore.ts` |
| ProviderRequestLog | Server SQLite | `schema.sql`, `keyStore.ts` |
| PoseReferenceKey | Mobile in-memory | `PoseReferenceKey.kt` |
| PreparedPoseReference | Mobile in-memory | `PreparedPoseReference.kt` |

## Ranh giới quan trọng

- `Photo` và `PersonalPose` là **mobile-local**: không có FK tới server.
- `CommunityPose` là **server-owned**: không có FK ngược về mobile.
- `schema_bootstrap` là bảng operational, **không phải product entity** — bị bỏ qua khỏi domain model.

## Thực thể TBD

Các khái niệm sau được feature specs đề cập nhưng **chưa có implementation**:

### MediaAsset

Khái niệm cross-feature cho media payload (source, render, thumbnail). Hiện tại các locator được lưu dưới dạng string trong `CommunityPose.image_path` / `thumbnail_path`; không có bảng hoặc class riêng.

### PoseGuide

Aggregate concept gồm source image, render, metadata, owner, re-extraction history. Hiện tại `PersonalPose` (local) và `CommunityPose` + `ExtractionJob` (server) là các mảnh ghép rời, chưa có guide aggregate.

### Account / SavedEntry

Ownership và saved-collection cho published poses. **Không tìm thấy schema, API, hoặc auth implementation** trong codebase.
