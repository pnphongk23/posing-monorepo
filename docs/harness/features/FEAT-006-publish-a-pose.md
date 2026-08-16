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

- A pose guide is complete and has a usable render asset; current implementation does not prove this relation.

### Trigger

The owner requests publication or removal from public discovery.

### Main flow

1. **Actor:** The owner requests publication. **System:** The system verifies eligibility and owner authority.
2. **System:** The system records the visibility transition. **System:** Public list/detail expose only confirmed published records.

### Alternative flows

- **A1 — Keep draft.** Source step: 1. Condition: eligibility is not confirmed. Behavior: retain draft state. Ends with: non-public pose.

### Exception flows

- **E1 — Asset not ready.** Source step: 1. Failure: render/readiness cannot be confirmed. Handling: reject or defer publication. Prohibited: exposing an unready asset publicly.
- **E2 — Owner/auth unknown.** Source step: 1. Failure: authority cannot be verified. Handling: keep the last confirmed visibility. Prohibited: claiming an authorized transition.

### Postconditions

- **Success:** A confirmed visibility state is available to public browsing.
- **Failure:** The pose remains non-public and the last confirmed state is retained.

### Current evidence

- **Observed:** `CommunityPose.status` is constrained to `draft|published`;
  admin multipart intake accepts either value; public list/detail routes filter
  to `published`.
- **Not observed:** owner identity/authorization, an explicit publication update
  or unpublish endpoint, a readiness gate, or deletion propagation to Saved entries.
- **Evidence gap:** `202 Accepted` and a `published` row do not prove the generated
  asset was uploaded or linked. See [REP-004 publication findings](../reports/REP-004-backend-feature-and-model-entity-scout.md#architecture-and-flows).

### Traceability

| Concern | Canonical reference | Evidence |
| --- | --- | --- |
| Entities | [`CommunityPose`](../../data/entities/community-pose.md), [MediaAsset TBD](../../data/domain-model.md), [PoseGuide TBD](../../data/domain-model.md) | [`schema.sql`](../../../web/services/pose-extract-server/src/db/schema.sql), [`communityStore.ts`](../../../web/services/pose-extract-server/src/db/communityStore.ts) |
| ERD | [Server graph](../../data/erd/server.md), [unresolved asset/readiness links](../../data/erd/conceptual.md) | [`adminCommunityRoutes.ts`](../../../web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts) |
| APIs | [Public community](../../api/modules/community.md), [admin intake](../../api/modules/admin-community.md) | [`communityRoutes.ts`](../../../web/services/pose-extract-server/src/routes/communityRoutes.ts), [`adminCommunityRoutes.ts`](../../../web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts) |
| Supporting evidence | Backend reports and feature inventory | [`REP-002`](../reports/REP-002-feature-gap-and-release-readiness-audit.md), [`REP-004`](../reports/REP-004-backend-feature-and-model-entity-scout.md) |

## Requirements

- **FR-001:** Public reads use the shared `CommunityPose.status` contract.
- **FR-002:** Owner authorization, unpublish, and readiness are TBD until implemented evidence exists.
- **BR-001:** `published` must not be equated with a verified uploaded asset.

## Acceptance

- [ ] Public list/detail return only current published records.
- [ ] Draft/unready/unauthorized transitions are not claimed as success.
- [ ] Unpublish/update API absence is recorded in the API catalogue.

## Relationships

- Shared references: [CommunityPose](../../data/entities/community-pose.md), [ERD conceptual](../../data/erd/conceptual.md), [Community API](../../api/modules/community.md).
- Related features: [FEAT-003](FEAT-003-browse-and-search-published-poses.md), [FEAT-005](FEAT-005-manage-a-pose-guide.md), [FEAT-008](FEAT-008-use-published-poses.md).
### Supporting evidence

- [`schema.sql`](../../../web/services/pose-extract-server/src/db/schema.sql)
- [`communityRoutes.ts`](../../../web/services/pose-extract-server/src/routes/communityRoutes.ts)
- [`adminCommunityRoutes.ts`](../../../web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts)
- [`REP-004`](../reports/REP-004-backend-feature-and-model-entity-scout.md)
