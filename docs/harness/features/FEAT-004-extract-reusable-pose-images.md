---
schema_version: 1
title: Extract Reusable Pose Images
relationships:
  specs:
    - "[[product-feature-inventory]]"
    - "[[technical-architecture]]"
    - "[[ui-ux-system]]"
    - "[[model-entity-catalogue]]"
    - "[[erd]]"
    - "[[api-catalogue]]"
  decisions:
    - "[[DEC-001-extraction-provider-selection-policy|DEC-001]]"
  plans:
    - "[[260816-2240-higgsfield-cli-parallel-extract-provider/plan|260816-2240]]"
  reports:
    - "[[REP-002-feature-gap-and-release-readiness-audit|REP-002]]"
    - "[[REP-004-backend-feature-and-model-entity-scout|REP-004]]"
  rules: []
  features:
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
    - "[[FEAT-007-operate-pose-content-from-admin-web|FEAT-007]]"
    - "[[FEAT-009-configure-extraction-provider|FEAT-009]]"
  source_paths:
    - web/services/pose-extract-server/src/routes/extractPoseRoutes.ts
    - web/services/pose-extract-server/src/services/geminiService.ts
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PosesScreen.kt
type: feature
id: FEAT-004
status: approved
created: 2026-08-09
approved: 2026-08-17
approved_by: Product Authority
---

# FEAT-004: Extract Reusable Pose Images

## Introduction

One source image is validated and sent through an extraction provider to produce
one reusable skeleton (the extraction output). The common request/result contract is owned here;
guide metadata/ownership is [FEAT-005](FEAT-005-manage-a-pose-guide.md), the
Admin operating surface is [FEAT-007](FEAT-007-operate-pose-content-from-admin-web.md),
and global extraction-engine selection is owned by
[FEAT-009](FEAT-009-configure-extraction-provider.md) per
[DEC-001](../decisions/DEC-001-extraction-provider-selection-policy.md).
This Feature documents dual-engine **processing** and async job flow; it does
not own which engine is selected.

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Mobile user or Admin operator | User/business role | Produce one reusable pose skeleton | Submit one eligible source image |
| AI provider | External system | Return the skeleton | Process the source and report outcome |

### Preconditions

- One supported image is supplied through a client path.

### Trigger

The actor submits a source image for extraction.

### Main flow

1. **Actor:** The actor submits an image. **System:** The service validates the multipart payload and applies the direct-extraction limiter.
2. **System:** The service enqueues an `ExtractionJob` and returns `202 Accepted` with `jobId` and poll URL (phase 1 target per [Plan 260816-2240](../plans/260816-2240-higgsfield-cli-parallel-extract-provider/plan.md)).
3. **System:** The worker claims the job and invokes the globally configured engine (`gemini_native` or `higgsfield_cli`) via `PoseExtractorProvider` per [FEAT-009](FEAT-009-configure-extraction-provider.md) / [DEC-001](../decisions/DEC-001-extraction-provider-selection-policy.md).
4. **Actor:** The actor polls job status until `succeeded` or `failed`. For a mobile client this is the per-job endpoint `GET /api/extract-jobs/:jobId`; there is **no job-list API**. **System:** On success, returns the skeleton in job result; on failure, returns provider-neutral `error_code`.
5. **Postcondition (creation timing):** The job start does **not** create a `Pose` — no Pose is persisted before extraction success. On `succeeded`, the caller finalizes creation through `POST /api/guides` (owner) or admin intake, which returns `201 Created` with the `Pose` (`poseId` stable, `status: local`) and the three media roles (`original`, `skeleton`, `thumbnail`) materialized.

**Observed (pre-Plan):** Steps 2–4 are synchronous `200` inline base64 today; the mobile client expects a sync response. The server async contract is in scope; mobile async client migration is out of **Plan 260816-2240** work-item scope, but the Feature-level mobile async behavior (per-job polling, no list API) is documented here and in [FEAT-005](FEAT-005-manage-a-pose-guide.md), not deferred by that Plan's scope note.

### Alternative flows

- **A1 — Provider quota.** Source step: 2. Condition: the selected key is exhausted. Behavior: rotate to another active key when available. Resume at step: 2.

### Exception flows

- **E1 — Invalid/oversized image.** Source step: 1. Failure: validation rejects the upload. Handling: return the documented error envelope. Prohibited: invoking the provider.
- **E2 — Provider unavailable.** Source step: 2. Failure: no successful provider result. Handling: return a failed/retryable outcome. Prohibited: claiming a usable image.

### Postconditions

- **Success:** One skeleton response is returned; the `Pose` (stable `poseId`) is created **after** the job is `succeeded` via the Pose-creation contract (`201`), not at enqueue time; persistence belongs to the caller/pose flow.
- **Failure:** No usable result is claimed.

### Current evidence

- **Observed:** Direct Express extraction is synchronous; it accepts multipart
  image data, applies a process-local IP limiter, rotates active provider keys,
  logs requests, and returns base64 plus MIME and timing metadata.
