---
schema_version: 1
type: spec
title: Product Feature Inventory
status: draft
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[ui-ux-system]]"
    - "[[model-entity-catalogue]]"
    - "[[erd]]"
    - "[[api-catalogue]]"
    - "[[product-delivery-roadmap]]"
  decisions: []
  plans: []
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
    - "[[FEAT-009-configure-extraction-provider|FEAT-009]]"
  source_paths: []
---

# Product Feature Inventory

## Scope

This inventory is a business-feature map. It records each Feature's observable boundary and ownership; implementation delivery, code parity, Plans, and runtime gaps are intentionally outside this inventory.

The landing-level traceability map is in the [Harness README](../README.md).
Shared model/entity, ERD, and API definitions are maintained once in
[docs/spec](./data-contract.md)
([data](data-contract.md), [api](api-contract.md));
Feature pages link to those entries instead of duplicating them.
Harness stubs remain at [model catalogue](./model-entity-catalogue.md),
[global ERD](./erd.md), and [API catalogue](./api-catalogue.md) for wikilink compatibility.

## Current feature inventory

| Feature | Business capability | Primary actor or owner | Boundary |
| --- | --- | --- | --- |
| [[FEAT-001-capture-a-photo-on-mobile\|FEAT-001]] | Capture a photo on mobile | Photographer | Capture a source photo for later use; pose extraction is FEAT-004. |
| [[FEAT-002-manage-a-local-photo-gallery\|FEAT-002]] | Manage a local photo gallery | Photographer | Organize personal photos; pose management is FEAT-005. |
| [[FEAT-003-browse-and-search-published-poses\|FEAT-003]] | Browse and search published poses | Visitor or signed-in user | Browse, search, inspect, refresh, and recover the public catalogue; no Save, Try Pose, extraction, or publication. |
| [[FEAT-004-extract-reusable-pose-images\|FEAT-004]] | Extract one reusable pose image | Signed-in user or Admin operator | One common extraction contract and ownership assignment for both creator roles. |
| [[FEAT-005-manage-a-pose-guide\|FEAT-005]] | Manage a pose guide | Pose Owner | My Poses, pose metadata, re-extraction, retry, revert, and terminal deletion around a FEAT-004 result. |
| [[FEAT-006-publish-a-pose\|FEAT-006]] | Publish or unpublish a pose | Pose Owner | Public-data acknowledgement, publication eligibility, and confirmed public visibility lifecycle. |
| [[FEAT-007-operate-pose-content-from-admin-web\|FEAT-007]] | Operate pose content from Admin Web | Admin operator | Admin surface for intake, status, ownership, pose management in FEAT-005, and invoking FEAT-004 and FEAT-006; no alternate extraction or publication model. |
| [[FEAT-008-use-published-poses\|FEAT-008]] | Use published poses | Signed-in user | Save, Unsave, Saved collection, Try Pose, camera guide lifecycle, and consequences of publication removal. |
| [[FEAT-009-configure-extraction-provider\|FEAT-009]] | Configure extraction provider | Admin operator | Select and persist the global extraction engine (Gemini native or Higgsfield CLI) for extract jobs; timing, default, and credential policy in DEC-001. |

## Supporting surfaces

- FEAT-003 consumes the public visibility established by FEAT-006.
- FEAT-008 consumes the published poses discovered through FEAT-003 and does not change ownership.
- FEAT-007 is an operating surface for Admin-owned pose content; Admin-created poses follow the same extraction, ownership, guide, and publication boundaries as other poses.
- FEAT-009 owns global extraction engine configuration; FEAT-007 invokes FEAT-009 through Admin Web without redefining extract or provider policy.

## Documentation rules

- Each observable behavior has one owning Feature.
- A Feature may invoke another Feature's behavior but must not redefine its contract.
- Feature documents describe business actors, flows, requirements, and acceptance; implementation design and delivery status belong elsewhere.
- When a business boundary changes, update the owning Features and this inventory together.

## Verification

- Validate the Feature documents with `ckh validate --kind feature --workspace .`.
- Check each Feature workflow state with `ckh workflow check TARGET --workspace .`.
- Check outgoing Feature and Spec relationships with `ckh graph check --workspace .` after rebuilding the index.
