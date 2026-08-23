---
schema_version: 1
title: Manage a Pose Guide
relationships:
  specs:
    - "[[product-feature-inventory]]"
    - "[[technical-architecture]]"
    - "[[ui-ux-system]]"
    - "[[model-entity-catalogue]]"
    - "[[erd]]"
    - "[[api-catalogue]]"
  decisions: []
  plans:
    - "[[260816-2240-higgsfield-cli-parallel-extract-provider/plan|260816-2240]]"
  reports:
    - "[[REP-002-feature-gap-and-release-readiness-audit|REP-002]]"
    - "[[REP-004-backend-feature-and-model-entity-scout|REP-004]]"
  rules: []
  features:
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-006-publish-a-pose|FEAT-006]]"
  source_paths:
    - web/services/pose-extract-server/src/db/communityStore.ts
    - web/services/pose-extract-server/src/db/extractionJobStore.ts
    - web/services/pose-extract-server/src/worker/job-processor.ts
    - web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts
    - web/services/pose-extract-server/src/routes/jobStatusRoutes.ts
    - web/services/pose-extract-server/src/routes/adminRoutes.ts
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt
    - mobile/shared/src/commonMain/sqldelight/com/aipose/Pose.sq
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PosesScreen.kt
type: feature
id: FEAT-005
status: approved
created: 2026-08-09
approved: 2026-08-17
approved_by: Product Authority
---

# FEAT-005: Manage a Pose Guide

## Introduction

The Pose Owner manages pose metadata and the lifecycle around an extracted
pose. This is the business owner for pose state, but it must reuse
[FEAT-004](FEAT-004-extract-reusable-pose-images.md)'s extraction contract and
[FEAT-006](FEAT-006-publish-a-pose.md)'s publication boundary. The current
implementation only partially realizes this aggregate.

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Pose Owner | Business role | Maintain one reusable pose lifecycle | Review metadata and extraction outcomes |
| Mobile user | User | Create a personal Pose from a source image | Choose a source, enter canonical metadata, submit, track the job, and retry manually |
| Admin operator/worker | Business role/external process | Operate queued community work | Submit, process, and inspect jobs |

### Preconditions

- A guide submission has eligible source metadata and an extraction path.
- A mobile user has a source image (freshly captured or selected) from the existing intake entry points and the canonical Pose fields.

### Trigger

A mobile user submits, inspects, or manually retries a personal extraction; an owner or operator submits, inspects, retries, or manages a guide.

### Main flow

**Mobile personal flow (canonical):**

1. **Actor:** The Mobile user opens the dedicated Extract screen. **System:** The screen offers source-image selection through the existing camera and local-library entry points.
2. **Actor:** The Mobile user chooses a source image and enters the canonical Pose fields — name and tags (required) plus at least one bodyPart; description and difficulty are optional. **System:** The Extract screen validates the required fields and the source image.
3. **Actor:** The Mobile user submits. **System:** The device persists a local job record with the server `jobId` and `queued` status, then enqueues the server `ExtractionJob` through FEAT-004 and receives `202`.
4. **Actor:** The Mobile user inspects the job on the dedicated local Jobs screen. **System:** The device polls `GET /api/extract-jobs/:jobId` and updates the local record (queued, processing, succeeded, or failed). There is no job-list API.
5. **System:** On `succeeded`, the app creates a local `Pose` (`status=local`, legacy `draft` alias) with the submitted metadata and the **three media roles materialized (post-extraction): `original`, `skeleton`, `thumbnail`**; on `failed`, the local record retains the error and the Jobs screen shows an explicit manual Retry.

**Admin/operator flow (community):**

6. **Actor:** The operator submits community metadata and an image. **System:** The image is submitted through FEAT-004: the service enqueues an `ExtractionJob` and returns `202` + `jobId` — **no `Pose` exists yet**.
7. **System:** The worker claims and processes the job. **System:** The job becomes queued, processing, succeeded, or failed according to observed store transitions.
8. **Actor:** The operator checks status. **System:** The service returns the latest confirmed job outcome.
9. **System (creation timing):** On `succeeded`, the service creates the `Pose` (`poseId` stable, `status=local`) with the submitted metadata and the three media roles (`original`, `skeleton`, `thumbnail`) materialized (`201`), matching the mobile path; its public DTO/view is `CommunityPose` over `status=published`.

### Alternative flows

