---
title: Pose Domain Model Unification
description: >-
  Unify the Pose domain model, ERD, API specs, and Harness specs around a single
  canonical Pose entity with three media asset roles (original, skeleton,
  thumbnail) and a simple lifecycle (local -> published). Technical-only
  documentation refactor; no application source code is modified.
status: completed
approval:
  status: approved
  required_by: Repository Maintainer
  decided: 2026-08-23
priority: P1
effort: L
branch: codex/pose-domain-model-unification
tags:
  - docs
  - domain-model
  - terminology
  - refactor
  - enums
  - erd
  - api
blockedBy: []
blocks: []
relationships:
  specs:
    - "[[pose-domain-glossary]]"
    - "[[technical-architecture]]"
    - "[[product-feature-inventory]]"
    - "[[model-entity-catalogue]]"
    - "[[erd]]"
    - "[[api-catalogue]]"
  decisions: []
  plans: []
  reports:
    - "[[REP-008-pose-domain-model-unification-delivery|REP-008]]"
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
  source_paths:
    - docs/spec/data/domain-model.md
    - docs/spec/data/enums.md
    - docs/spec/data/entities/pose.md
    - docs/spec/data/entities/media-asset.md
    - docs/spec/api/openapi.yaml
    - docs/harness/specs/pose-domain-glossary.md
created: 2026-08-23T00:45:00+07:00
createdBy: Harness CLI
---

# Pose Domain Model Unification

## Overview

Unify the Pose product documentation around a single canonical domain model:

- **One** canonical `Pose` entity with a stable UUID (`poseId`) from **creation
  (post-extraction)** through publication.
- **Creation timing:** a `Pose` is created **only after extraction succeeds**.
  During extraction the work is tracked by `jobId` (correlation key; no
  persisted Pose exists). Once extraction succeeds, the `Pose` is created with
  its stable `poseId`. HTTP contract: `202 Accepted` for job start, `201 Created`
  for Pose creation/completion.
- **Lifecycle:** `status: local` → `status: published`. No parallel
  `PoseGuide`, `CommunityPose`, or `PersonalPose` domain entities. The public
  catalogue is a filtered **view/DTO** (`status='published'`), not a separate
  entity.
- **Three media roles:** `original` (source), `skeleton` (AI extraction
  result), `thumbnail` (preview) — all non-nullable, materialized immediately
  upon Pose creation.
- **Mandatory owner:** `ownerAccountId` is required (non-nullable) on every
  `Pose`, including Admin-created poses; the authenticated actor (Admin bearer)
  may differ from the owner in API headers.
- **Terminology:** extraction-result references (`render`, `extracted pose
  image`, `result image`) are renamed to **skeleton** across models, API specs,
  ERDs, and docs.
- **Simple IDs:** `poseId` (UUID) and `mediaId` (UUID), plus `jobId` as the
  extraction correlation key. The old Personal/Community reference-key concept
  is deprecated.

**Scope boundary:** only documentation under `docs/spec/` and `docs/harness/`.
No application source (`*.kt`, `*.ts`, etc.) is modified. Unrelated dirty
worktree changes outside these trees are preserved.

Canonical definitions live in
[`docs/harness/specs/pose-domain-glossary.md`](../../specs/pose-domain-glossary.md)
and [`docs/spec/data/entities/pose.md`](../../../spec/data/entities/pose.md).

## Work Items

- [Work Item 1: Glossary and canonical Pose domain model](./work-item-01-glossary-and-canonical-pose-domain-model.md)
- [Work Item 2: Data specs entities enums and ERD refactor](./work-item-02-data-specs-entities-enums-and-erd-refactor.md)
- [Work Item 3: API specs openapi and module contracts refactor](./work-item-03-api-specs-openapi-and-module-contracts-refactor.md)
- [Work Item 4: Harness specs and features alignment](./work-item-04-harness-specs-and-features-alignment.md)
- [Work Item 5: Harness validation and index/graph build](./work-item-05-harness-validation-and-index-graph-build.md)

### Work item dependency graph

```
WI-01 (glossary + canonical Pose entity)
  → WI-02 (data specs: entities, enums, ERD)
    → WI-03 (API specs: openapi + module contracts)
    → WI-04 (Harness specs + features alignment)
      → WI-05 (validation / index / graph)
```

WI-01 defines the canonical model; WI-02 materializes it in the data specs;
WI-03 and WI-04 align API and Harness docs; WI-05 gates completion on clean
`ckh` checks.

## Coverage

| Scope item | Work Items |
|---|---|
| Canonical `Pose` entity + glossary | 1 |
| Enums: `PoseStatus` (`local`/`published`), `MediaAssetRole` (`original`/`skeleton`/`thumbnail`) | 1, 2 |
| Entities refactor + `pose.md` | 1, 2 |
| ERD refactor (conceptual/mobile/server) | 2 |
| OpenAPI `skeleton` fields + Pose lifecycle schemas | 3 |
| API module contracts + conventions | 3 |
| Harness specs (`model-entity-catalogue`, `erd`, `api-catalogue`, `product-feature-inventory`, `technical-architecture`) | 4 |
| FEAT-001…FEAT-009 terminology alignment | 4 |
| `ckh validate --all` / `index` / `graph` green | 5 |

## Verification

### Required evidence commands

```bash
cd /Users/phamnhuphong/Git/ai-pose
ckh validate --all
ckh index build
ckh index check
ckh graph build
ckh graph check
```

### Acceptance criteria

- Single canonical `Pose` entity with stable UUID from creation (post-extraction)
  through publication; no persisted Pose before extraction success (`202` job start,
  `201` Pose creation).
- Mandatory `ownerAccountId` on every `Pose` (mobile/local + admin; authenticated
  actor vs owner documented).
- Exactly three media roles: `original`, `skeleton`, `thumbnail` — all
  non-nullable, materialized at creation.
- All extraction-result references updated to `skeleton`.
- Hierarchical glossary at
  `docs/harness/specs/pose-domain-glossary.md`.
- All `ckh` validation/index/graph checks pass cleanly (except pre-existing
  out-of-scope failures in plan `260816-2240`, which are reported as a blocker).
- Detailed delivery report provided at completion.