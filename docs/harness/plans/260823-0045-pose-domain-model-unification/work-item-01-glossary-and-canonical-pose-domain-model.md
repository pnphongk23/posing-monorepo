---
work_item: 1
title: Glossary and canonical Pose domain model
status: completed
priority: P1
effort: M
dependencies: []
decision_dependencies: []
---

# Work Item 1: Glossary and canonical Pose domain model

## Tasks

1. Create the canonical glossary at
   `docs/harness/specs/pose-domain-glossary.md`: a numbered hierarchical
   glossary explaining the Pose domain model, the canonical `Pose` entity
   definition and **creation timing (created only after extraction succeeds;
   `jobId` correlation → stable `poseId`)**, mandatory `ownerAccountId`, the
   three media roles (non-nullable, materialized at creation), the lifecycle
   states (`local` → `published`), the ID strategy, and the terminology
   migration map.
2. Create the canonical single-entity spec `docs/harness/specs/data-contract.md#pose`
   with stable `poseId`, mandatory `ownerAccountId`, three non-nullable
   media-role references (`originalMediaId`, `skeletonMediaId`,
   `thumbnailMediaId`), `PoseStatus` (`local` | `published`), post-extraction
   creation business rules (BR-POSE-001, BR-POSE-008, BR-POSE-009), and
   business rules.
3. Update `docs/harness/README.md` canonical references to link the glossary
   (preserving the existing product-delivery-roadmap addition).

## Scope and affected files

- `docs/harness/specs/pose-domain-glossary.md` (new)
- `docs/harness/specs/data-contract.md#pose` (new)
- `docs/harness/README.md` (link addition only)

## Success criteria

- Glossary enumerates one canonical `Pose` entity, `poseId`/`mediaId` IDs, the
  three media roles (`original`, `skeleton`, `thumbnail`), the `local` →
  `published` lifecycle, creation-after-extraction timing, mandatory
  `ownerAccountId`, and a complete legacy→canonical terminology map.
- `pose.md` is the authoritative single-entity Pose spec.

## Risks

- Terminology drift across the many consumer documents — mitigated by placing
  the canonical map in the glossary and applying it uniformly in WI-02/03/04.

## Required evidence

- `docs/harness/specs/pose-domain-glossary.md` exists and is internally
  consistent; `docs/harness/specs/data-contract.md#pose` exists.