- **Planned (draft):** [Plan 260816-2240](../plans/260816-2240-higgsfield-cli-parallel-extract-provider/plan.md)
  adds a second engine (`higgsfield_cli` via spawn-per-job CLI, model
  `gpt_image_2`) behind `PoseExtractorProvider`, unifies canonical extract with
  async `ExtractionJob` enqueue + poll (phase 1), and generalizes provider error
  codes. Processing uses the globally configured engine per
  [FEAT-009](FEAT-009-configure-extraction-provider.md) and
  [DEC-001](../decisions/DEC-001-extraction-provider-selection-policy.md);
  engine selection is not owned here. Mobile async client migration is out of
  that Plan's work-item scope, not out of Feature scope: the intended mobile
  async flow (per-job polling, no list API) is documented here and in FEAT-005.
- **Observed (legacy / non-canonical):** Mobile `PosesScreen` can pick an image,
  call the service via the synchronous client, and persist the result through
  local pose storage. This picker path is legacy and does not follow the
  canonical async job contract; the canonical mobile extraction entry point is
  the dedicated Extract screen owned by [FEAT-005](FEAT-005-manage-a-pose-guide.md).
- **Boundary:** Mobile extraction does not own the CameraScreen/FEAT-001 business
  flow; it reuses image source entry points (camera or local library) owned by
  [FEAT-001](FEAT-001-capture-a-photo-on-mobile.md)/[FEAT-002](FEAT-002-manage-a-local-photo-gallery.md).
- **Alternate path:** Admin Web also contains a legacy Replicate route. It is
  catalogued separately and is not silently treated as the canonical API-003 contract.
- **Gaps:** Content validation, cancellation/idempotency, retention, and error
  envelope parity remain documented in [REP-002](../reports/REP-002-feature-gap-and-release-readiness-audit.md).

### Traceability

| Concern | Canonical reference | Evidence |
| --- | --- | --- |
| Entities | [`ExtractionJob`](../../spec/data/entities/extraction-job.md), [`ApiKeyCredential`](../../spec/data/entities/api-key-credential.md), [`ProviderRequestLog`](../../spec/data/entities/provider-request-log.md) | [`schema.sql`](../../../web/services/pose-extract-server/src/db/schema.sql), [`KeyStore`](../../../web/services/pose-extract-server/src/services/keyStore.ts) |
| ERD | [Server physical graph](../../spec/data/erd/server.md) | [`ExtractionJobStore`](../../../web/services/pose-extract-server/src/db/extractionJobStore.ts) |
| APIs | [Direct extraction](../../spec/api/modules/extract-pose.md), [legacy route in conventions](../../spec/api/conventions.md) | [`extractPoseRoutes.ts`](../../../web/services/pose-extract-server/src/routes/extractPoseRoutes.ts), [`route.js`](../../../web/admin-ui/src/app/api/extract/route.js) |
| Supporting client | Mobile picker/service and proxy | [`PosesScreen.kt`](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PosesScreen.kt), [`poseExtractExtractPoseProxy.js`](../../../web/admin-ui/src/lib/poseExtractExtractPoseProxy.js) |

## Requirements

- **FR-001:** The canonical direct route returns one structured skeleton (async: via job poll when `succeeded`); the `Pose` is created only afterward (`201`), never at job start.
- **FR-002:** Direct and legacy extraction routes remain separately labelled until a Decision selects one path.
- **FR-003:** Canonical extract enqueues an `ExtractionJob` and returns `202` with `jobId` (phase 1); worker processes via `PoseExtractorProvider` using the globally configured engine per FEAT-009/DEC-001.
- **FR-004:** Supported engines: `gemini_native` (REST + key pool) and `higgsfield_cli` (spawn-per-job CLI, model `gpt_image_2`).
- **BR-001:** A failed or unverified provider result must not be reported as usable.
- **FR-005:** A mobile client polls the per-job endpoint `GET /api/extract-jobs/:jobId` until `succeeded` or `failed`; there is no job-list API.
- **BR-002:** Engine selection is not owned here; processing consumes the global setting from FEAT-009.
- **BR-003:** Mobile extraction does not own the CameraScreen business flow ([FEAT-001](FEAT-001-capture-a-photo-on-mobile.md)); it reuses image source entry points only.

## Acceptance

- [ ] Valid direct extraction returns the API-003 shape (`202` + `jobId`, poll; Pose created only on `succeeded`).
- [ ] Invalid/oversized requests return documented errors.
- [ ] Quota exhaustion and provider failures remain recoverable or explicit.
- [ ] Mobile polling uses the per-job endpoint only and requires no job-list API.

## Relationships

- Shared references: [ExtractionJob](../../spec/data/entities/extraction-job.md), [ERD server](../../spec/data/erd/server.md), [Extract API](../../spec/api/modules/extract-pose.md).
- Related features: [FEAT-005](FEAT-005-manage-a-pose-guide.md), [FEAT-007](FEAT-007-operate-pose-content-from-admin-web.md), [FEAT-009](FEAT-009-configure-extraction-provider.md) (global engine selection; this Feature consumes configured engine for processing).
- Policy: [DEC-001 Extraction provider selection policy](../decisions/DEC-001-extraction-provider-selection-policy.md)
### Supporting evidence

- [`extractPoseRoutes.ts`](../../../web/services/pose-extract-server/src/routes/extractPoseRoutes.ts)
- [`geminiService.ts`](../../../web/services/pose-extract-server/src/services/geminiService.ts)
- [`extractPose.test.ts`](../../../web/services/pose-extract-server/src/extractPose.test.ts)
- [`PoseApiService.kt`](../../../mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt)
- [`REP-002`](../reports/REP-002-feature-gap-and-release-readiness-audit.md)
