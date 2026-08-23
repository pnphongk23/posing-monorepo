---
title: Runtime Pose Domain Migration
description: Canonical Pose runtime migration across mobile, backend, Admin Web, OpenAPI, and harness within approved Team A scope.
status: completed
approval:
  status: approved
  required_by: Repository Maintainer
  decided: 2026-08-23
priority: P1
effort: L
branch: working-tree
tags:
  - pose
  - migration
  - mobile
  - backend
  - admin
blockedBy: []
blocks: []
relationships:
  specs: []
  decisions: []
  plans: []
  reports:
    - "[[REP-009-runtime-pose-domain-migration|REP-009]]"
  rules: []
  features: []
created: 2026-08-23T00:00:00Z
createdBy: Team A
---

# Runtime Pose Domain Migration

- **Plan ID:** 260823-0215
- **Status:** in progress
- **Authority:** Canonical Pose Domain Model in `docs/spec/data/domain-model.md`

## Goal

Migrate mobile Kotlin/Compose, SQLDelight, pose-extract backend, Admin Web, OpenAPI, and harness documentation to one canonical `Pose` entity.

## Invariants

1. `poseId` is a UUID assigned once after extraction succeeds and remains stable through `local` → `published`.
2. Every Pose has non-null `ownerAccountId`.
3. `original`, `skeleton`, and `thumbnail` media roles are non-null at Pose creation.
4. Extraction start is `202 Accepted`; post-success Pose materialization is `201 Created`.
5. `CommunityPose` is a published read projection, not a persisted entity.
6. Legacy names and models may remain only in isolated, deprecated transport adapters.

## Work items

1. Forensic review and migration safety gate.
2. Align SQLDelight `Pose`/`Photo` schema, repositories, and migration tests.
3. Remove mobile runtime `PoseReferenceKey` branching; route all navigation and camera handoff by `poseId`.
4. Align backend PoseStore, media assets, extraction finalization, routes, and tests.
5. Align Admin Web API proxy and pages with 202/201 and canonical fields.
6. Refresh OpenAPI and harness source-of-truth documents.
7. Run full mobile, backend, web, harness, diff, and GitNexus validation.

## Validation

- `./gradlew :composeApp:allTests :shared:iosSimulatorArm64Test --no-daemon`
- `./gradlew :composeApp:linkDebugFrameworkIosArm64 --no-daemon`
- backend `npm test`, `npm run build`, `npm run lint`
- Admin Web `npm run build`, `npm run lint`
- `ckh validate --all`
- `git diff --check`
- `gitnexus detect_changes --repo ai-pose --scope working`
