---
work_item: 2
title: Data specs entities enums and ERD refactor
status: completed
priority: P1
effort: L
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 2: Data specs entities enums and ERD refactor

## Tasks

1. Refactor `docs/harness/specs/data-contract.md#domain-model`: single `Pose` entity, three media
   roles, `local` → `published` lifecycle, public catalogue as view/DTO, and
   creation timing (Pose created only after extraction `succeeded`; `jobId`
   during extraction, `poseId` after).
2. Refactor `docs/harness/specs/data-contract.md#enums`: `PoseStatus` (`local` | `published`;
   `draft` deprecated alias), `MediaAssetRole` (`original` | `skeleton` |
   `thumbnail`).
3. Update entity files: `pose.md` (canonical, from WI-01; post-extraction
   creation, mandatory `ownerAccountId`, three non-nullable media slots),
   `media-asset.md` (`mediaId`, `poseId`, roles
   `original`/`skeleton`/`thumbnail`; three media materialized at creation),
   `photo.md`, `extraction-job.md` (`jobId` PK / correlation key; `poseId`
   nullable until pose created; `skeletonMediaId`), `saved-entry.md`,
   `prepared-pose-reference.md` (`skeletonLocator`). Update `account.md`
   (mandatory `ownerAccountId`; admin actor vs owner).
4. Update `pose-guide.md`, `community-pose.md`, `personal-pose.md`,
   `pose-reference-key.md` to document the transition to the single canonical
   `Pose` entity / DTO / deprecation.
5. Update `docs/harness/specs/data-contract.md` `conceptual.md`, `mobile.md`, `server.md`,
   `README.md` to align with single `Pose` entity and three media roles.
6. Update `docs/harness/specs/data-contract.md` entity classification and `CHANGELOG.md`.

## Scope and affected files

- `docs/harness/specs/data-contract.md#domain-model`
- `docs/harness/specs/data-contract.md#enums`
- `docs/harness/specs/data-contract.md`, `docs/harness/specs/data-contract.md`
- `docs/harness/specs/data-contract.md#pose`, `media-asset.md`, `photo.md`,
  `extraction-job.md`, `saved-entry.md`, `prepared-pose-reference.md`,
  `pose-guide.md`, `community-pose.md`, `personal-pose.md`,
  `pose-reference-key.md`, `account.md`
- `docs/harness/specs/data-contract.md#conceptual-overlay`, `mobile.md`, `server.md`, `README.md`

## Success criteria

- A single canonical `Pose` entity with stable UUID `poseId` created only after
  extraction succeeds.
- Exactly three media roles: `original`, `skeleton`, `thumbnail` — all
  non-nullable, materialized at creation.
- `ownerAccountId` mandatory on every `Pose`.
- Deprecated entity files describe their transition; no parallel Pose domain
  entity remains canonical.
- ERD documents render consistent single-Pose graphs.

## Risks

- Broken relative links when updating entity references — keep every linked
  target file present (`pose.md`, `pose-guide.md`, etc.).

## Required evidence

- `ckh validate docs/harness/specs/data-contract.md` passes.
- `grep -rniE "renderAsset|sourceAsset|PoseReferenceKey.Personal" docs/harness/specs/data-contract.md`
  returns no canonical (non-deprecation) occurrences.