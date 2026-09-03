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

# Pose Domain Glossary (Canonical Domain Model)

> **Quy ước đọc:** semanti, fields, và business rules nằm tại
> [`docs/spec/data/`](../../spec/data/README.md) — file này chỉ giữ **terminology
> và naming chuẩn**, không lặp lại field tables hay business rules. ID strategy
> (§4) và terminology migration map (§5) là phần độc nhất của glossary.

## 1. Aggregate ownership map

| Term | Canonical status | Meaning |
|---|---|---|
| `Pose` | **Canonical** | Single domain aggregate; created post-extraction with metadata + three media roles + job history + visibility. Semantics: [`entities/pose.md`](../../spec/data/entities/pose.md) |
| `PoseGuide` | **Deprecated alias** | Legacy name for the same aggregate; now `Pose`. |
| `CommunityPose` | **Deprecated as entity** | Read-only **DTO / filtered view** over `Pose` where `status='published'`. No separate storage/entity. |
| `PersonalPose` | **Deprecated as entity** | Former device-local pose; folded into canonical `Pose` (created post-extraction). |
| `PoseReferenceKey` | **Deprecated** | Legacy Personal-vs-Community reference-key union; replaced by `poseId` and `mediaId`. |

## 2. Three media asset roles (canonical naming)

| # | Role | Canonical term | Legacy term(s) |
|---|---|---|---|
| 2.1 | `original` | original media | `source`, `source asset` |
| 2.2 | `skeleton` | skeleton media | `render`, `render asset`, `extracted pose image`, `result image`, `extract` |
| 2.3 | `thumbnail` | thumbnail media | thumbnail |

**Renaming rule:** the extraction-result terminology is **always** `skeleton`.
Terms `render`, `render asset`, `extracted pose image`, `result image`, and
`extract` (as a noun for the result) are deprecated and must be replaced by
`skeleton` in every model, API spec, ERD, and document.

Mỗi `Pose` có đúng ba `MediaAsset` (`original`, `skeleton`, `thumbnail`)
materialize **ngay tại lúc tạo** (post-extraction), non-nullable; `skeleton`
phải `ready` trước khi publish. Chi tiết: [`entities/media-asset.md`](../../spec/data/entities/media-asset.md),
[`enums.md`](../../spec/data/enums.md) (`MediaAssetRole`, `MediaAssetReadiness`).

## 3. Lifecycle and creation timing (tóm tắt)

- Submit ảnh → enqueue `ExtractionJob` (`202` + `jobId`) — **chưa có `Pose`**.
- Extraction `succeeded` → tạo `Pose` (`201`) với `poseId` stable, `status = local`,
  ba `MediaAsset` materialize; `ownerAccountId` bắt buộc trên mọi Pose.
- `Pose` chuyển `local` → `published` qua FEAT-006 — `poseId` giữ nguyên,
  publish không tạo entity thứ hai; `draft` là deprecated alias của `local`.

Chi tiết: [`domain-model.md`](../../spec/data/domain-model.md) (luồng product +
ranh giới), [`entities/pose.md`](../../spec/data/entities/pose.md) (fields +
business rules), [`enums.md`](../../spec/data/enums.md) (`PoseStatus`).

## 4. ID strategy

Canonical references use **two simple IDs** (UUIDs) plus the job correlation ID:

| ID | Scope | Used by |
|---|---|---|
| `jobId` | UUID PK of an `ExtractionJob`; the **correlation key during extraction** | `POST /api/extract-pose` → `202` `jobId`; `GET /api/extract-jobs/{jobId}`. No `Pose` exists while only a `jobId` is held. |
| `poseId` | UUID primary key of the **single** `Pose` entity | Every Pose-shaped reference across server, API, Saved, Photo, Try Pose. **Assigned once at creation (post-extraction)** and stable from `local` through `published`. |
| `mediaId` | UUID primary key of a `MediaAsset` | `Pose.originalMediaId` / `Pose.skeletonMediaId` / `Pose.thumbnailMediaId`; JSON `original_media_id` / `skeleton_media_id` / `thumbnail_media_id`. |

**Deprecated:** the legacy `PoseReferenceKey.Personal(id)|Community(id)` union,
which mixed an integer local ID with a server UUID, is **removed** from the
canonical model. All references now use the single stable `poseId` UUID.
Transient camera handoff notes may retain mobility detail but must not introduce
a second domain reference key.

## 5. Terminology migration map

Apply this map when refactoring any spec, ERD, API, Feature, or doc. The left
(legacy) term is deprecated; the right (canonical) term replaces it.

| Legacy | Canonical |
|---|---|
| `PoseGuide` | `Pose` |
| `CommunityPose` (entity) | `Pose` filtered public **DTO/view** (`status='published'`) |
| `PersonalPose` (entity) | `Pose` (canonical, created post-extraction); deprecate separate personal entity |
| `PoseReferenceKey.Personal\|Community` | `poseId` (UUID) + `mediaId` (UUID) |
| `draft` (PoseStatus) | `local` |
| `source` / `sourceAsset` / `sourceAssetId` | `original` / `originalMediaId` / `original_media_id` |
| `render` / `renderAsset` / `renderAssetId` / `renderLocator` / `imagePath`(result) / `resultAssetId` / `extracted pose image` / `result image` | `skeleton` / `skeletonMediaId` / `skeleton_url` / `skeletonLocator` |
| `thumbnailAssetId` | `thumbnailMediaId` / `thumbnail_media_id` |
| `guideId` | `poseId` |
| `result images` / `extract` (as result noun) | `skeleton` (extraction result) |
| `PoseAccepted` / `GuideAccepted` (`202` payload carrying a `pose`) | `ExtractionJobAccepted` (`202`: `{ jobId, status }` only — no Pose at job start) + `PoseCreated` (`201`: `{ pose }` after extraction succeeded) |

## 6. Canonical source of truth

- Domain model & layer map: [`docs/spec/data/domain-model.md`](../../spec/data/domain-model.md)
- Enums: [`docs/spec/data/enums.md`](../../spec/data/enums.md)
- Entity files: [`docs/spec/data/entities/`](../../spec/data/entities/) (`pose.md` is the canonical Pose spec)
- ERD: [`docs/spec/data/erd/`](../../spec/data/erd/)
- API contract: [`docs/spec/api/openapi.yaml`](../../spec/api/openapi.yaml)