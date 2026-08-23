---
schema_version: 1
title: Browse and Search Published Poses
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
    - "[[260809-2240-pose-reference-library-convergence/plan|260809-2240]]"
  reports:
    - "[[REP-003-pose-reference-library-convergence-delivery|REP-003]]"
    - "[[REP-004-backend-feature-and-model-entity-scout|REP-004]]"
  rules: []
  features:
    - "[[FEAT-006-publish-a-pose|FEAT-006]]"
    - "[[FEAT-008-use-published-poses|FEAT-008]]"
  source_paths:
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt
    - web/services/pose-extract-server/src/routes/communityRoutes.ts
type: feature
id: FEAT-003
status: approved
created: 2026-08-09
approved: 2026-08-18
approved_by: Repository Maintainer
---

# FEAT-003: Browse and Search Published Poses

## Introduction

Visitors and signed-in users browse a published community catalogue, filter the
server list, search by title in the mobile library, refresh, and inspect detail.
Save/Try Pose is [FEAT-008](FEAT-008-use-published-poses.md); publication is
[FEAT-006](FEAT-006-publish-a-pose.md).

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Visitor or signed-in user | User | Discover published poses | Browse, filter, search, and inspect |

### Preconditions

- A community record must be returned by the public route with `status=published`.

### Trigger

The user opens the catalogue, refreshes, searches, or opens a pose card.

### Main flow

1. **Actor:** The user opens the catalogue. **System:** The app requests the published list.
2. **Actor:** The user pages, filters, refreshes, or searches. **System:** The app presents confirmed matching results without duplicate active IDs.
3. **Actor:** The user opens a card. **System:** The app presents published detail and available metadata.

### Alternative flows

- **A1 — Empty result.** Source step: 1 or 2. Condition: no published match exists. Behavior: show an explicit empty state. Ends with: no-match view.
- **A2 — Refresh.** Source step: 2. Condition: the user requests fresh data. Behavior: replace only with confirmed results. Ends with: refreshed list.

### Exception flows

- **E1 — Catalogue unavailable.** Source step: 1 or 2. Failure: transport or server failure. Handling: preserve confirmed results and offer retry. Prohibited: showing unconfirmed content as published.
- **E2 — Detail unavailable.** Source step: 3. Failure: pose is missing/unpublished. Handling: explain unavailability and return to the list. Prohibited: presenting stale detail as current.

### Postconditions

- **Success:** The user sees a published list/search result or detail.
- **Failure:** No unconfirmed pose is presented as public.

### Current evidence

- **Observed:** `CommunityPose` DTOs (the published-`Pose` view/DTO), public list/detail routes with pagination,
  mobile list/detail client calls, refresh/load-more states, and source-qualified
  detail exist.
- **Partial:** `MockCommunitySearchProvider` backs title search; no server title
  search query exists. Public asset readiness and production exposure are not proven.
- **Delivery evidence:** [REP-003](../reports/REP-003-pose-reference-library-convergence-delivery.md)
  records iOS-first library convergence and explicitly defers Android and
  production community search.

### Traceability

| Concern | Canonical reference | Evidence |
| --- | --- | --- |
| Entity/DTO | [`CommunityPose`](../../spec/data/entities/community-pose.md), pagination envelope in [openapi.yaml](../../spec/api/openapi.yaml) | [`PoseApiService.kt`](../../../mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt) |
| ERD | [Server graph](../../spec/data/erd/server.md) plus [unresolved asset links](../../spec/data/erd/conceptual.md) | [`schema.sql`](../../../web/services/pose-extract-server/src/db/schema.sql) |
| APIs | [Community list/detail](../../spec/api/modules/community.md) | [`communityRoutes.ts`](../../../web/services/pose-extract-server/src/routes/communityRoutes.ts), [`PoseApiService.kt`](../../../mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt#L114) |
| Supporting UI/tests | Library, search, detail, coordinator | [`PosesScreen.kt`](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PosesScreen.kt), [`SearchScreen.kt`](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/SearchScreen.kt), [`REP-003`](../reports/REP-003-pose-reference-library-convergence-delivery.md) |

## Requirements

- **FR-001:** Public list/detail responses use the shared `CommunityPose` and pagination DTOs.
- **FR-002:** Title search uses query `q` on `GET /api/community/poses` and only matches published records.
- **BR-001:** A `local` (legacy `draft` alias) or unverified pose must not be described as public/ready.

## Acceptance

- [ ] Public list returns only published records with pagination metadata.
- [ ] Detail rejects missing or unpublished records.
- [ ] Refresh/search failures offer recovery without fabricating content.

## Relationships

- Shared references: [CommunityPose](../../spec/data/entities/community-pose.md) (published-`Pose` view/DTO), [ERD server](../../spec/data/erd/server.md), [Community API](../../spec/api/modules/community.md).
- Related features: [FEAT-006](FEAT-006-publish-a-pose.md), [FEAT-008](FEAT-008-use-published-poses.md).
### Supporting evidence

- [`communityRoutes.ts`](../../../web/services/pose-extract-server/src/routes/communityRoutes.ts)
- [`communityRoutes.test.ts`](../../../web/services/pose-extract-server/src/routes/communityRoutes.test.ts)
- [`PosesLibraryCoordinator.kt`](../../../mobile/shared/src/commonMain/kotlin/com/aipose/data/PosesLibraryCoordinator.kt)
- [`CommunitySearchRepository.kt`](../../../mobile/shared/src/commonMain/kotlin/com/aipose/data/CommunitySearchRepository.kt)
- [`REP-003`](../reports/REP-003-pose-reference-library-convergence-delivery.md)
