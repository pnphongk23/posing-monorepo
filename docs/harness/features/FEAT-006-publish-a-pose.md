---
schema_version: 1
type: feature
id: FEAT-006
title: Publish a Pose
status: draft
created: 2026-08-15
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
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
    - "[[FEAT-008-use-published-poses|FEAT-008]]"
  source_paths:
    - web/services/pose-extract-server/src/db/schema.sql
    - web/services/pose-extract-server/src/routes/communityRoutes.ts
    - web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts
---

# FEAT-006: Publish a Pose

## Introduction

The Pose Owner controls whether a complete, usable pose is publicly discoverable.
Public browsing consumes this decision through [FEAT-003](FEAT-003-browse-and-search-published-poses.md);
guide completeness comes from [FEAT-005](FEAT-005-manage-a-pose-guide.md).

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Pose Owner | Business role | Make a complete guide public | Confirm eligibility and visibility |
| Public catalogue | External consumer | Serve published content | Return only confirmed public records |

### Preconditions

- A pose is complete and has a usable skeleton asset; current implementation does not prove this relation.

### Trigger

The owner requests publication or removal from public discovery.

### Main flow

1. **Actor:** The owner requests publication. **System:** The system verifies eligibility and owner authority.
2. **System:** The system records the visibility transition. **System:** Public list/detail expose only confirmed published records.

### Alternative flows

- **A1 — Keep local.** Source step: 1. Condition: eligibility is not confirmed. Behavior: retain `local` state (legacy `draft` alias). Ends with: non-public pose.

### Exception flows

- **E1 — Asset not ready.** Source step: 1. Failure: skeleton/readiness cannot be confirmed. Handling: reject or defer publication. Prohibited: exposing an unready asset publicly.
- **E2 — Owner/auth unknown.** Source step: 1. Failure: authority cannot be verified. Handling: keep the last confirmed visibility. Prohibited: claiming an authorized transition.

### Postconditions

- **Success:** A confirmed visibility state is available to public browsing.
- **Failure:** The pose remains non-public and the last confirmed state is retained.

### Current evidence

- **Observed:** `status: local → published` là thuộc tính của canonical [`Pose`](../../spec/data/entities/pose.md)
  (`local` nhận legacy `draft` alias; `published` là trạng thái catalogue). Public
  list/detail (`CommunityPose` DTO) chỉ lọc `published`; **admin đọc canonical
  `Pose`**, không đọc DTO.
- **Not observed:** owner identity/authorization, an explicit publication update
  or unpublish endpoint, a readiness gate, or deletion propagation to Saved entries.
- **Evidence gap:** `202 Accepted` and a `published` row do not prove the generated
  asset was uploaded or linked. See [REP-004 publication findings](../reports/REP-004-backend-feature-and-model-entity-scout.md#architecture-and-flows).

### Traceability

| Concern | Canonical reference | Evidence |
| --- | --- | --- |
| Entities | [`CommunityPose`](../../spec/data/entities/community-pose.md) (published view/DTO), [`MediaAsset`](../../spec/data/entities/media-asset.md), [`Pose`](../../spec/data/entities/pose.md), [`Account`](../../spec/data/entities/account.md) | [`schema.sql`](../../../web/services/pose-extract-server/src/db/schema.sql), [`communityStore.ts`](../../../web/services/pose-extract-server/src/db/communityStore.ts) |
| ERD | [Server graph](../../spec/data/erd/server.md), [unresolved asset/readiness links](../../spec/data/erd/conceptual.md) | [`adminCommunityRoutes.ts`](../../../web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts) |
| APIs | [Public community](../../spec/api/modules/community.md), [publish](../../spec/api/modules/publish.md), [admin intake](../../spec/api/modules/admin-community.md) | [`communityRoutes.ts`](../../../web/services/pose-extract-server/src/routes/communityRoutes.ts), [`adminCommunityRoutes.ts`](../../../web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts) |
| Supporting evidence | Backend reports and feature inventory | [`REP-002`](../reports/REP-002-feature-gap-and-release-readiness-audit.md), [`REP-004`](../reports/REP-004-backend-feature-and-model-entity-scout.md) |

## Requirements

- **FR-001:** Public reads use the shared `CommunityPose` (published-`Pose` view) status contract.
- **FR-002:** Owner or Admin publishes/unpublishes through [`publish.md`](../../spec/api/modules/publish.md); readiness requires a `ready` skeleton [`MediaAsset`](../../spec/data/entities/media-asset.md).
- **BR-001:** `published` requires a readable ready skeleton; queued `202` is not publication.

## Acceptance

- [ ] Public list/detail return only current published records.
- [ ] Local/unready/unauthorized transitions are not claimed as success.
- [ ] Unpublish is `POST /api/guides/:id/unpublish`.

## Relationships

- Shared references: [CommunityPose](../../spec/data/entities/community-pose.md) (published view/DTO), [ERD conceptual](../../spec/data/erd/conceptual.md), [Community API](../../spec/api/modules/community.md).
- Related features: [FEAT-003](FEAT-003-browse-and-search-published-poses.md), [FEAT-005](FEAT-005-manage-a-pose-guide.md), [FEAT-008](FEAT-008-use-published-poses.md).
### Supporting evidence

- [`schema.sql`](../../../web/services/pose-extract-server/src/db/schema.sql)
- [`communityRoutes.ts`](../../../web/services/pose-extract-server/src/routes/communityRoutes.ts)
- [`adminCommunityRoutes.ts`](../../../web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts)
- [`REP-004`](../reports/REP-004-backend-feature-and-model-entity-scout.md)
