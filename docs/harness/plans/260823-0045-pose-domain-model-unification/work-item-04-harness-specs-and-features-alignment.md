---
work_item: 4
title: Harness specs and features alignment
status: completed
priority: P1
effort: L
dependencies:
  - 3
decision_dependencies: []
---

# Work Item 4: Harness specs and features alignment

## Tasks

1. Update `docs/harness/specs/` `model-entity-catalogue.md`, `erd.md`,
   `api-catalogue.md`, `product-feature-inventory.md`,
   `technical-architecture.md` to the single-Pose canonical model.
2. Update terminology in `docs/harness/features/FEAT-001` through FEAT-009:
   use `Pose` with `local`/`published`, and `skeleton` for the extraction
   result.
3. Update `docs/harness/README.md` feature-inventory table terminology
   (preserving the existing roadmap/glossary links).

## Scope and affected files

- `docs/harness/specs/model-entity-catalogue.md`, `erd.md`, `api-catalogue.md`,
  `product-feature-inventory.md`, `technical-architecture.md`
- `docs/harness/features/FEAT-001-…` through `FEAT-009-…`
- `docs/harness/README.md`

## Success criteria

- Harness specs and features use `Pose` (`local`/`published`) and `skeleton`;
  feature IDs, wikilink targets, and file names stay unchanged so links resolve.
- FEAT-008 `PreparedPoseReference` refers to `poseId`/`mediaId` and
  `skeletonLocator`.

## Risks

- Breaking wikilinks/relative paths during feature edits — preserve every link
  target file.

## Required evidence

- `ckh validate --kind feature --workspace .` passes for all features.
- `grep -rniE "PoseGuide|PersonalPose as entity|renderAssetId|resultImage"
  docs/harness/features/ docs/harness/specs/` returns only intentional
  deprecation/migration notes or code-source path references.