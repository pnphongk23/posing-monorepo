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

This is a **number-hierarchical glossary** that enumerates the canonical Pose
domain model. It is the single naming and conceptual reference for the Pose
entity, its creation timing, its three media asset roles, its lifecycle states,
its ID strategy, and the terminology migration map that replaced the legacy
`PoseGuide` / `CommunityPose` / `PersonalPose` parallel-entity model.

The authoritative *semantics, fields, and business rules* for each concept below
live in [`docs/spec/data/`](../../spec/data/README.md); this glossary explains
and cross-links them. All ERD, API, Harness spec, and Feature documents must use
the terms defined here.

## 1. Canonical Pose entity

### 1.1 Definition

**Pose** (canonical entity — spec: [`data/entities/pose.md`](../../spec/data/entities/pose.md))
is the **single** domain entity that represents a reusable pose. It is the only
Pose-shaped aggregate in the canonical data model. There is **no** parallel
`PoseGuide`, `CommunityPose`, or `PersonalPose` entity in the canonical model.

**Creation timing:** a `Pose` is created **only after extraction succeeds**.
There is **no persisted `Pose` before extraction success** — during extraction
the work is tracked by the [`ExtractionJob`](#42-extractionjob) under its
`jobId` (correlation key), and no `Pose` row exists yet. Once extraction
succeeds, the `Pose` entity is created with its **stable `poseId` (UUID)** and
its `status` is initially `local`. That same `poseId` (and the same logical
record) is retained when `status` transitions `local` → `published`; publication
changes only the `status` field and does **not** create a second entity.

### 1.2 Aggregate ownership map

| Term | Canonical status | Meaning |
|---|---|---|
| `Pose` | **Canonical** | Single domain aggregate; created post-extraction with metadata + three media roles + job history + visibility. |
| `PoseGuide` | **Deprecated alias** | Legacy name for the same aggregate; now `Pose`. |
| `CommunityPose` | **Deprecated as entity** | Former "projection" of a published `PoseGuide`; now a **read-only DTO / filtered view** over `Pose` where `status='published'`. No separate storage/entity. |
| `PersonalPose` | **Deprecated as entity** | Former device-local pose; its concept folds into the canonical `Pose` (created post-extraction). Transient mobile handoff notes only where required. |
| `PoseReferenceKey` | **Deprecated** | Legacy Personal-vs-Community reference-key union; replaced by simple IDs `poseId` and `mediaId`. |

### 1.3 Field set (summary)

The `Pose` entity carries the following key fields (full set in
[`data/entities/pose.md`](../../spec/data/entities/pose.md)):

- `poseId` — stable primary key (UUID), assigned **once, at creation (post-extraction)**.
- `ownerAccountId` — **REQUIRED (non-nullable)** owning `Account` on **every**
  `Pose`, including Admin-created poses. Both local (mobile) and Admin poses are
  created for an authenticated account. The *authenticated actor* may differ
  from the *owner* in API headers: with an `AccountSession` the owner is the
  session account; with an Admin `Bearer` operator the request must carry the
  owning `ownerAccountId` explicitly (see [`account.md`](../../spec/data/entities/account.md)
  and [API conventions](../../spec/api/conventions.md)).
- `name`, `description`, `tags`, `difficulty`, `bodyParts` — metadata.
- `status` — [`PoseStatus`](#31-posestatus) (`local` | `published`).
- `originalMediaId` / `skeletonMediaId` / `thumbnailMediaId` — references to the
  three [`MediaAsset`](#2-three-media-asset-roles) records (roles `original`,
  `skeleton`, `thumbnail`). **All three slots are non-nullable and are
  materialized immediately upon creation** (which happens post-extraction).
- `currentJobId` — the [`ExtractionJob`](#42-extractionjob) that produced the
  current skeleton (the job was tracked by its `jobId` before the `Pose`
  existed).
- `createdAt`, `updatedAt`.

## 2. Three media asset roles

Every successful `Pose` has **exactly three** [`MediaAsset`](#41-mediaasset)
records materialized **immediately upon creation** (i.e. right after extraction
succeeds), each with a single, fixed `MediaAssetRole`, and all three Pose slots
are **non-nullable** from creation. These roles are the canonical naming for
every image attached to a Pose:

| # | Role | Canonical term | Legacy term(s) | Meaning |
|---|---|---|---|---|
| 2.1 | `original` | original media | `source`, `source asset` | The user's captured source image fed into extraction. |
| 2.2 | `skeleton` | skeleton media | `render`, `render asset`, `extracted pose image`, `result image`, `extract` | The AI extraction result — a reusable clean pose image. |
| 2.3 | `thumbnail` | thumbnail media | thumbnail | A small preview image for lists/catalogue. |

**Renaming rule:** the extraction-result terminology is **always** `skeleton`.
Terms `render`, `render asset`, `extracted pose image`, `result image`, and
`extract` (as a noun for the result) are deprecated and must be replaced by
`skeleton` in every model, API spec, ERD, and document.

Media readiness is governed by `MediaAssetReadiness` (`pending` | `ready` |
`failed`) — see [`data/enums.md`](../../spec/data/enums.md). A Pose may only be
`published` once its `skeleton` media is `ready`.

## 3. Lifecycle states

### 3.1 PoseStatus

`PoseStatus` is the visibility/lifecycle state of a `Pose`.

| Value | Meaning |
|---|---|
| `local` | Pose exists on the device/server but is not publicly discoverable. Only the owner (and Admin) can see it. This is the **initial state** of a created `Pose` and replaces the legacy `draft` value. |
| `published` | Pose is in the public catalogue; public list/detail and search return only this state. |

> **Legacy alias:** the old `draft` value is a **deprecated alias** of `local`.
> Newer documents and schemas use `local`. Migrating code/docs should map
> `draft` → `local`. `published` is unchanged.

Lifecycle (simple): **extraction succeeds → `Pose` created (`status: local`) →
`published`**.

The public catalogue is a **filtered read view / DTO** of `Pose` rows where
`status='published'` — it is not a separate persisted entity.

### 3.2 Creation timing and job correlation

The following sequence is authoritative:

1. The client submits an image. The system **enqueues an `ExtractionJob`** and
   returns `202 Accepted` with the job's **`jobId`** and a poll URL. **No `Pose`
   is created at this point** — the job itself is the correlation key.
2. The client polls `GET /api/extract-jobs/{jobId}` (or the Admin job endpoint)
   until the job is `succeeded` or `failed`.
3. **On `succeeded`**, the client finalizes creation — `POST /api/guides` (owner)
   or `POST /api/admin/community/poses` (Admin), referencing the succeeded
   `jobId` — and the system **creates the `Pose`** with its **stable `poseId`**,
   `status: local`, and the **three `MediaAsset`s (`original`, `skeleton`,
   `thumbnail`) materialized immediately**, returning `201 Created`.
4. The `Pose` transitions `local` → `published` via
   [`FEAT-006`](../../../docs/harness/features/FEAT-006-publish-a-pose.md) —
   `poseId` remains identical.

HTTP contract mapping: **`202 Accepted` for job start; `201 Created` for Pose
creation/completion** (see [API conventions](../../spec/api/conventions.md)).

## 4. Supporting entities and enumerations

### 4.1 MediaAsset

The media payload attached to a `Pose`. Canonical fields:
`mediaId` (UUID, PK), `poseId` (FK to `Pose` — was `guideId`), `role`
(`MediaAssetRole`), `locator`, `mimeType`, `readiness`, `createdAt`, `updatedAt`.
Exactly three `MediaAsset` records (`original`, `skeleton`, `thumbnail`) are
materialized when the `Pose` is created (post-extraction), and every
`Pose.originalMediaId` / `Pose.skeletonMediaId` / `Pose.thumbnailMediaId` is
non-nullable.
Spec: [`data/entities/media-asset.md`](../../spec/data/entities/media-asset.md).

### 4.2 ExtractionJob

Tracks one extraction attempt. The job is created at enqueue under its
**`jobId` (correlation key) — before any `Pose` exists**. On `succeeded`, the
system creates the `Pose` (stable `poseId`), materializes the three
`MediaAsset`s, and back-fills the job's `poseId` FK (nullable until then).
The `skeleton` `MediaAsset` (`skeletonMediaId`, was `resultAssetId`) must be
`ready` before publication. `guideId` is renamed `poseId`.
Spec: [`data/entities/extraction-job.md`](../../spec/data/entities/extraction-job.md).

### 4.3 Photo

Device-local captured still image (`Photo.sq`). `Photo.poseId` now optionally
references the canonical `Pose` (not a `PersonalPose`); because a `Pose` is
created only after extraction succeeds, the link exists only once the Pose
exists. Spec: [`data/entities/photo.md`](../../spec/data/entities/photo.md).

### 4.4 SavedEntry

"Saved" link between a signed-in `Account` and a `published` `Pose`
(`SavedEntry.poseId` → `Pose.poseId`).
Spec: [`data/entities/saved-entry.md`](../../spec/data/entities/saved-entry.md).

### 4.5 Account, ApiKeyCredential, ProviderRequestLog

Operational/identity entities. `Account` owns `Pose`s. `ApiKeyCredential` +
`ProviderRequestLog` record provider usage during extraction. Their Pose links
use the canonical `poseId` naming.
Specs: [`data/entities/account.md`](../../spec/data/entities/account.md),
[`data/entities/api-key-credential.md`](../../spec/data/entities/api-key-credential.md),
[`data/entities/provider-request-log.md`](../../spec/data/entities/provider-request-log.md).

### 4.6 PreparedPoseReference (transient)

An in-memory, non-persisted transport contract for Try Pose camera handoff
[FEAT-008](../../harness/features/FEAT-008-use-published-poses.md). It references a
`poseId` / `mediaId` and carries a verified local `skeletonLocator` (formerly
`renderLocator`; local data URI / absolute path only).
Spec: [`data/entities/prepared-pose-reference.md`](../../spec/data/entities/prepared-pose-reference.md).

### 4.7 Enumerations

Full enum set and values live in [`data/enums.md`](../../spec/data/enums.md):
`PoseStatus`, `PoseDifficulty`, `MediaAssetRole`, `MediaAssetReadiness`,
`ExtractionJobStatus`, `ApiKeyStatus`.
Spec: [`data/entities/pose.md`](../../spec/data/entities/pose.md).

## 5. ID strategy

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

## 6. Terminology migration map

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

## 7. Canonical source of truth

- Domain model & layer map: [`docs/spec/data/domain-model.md`](../../spec/data/domain-model.md)
- Enums: [`docs/spec/data/enums.md`](../../spec/data/enums.md)
- Entity files: [`docs/spec/data/entities/`](../../spec/data/entities/) (`pose.md` is the canonical Pose spec)
- ERD: [`docs/spec/data/erd/`](../../spec/data/erd/)
- API contract: [`docs/spec/api/openapi.yaml`](../../spec/api/openapi.yaml)