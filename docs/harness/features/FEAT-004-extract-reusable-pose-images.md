---
schema_version: 1
type: feature
id: FEAT-004
title: Extract Reusable Pose Images
status: draft
created: 2026-08-09
relationships:
  specs:
    - "[[product-feature-inventory]]"
    - "[[technical-architecture]]"
    - "[[ui-ux-system]]"
    - "[[model-entity-catalogue]]"
    - "[[erd]]"
    - "[[api-catalogue]]"
  decisions: []
  plans: []
  reports:
    - "[[REP-002-feature-gap-and-release-readiness-audit|REP-002]]"
    - "[[REP-004-backend-feature-and-model-entity-scout|REP-004]]"
  rules: []
  features:
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
    - "[[FEAT-007-operate-pose-content-from-admin-web|FEAT-007]]"
  source_paths:
    - web/services/pose-extract-server/src/routes/extractPoseRoutes.ts
    - web/services/pose-extract-server/src/services/geminiService.ts
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PosesScreen.kt
---

# FEAT-004: Extract Reusable Pose Images

## Introduction

One source image is validated and sent through an extraction provider to produce
one reusable image result. The common request/result contract is owned here;
guide metadata/ownership is [FEAT-005](FEAT-005-manage-a-pose-guide.md), and the
Admin operating surface is [FEAT-007](FEAT-007-operate-pose-content-from-admin-web.md).

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Mobile user or Admin operator | User/business role | Produce one reusable pose image | Submit one eligible source image |
| AI provider | External system | Return an extracted image | Process the source and report outcome |

### Preconditions

- One supported image is supplied through a client path.

### Trigger

The actor submits a source image for extraction.

### Main flow

1. **Actor:** The actor submits an image. **System:** The service validates the multipart payload and applies the direct-extraction limiter.
2. **System:** The provider is invoked with an active credential. **System:** The service records usage and returns the extracted image result.

### Alternative flows

- **A1 — Provider quota.** Source step: 2. Condition: the selected key is exhausted. Behavior: rotate to another active key when available. Resume at step: 2.

### Exception flows

- **E1 — Invalid/oversized image.** Source step: 1. Failure: validation rejects the upload. Handling: return the documented error envelope. Prohibited: invoking the provider.
- **E2 — Provider unavailable.** Source step: 2. Failure: no successful provider result. Handling: return a failed/retryable outcome. Prohibited: claiming a usable image.

### Postconditions

- **Success:** One extracted image response is returned; persistence belongs to the caller/guide flow.
- **Failure:** No usable result is claimed.

### Current evidence

- **Observed:** Direct Express extraction is synchronous; it accepts multipart
  image data, applies a process-local IP limiter, rotates active provider keys,
  logs requests, and returns base64 plus MIME and timing metadata.
- **Observed:** Mobile `PosesScreen` can pick an image, call the service, and
  persist the result through local pose storage.
- **Alternate path:** Admin Web also contains a legacy Replicate route. It is
  catalogued separately and is not silently treated as the canonical API-003 contract.
- **Gaps:** Content validation, cancellation/idempotency, retention, and error
  envelope parity remain documented in [REP-002](../reports/REP-002-feature-gap-and-release-readiness-audit.md).

### Traceability

| Concern | Canonical reference | Evidence |
| --- | --- | --- |
| Entities | [`ExtractionJob`](../../data/entities/extraction-job.md), [`ApiKeyCredential`](../../data/entities/api-key-credential.md), [`ProviderRequestLog`](../../data/entities/provider-request-log.md) | [`schema.sql`](../../../web/services/pose-extract-server/src/db/schema.sql), [`KeyStore`](../../../web/services/pose-extract-server/src/services/keyStore.ts) |
| ERD | [Server physical graph](../../data/erd/server.md) | [`ExtractionJobStore`](../../../web/services/pose-extract-server/src/db/extractionJobStore.ts) |
| APIs | [Direct extraction](../../api/modules/extract-pose.md), [legacy route in conventions](../../api/conventions.md) | [`extractPoseRoutes.ts`](../../../web/services/pose-extract-server/src/routes/extractPoseRoutes.ts), [`route.js`](../../../web/admin-ui/src/app/api/extract/route.js) |
| Supporting client | Mobile picker/service and proxy | [`PosesScreen.kt`](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PosesScreen.kt), [`poseExtractExtractPoseProxy.js`](../../../web/admin-ui/src/lib/poseExtractExtractPoseProxy.js) |

## Requirements

- **FR-001:** The canonical direct route returns one structured extracted image result.
- **FR-002:** Direct and legacy extraction routes remain separately labelled until a Decision selects one path.
- **BR-001:** A failed or unverified provider result must not be reported as usable.

## Acceptance

- [ ] Valid direct extraction returns the API-003 shape.
- [ ] Invalid/oversized requests return documented errors.
- [ ] Quota exhaustion and provider failures remain recoverable or explicit.

## Relationships

- Shared references: [ExtractionJob](../../data/entities/extraction-job.md), [ERD server](../../data/erd/server.md), [Extract API](../../api/modules/extract-pose.md).
- Related features: [FEAT-005](FEAT-005-manage-a-pose-guide.md), [FEAT-007](FEAT-007-operate-pose-content-from-admin-web.md).
### Supporting evidence

- [`extractPoseRoutes.ts`](../../../web/services/pose-extract-server/src/routes/extractPoseRoutes.ts)
- [`geminiService.ts`](../../../web/services/pose-extract-server/src/services/geminiService.ts)
- [`extractPose.test.ts`](../../../web/services/pose-extract-server/src/extractPose.test.ts)
- [`PoseApiService.kt`](../../../mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt)
- [`REP-002`](../reports/REP-002-feature-gap-and-release-readiness-audit.md)
