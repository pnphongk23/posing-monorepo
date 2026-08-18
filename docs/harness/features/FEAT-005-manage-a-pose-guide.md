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
type: feature
id: FEAT-005
status: approved
created: 2026-08-09
approved: 2026-08-17
approved_by: Product Authority
---

# FEAT-005: Manage a Pose Guide

## Introduction

The Pose Guide Owner manages guide metadata and the lifecycle around an extracted
pose. This is the business owner for guide state, but it must reuse
[FEAT-004](FEAT-004-extract-reusable-pose-images.md)'s extraction contract and
[FEAT-006](FEAT-006-publish-a-pose.md)'s publication boundary. The current
implementation only partially realizes this aggregate.

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Pose Guide Owner | Business role | Maintain one reusable guide lifecycle | Review metadata and extraction outcomes |
| Admin operator/worker | Business role/external process | Operate queued community work | Submit, process, and inspect jobs |

### Preconditions

- A guide submission has eligible source metadata and an extraction path.

### Trigger

The owner or operator submits, inspects, retries, or manages a guide.

### Main flow

1. **Actor:** The operator submits community metadata and an image. **System:** The service creates a `CommunityPose` and queues an `ExtractionJob`.
2. **System:** The worker claims and processes the job. **System:** The job becomes queued, processing, succeeded, or failed according to observed store transitions.
3. **Actor:** The operator checks status. **System:** The service returns the latest confirmed job outcome.

### Alternative flows

- **A1 — Retryable failure.** Source step: 2. Condition: attempts remain. Behavior: requeue the job. Resume at step: 2.

### Exception flows

- **E1 — Queue/metadata failure.** Source step: 1. Failure: one write fails. Handling: return the documented error and retain evidence for reconciliation. Prohibited: claiming a ready guide.
- **E2 — Worker failure.** Source step: 2. Failure: provider/browser processing fails. Handling: record error or requeue according to current store logic. Prohibited: claiming public readiness.

### Postconditions

- **Success:** Only the observed job status is confirmed; guide/asset readiness remains separate.
- **Failure:** The last confirmed job/pose state remains inspectable.

### Current evidence

- **Observed:** Server `CommunityPose`, `ExtractionJob`, API-key records, admin
  community intake/listing, worker processing, job status, and key CRUD/status/reset.
- **Planned:** [Plan 260816-2240](../../plans/260816-2240-higgsfield-cli-parallel-extract-provider/plan.md)
  routes the same `ExtractionJob` worker through `PoseExtractorProvider`; community
  intake enqueue shape (`202` + `jobId`) is unchanged; engine follows global FEAT-009
  setting at claim time.
- **Not observed:** A dedicated pose-guide owner/version/notes model, guide CRUD,
  re-extraction/revert routes, durable job-to-pose link, or asset readiness state.
- **Primary blocker:** Worker stores generated base64 on `ExtractionJob` only;
  no repository evidence proves `CommunityPose → MediaAsset` publication.
- **Historical evidence:** [REP-004](../reports/REP-004-backend-feature-and-model-entity-scout.md)
  and [REP-002 GAP-001/GAP-006/GAP-007](../reports/REP-002-feature-gap-and-release-readiness-audit.md#prioritized-backlog)
  preserve the detailed findings.

### Traceability

| Concern | Canonical reference | Evidence |
| --- | --- | --- |
| Entities | [`PoseGuide`](../../spec/data/entities/pose-guide.md), [`CommunityPose`](../../spec/data/entities/community-pose.md), [`ExtractionJob`](../../spec/data/entities/extraction-job.md), [`MediaAsset`](../../spec/data/entities/media-asset.md), [`ApiKeyCredential`](../../spec/data/entities/api-key-credential.md) | [`communityStore.ts`](../../../web/services/pose-extract-server/src/db/communityStore.ts), [`schema.sql`](../../../web/services/pose-extract-server/src/db/schema.sql) |
| ERD | [Server physical graph](../../spec/data/erd/server.md), [unresolved cross-feature links](../../spec/data/erd/conceptual.md) | [`job-processor.ts`](../../../web/services/pose-extract-server/src/worker/job-processor.ts) |
| APIs | [Guides](../../spec/api/modules/guides.md), [admin keys](../../spec/api/modules/admin-keys.md), [admin community](../../spec/api/modules/admin-community.md), [admin jobs](../../spec/api/modules/admin-jobs.md) | [`adminCommunityRoutes.ts`](../../../web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts), [`jobStatusRoutes.ts`](../../../web/services/pose-extract-server/src/routes/jobStatusRoutes.ts) |
| Supporting evidence | Backend scout and readiness audit | [`REP-004`](../reports/REP-004-backend-feature-and-model-entity-scout.md), [`REP-002`](../reports/REP-002-feature-gap-and-release-readiness-audit.md) |

## Requirements

- **FR-001:** A `202` submission is documented as queued acceptance, not readiness.
- **FR-002:** Job state uses the shared observed values and API-013 shape.
- **BR-001:** No guide is public until a durable asset/readiness relationship is proven.

## Acceptance

- [ ] Submission returns one queued job and community record shape.
- [ ] Job status distinguishes queued, processing, succeeded, and failed.
- [ ] Owner, media assets, and job-to-guide links follow [`PoseGuide`](../../spec/data/entities/pose-guide.md).

## Relationships

- Shared references: [CommunityPose](../../spec/data/entities/community-pose.md), [ERD conceptual](../../spec/data/erd/conceptual.md), [Admin API](../../spec/api/README.md).
- Related features: [FEAT-004](FEAT-004-extract-reusable-pose-images.md), [FEAT-006](FEAT-006-publish-a-pose.md).
### Supporting evidence

- [`communityStore.ts`](../../../web/services/pose-extract-server/src/db/communityStore.ts)
- [`extractionJobStore.ts`](../../../web/services/pose-extract-server/src/db/extractionJobStore.ts)
- [`job-processor.ts`](../../../web/services/pose-extract-server/src/worker/job-processor.ts)
- [`adminCommunityRoutes.ts`](../../../web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts)
- [`REP-004`](../reports/REP-004-backend-feature-and-model-entity-scout.md)