- **A1 — Retryable failure.** Source step: 6. Condition: attempts remain. Behavior: requeue the job. Resume at step: 6.
- **A2 — Manual retry (mobile).** Source step: 4. Condition: the local job is `failed` and the Mobile user chooses Retry. Behavior: the app re-enqueues a new server job through FEAT-004 and attaches it to the same local job record or Pose; no automatic retry occurs. Resume at step: 3.

### Exception flows

- **E1 — Queue/metadata failure.** Source step: 6. Failure: one write fails. Handling: return the documented error and retain evidence for reconciliation. Prohibited: claiming a ready guide or a Pose before the job is `succeeded`.
- **E2 — Worker failure.** Source step: 7. Failure: provider/browser processing fails. Handling: record error or requeue according to current store logic. Prohibited: claiming public readiness.
- **E3 — Extraction failure (mobile, no auto-retry).** Source step: 4. Failure: the server job reaches `failed`. Handling: the Jobs screen shows the failure details and an explicit manual Retry action; the local record keeps `failed` and the error. Prohibited: silently auto-retrying or claiming a Pose.

### Postconditions

- **Success:** On the mobile path, a local `Pose` (`status=local`) is created **after** the server job reports `succeeded` (`202` job start never creates a Pose) with the submitted metadata and the **three media roles materialized (post-extraction): `original`, `skeleton`, `thumbnail`**, and the local job record links to it; on the admin path, only the observed job status is confirmed, and the Pose is created the same way (post-`succeeded`, `201`).
- **Failure:** The failed job remains inspectable on the local Jobs screen with a manual Retry (mobile) or the last confirmed job/pose state remains inspectable (admin).

### Current evidence

- **Observed:** Server `CommunityPose` (published-`Pose` view/DTO), `ExtractionJob`, API-key records, admin
  community intake/listing, worker processing, job status, and key CRUD/status/reset.
- **Observed (mobile legacy):** Mobile `PoseApiService.extractPose` calls the
  synchronous `POST /api/extract-pose` and decodes `data.imageBase64`; local
  persistence uses a `Pose` local table; `PosesScreen` exposes an extract control.
  No dedicated Extract or Jobs screen and no device-local extraction-job table exist yet.
- **Inferred:** A dedicated Extract screen, a dedicated local Jobs screen, and a
  device-only local job record are the intended mobile path. Per-field status:
  - local id — **Inferred** (no device table exists yet)
  - server `jobId` — **Observed** at the server API (`202` + `jobId`), **Inferred** for device storage
  - status (`queued | processing | succeeded | failed`) — **Observed** at the server API (BR-JOB-001), **Inferred** for the device mirror
  - timestamps — **Inferred**
  - error when `failed` — **Observed** at the server error envelope, **Inferred** for the device mirror
  - Pose link when `succeeded` — **Inferred**
- **Unresolved (TBD):** The storage shape for the device-local job record is not yet
  implemented; the canonical Pose field set is fixed by
  [`pose.md`](../../spec/data/entities/pose.md).
- **Planned:** [Plan 260816-2240](../plans/260816-2240-higgsfield-cli-parallel-extract-provider/plan.md)
  routes the same `ExtractionJob` worker through `PoseExtractorProvider`; community
  intake enqueue shape (`202` + `jobId`) is unchanged; engine follows global FEAT-009
  setting at claim time.
- **Not observed:** A dedicated pose-guide owner/version/notes model, guide CRUD,
  re-extraction/revert routes, durable job-to-pose link, or asset readiness state.
- **Primary blocker:** Worker stores generated base64 on `ExtractionJob` only;
  no repository evidence proves the `Pose` → skeleton [`MediaAsset`](../../spec/data/entities/media-asset.md) publication.
