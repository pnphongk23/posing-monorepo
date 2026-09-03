---
schema_version: 1
type: spec
title: Pose Domain Glossary (Canonical Domain Model)
status: draft
relationships:
  specs:
    - "[[model-entity-catalogue]]"
    - "[[erd]]"
    - "[[api-catalogue]]"
    - "[[technical-architecture]]"
    - "[[product-feature-inventory]]"
  decisions: []
  plans:
    - "[[260823-0045-pose-domain-model-unification/plan|260823-0045]]"
  reports: []
  rules: []
  features:
    - "[[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]"
    - "[[FEAT-002-manage-a-local-photo-gallery|FEAT-002]]"
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
    - "[[FEAT-006-publish-a-pose|FEAT-006]]"
    - "[[FEAT-007-operate-pose-content-from-admin-web|FEAT-007]]"
    - "[[FEAT-008-use-published-poses|FEAT-008]]"
  source_paths:
    - docs/spec/data/domain-model.md
    - docs/spec/data/enums.md
    - docs/spec/data/entities/pose.md
    - docs/spec/data/entities/media-asset.md
    - docs/spec/api/openapi.yaml
---

# Pose Domain Glossary

> **File này chỉ giữ phần *độc nhất* của canonical Pose domain model: naming
> chuẩn (ID strategy + terminology migration map).** Semantics, fields,
> business rules, lifecycle chi tiết — nguồn sự thật tại
> [`docs/spec/data/`](../../spec/data/README.md) và [`docs/spec/api/`](../../spec/api/README.md);
> không lặp lại ở đây.

## ID strategy

| ID | Scope | Ghi chú |
|---|---|---|
| `jobId` | `ExtractionJob` — correlation key **trong lúc extraction** | `POST /api/extract-pose` → `202` `{ jobId }`; chưa có `Pose` khi chỉ có `jobId` |
| `poseId` | `Pose` — **định danh duy nhất của entity** | Gán **một lần tại lúc tạo (post-extraction)**, ổn định `local` → `published`; dùng cho mọi reference (Saved, Photo, Try Pose) |
| `mediaId` | `MediaAsset` — media của `Pose` | `Pose.originalMediaId` / `skeletonMediaId` / `thumbnailMediaId` |

`PoseReferenceKey.Personal(id)|Community(id)` (legacy union trộn integer id với
UUID) **đã bị gỡ khỏi canonical model** — mọi reference dùng `poseId` UUID đơn.

## Terminology migration map

Áp dụng khi refactor spec, ERD, API, Feature, hay doc. Trái = legacy (deprecated),
phải = canonical.

| Legacy | Canonical |
|---|---|
| `PoseGuide` | `Pose` |
| `CommunityPose` (entity) | `Pose` filtered public **DTO/view** (`status='published'`) |
| `PersonalPose` (entity) | `Pose` (canonical, created post-extraction) |
| `PoseReferenceKey.Personal\|Community` | `poseId` (UUID) + `mediaId` (UUID) |
| `draft` (PoseStatus) | `local` |
| `source` / `sourceAsset` / `sourceAssetId` | `original` / `originalMediaId` / `original_media_id` |
| `render` / `renderAsset` / `renderAssetId` / `renderLocator` / `imagePath`(result) / `resultAssetId` / `extracted pose image` / `result image` | `skeleton` / `skeletonMediaId` / `skeleton_url` / `skeletonLocator` |
| `thumbnailAssetId` | `thumbnailMediaId` / `thumbnail_media_id` |
| `guideId` | `poseId` |
| `result images` / `extract` (as result noun) | `skeleton` (extraction result) |
| `PoseAccepted` / `GuideAccepted` (`202` payload carrying a `pose`) | `ExtractionJobAccepted` (`202`: `{ jobId, status }` only) + `PoseCreated` (`201`: `{ pose }` after extraction succeeded) |

## Nguồn sự thật

- Domain model & layer map: [`docs/spec/data/domain-model.md`](../../spec/data/domain-model.md)
- Entity files: [`docs/spec/data/entities/`](../../spec/data/entities/) (`pose.md` canonical)
- Enums: [`docs/spec/data/enums.md`](../../spec/data/enums.md)
- ERD: [`docs/spec/data/erd/`](../../spec/data/erd/)
- API contract: [`docs/spec/api/openapi.yaml`](../../spec/api/openapi.yaml) + [`docs/spec/api/modules/`](../../spec/api/modules/)