- **Historical evidence:** [REP-004](../reports/REP-004-backend-feature-and-model-entity-scout.md)
  and [REP-002 GAP-001/GAP-006/GAP-007](../reports/REP-002-feature-gap-and-release-readiness-audit.md#prioritized-backlog)
  preserve the detailed findings.

### Traceability

| Concern | Canonical reference | Evidence |
| --- | --- | --- |
| Entities | [`Pose`](../../spec/data/entities/pose.md), [`CommunityPose`](../../spec/data/entities/community-pose.md) (published view/DTO), [`ExtractionJob`](../../spec/data/entities/extraction-job.md), [`MediaAsset`](../../spec/data/entities/media-asset.md), [`Account`](../../spec/data/entities/account.md), [`ApiKeyCredential`](../../spec/data/entities/api-key-credential.md) | [`communityStore.ts`](../../../web/services/pose-extract-server/src/db/communityStore.ts), [`schema.sql`](../../../web/services/pose-extract-server/src/db/schema.sql) |
| ERD | [Server physical graph](../../spec/data/erd/server.md), [unresolved cross-feature links](../../spec/data/erd/conceptual.md) | [`job-processor.ts`](../../../web/services/pose-extract-server/src/worker/job-processor.ts) |
| APIs | [Guides](../../spec/api/modules/guides.md), [admin keys](../../spec/api/modules/admin-keys.md), [admin community](../../spec/api/modules/admin-community.md), [admin jobs](../../spec/api/modules/admin-jobs.md) | [`adminCommunityRoutes.ts`](../../../web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts), [`jobStatusRoutes.ts`](../../../web/services/pose-extract-server/src/routes/jobStatusRoutes.ts) |
| Supporting evidence | Backend scout and readiness audit | [`REP-004`](../reports/REP-004-backend-feature-and-model-entity-scout.md), [`REP-002`](../reports/REP-002-feature-gap-and-release-readiness-audit.md) |
| Mobile personal path | Dedicated Extract screen, local Jobs screen, device-local job record | [`PoseApiService.kt`](../../../mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt), [`Pose.sq`](../../../mobile/shared/src/commonMain/sqldelight/com/aipose/Pose.sq), [`PosesScreen.kt`](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PosesScreen.kt), [extraction screen UX line](../specs/ui-ux-system.md) |

## Requirements

- **FR-001:** A `202` submission is documented as queued acceptance, not readiness.
- **FR-002:** Job state uses the shared observed values and API-013 shape.
- **FR-003:** A Mobile user creates a personal Pose through a dedicated Extract screen that collects the canonical fields — name, tags, and at least one bodyPart (required); description and difficulty (optional); **`ownerAccountId` (taken from the signed-in session — mandatory on every `Pose`)** — and reads the source image from the existing camera ([FEAT-001](FEAT-001-capture-a-photo-on-mobile.md)) or local-library ([FEAT-002](FEAT-002-manage-a-local-photo-gallery.md)) entry points.
- **FR-004:** Submission persists a device-only local job record (local id, server `jobId`, status, timestamps, error when failed, Pose link when succeeded) and polls `GET /api/extract-jobs/:jobId`; there is no job-list API.
- **FR-005:** A dedicated local Jobs screen shows current-device jobs with status, outcome, and failure details, and offers an explicit manual Retry on failure with no automatic retry.
- **BR-001:** No guide is public until a durable asset/readiness relationship is proven; no `Pose` is persisted before the extraction job is `succeeded`.
- **BR-002:** Mobile extraction does not own the CameraScreen business flow; it only reuses image source entry points.

## Acceptance

- [ ] Submission returns **`202 Accepted` queued job (`jobId`)**; the Pose is created only after the job is `succeeded` (`201`).
- [ ] Job status distinguishes queued, processing, succeeded, and failed.
- [ ] Owner, media assets, and job-to-pose links follow [`Pose`](../../spec/data/entities/pose.md).
- [ ] Mobile Extract screen creates a local `Pose` with name, tags, bodyParts, and source image on success.
- [ ] Mobile Jobs screen lists device-local jobs with status and failure details and offers manual retry only (no automatic retry).
- [ ] Mobile polls the per-job endpoint and requires no job-list API.

## Relationships

- Shared references: [CommunityPose](../../spec/data/entities/community-pose.md) (published view/DTO), [ERD conceptual](../../spec/data/erd/conceptual.md), [Admin API](../../spec/api/README.md).
- Related features: [FEAT-004](FEAT-004-extract-reusable-pose-images.md), [FEAT-006](FEAT-006-publish-a-pose.md).
- Mobile extraction reuses image source entry points from [FEAT-001](FEAT-001-capture-a-photo-on-mobile.md) and [FEAT-002](FEAT-002-manage-a-local-photo-gallery.md) without owning camera behavior.
### Supporting evidence

- [`communityStore.ts`](../../../web/services/pose-extract-server/src/db/communityStore.ts)
- [`extractionJobStore.ts`](../../../web/services/pose-extract-server/src/db/extractionJobStore.ts)
- [`job-processor.ts`](../../../web/services/pose-extract-server/src/worker/job-processor.ts)
- [`adminCommunityRoutes.ts`](../../../web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts)
- [`REP-004`](../reports/REP-004-backend-feature-and-model-entity-scout.md)
