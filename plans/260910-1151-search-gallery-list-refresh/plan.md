---
title: "search-gallery-list-refresh"
description: "Plan 2: published pose search/browse and local Photo gallery list refresh."
status: pending
priority: P1
effort: "2-3d"
tags:
  - SCR-003-02
  - SCR-002-01
  - FEAT-003
  - FEAT-002
created: 2026-09-10
---

# Search + Gallery List Refresh

## Overview

Deliver the two list surfaces owned by Plan 2: published community pose browse/search for `SCR-003-02`/`FEAT-003`, and the local captured-photo list refresh for `SCR-002-01`/`FEAT-002`. The existing backend contract is `GET /api/community/poses` with a trimmed, optional `q`, published-only projection, fixed search page limit, and `{data, pagination}` response. The existing mobile paging controller already has generation guards, single-flight paging, `poseId` dedupe, retry, and confirmed-item retention on errors. The plan locks those facts with focused tests and changes only the missing screen/list behavior.

Gallery refresh means reconciliation from the reactive local `Photo` flow and list re-entry, not a new HTTP endpoint. Local filtering follows DEC-004 Option A: case-insensitive substring matching against `Photo.poseName` or the linked local `Pose.name` when `poseId` is set. The approved visual target is the current dense three-column grid; the list/detail boundary and the hoisted list state remain intact.

## Goals

| # | Goal | Priority |
|---|------|----------|
| 1 | Preserve published-only `q`, paging, refresh, dedupe, empty, and error contracts for browse/search. | P1 |
| 2 | Make SearchScreen’s query state and published result states match SCR-003-02 without inventing mixed-source contracts. | P1 |
| 3 | Add the local Photo/pose-name list projection and refresh/re-entry behavior for FEAT-002. | P1 |
| 4 | Preserve dense grid geometry and keep viewer/detail/delete/export outside this plan. | P1 |

## Decisions and evidence boundary

- `communityRoutes.ts` and `api-contract.md` are authoritative for `q`: title substring over published records only; no cursor or new endpoint is introduced.
- `CommunitySearchPagingController` and `PosesLibraryCoordinator` are the state seams for generation safety, page sequencing, dedupe, refresh replacement on success, and retention on failure.
- `SearchViewModel` is declared in `SearchScreen.kt:91-155`, not a separate file. The plan edits that file in place; no `SearchViewModel.kt` is created or referenced.
- Search’s current blank initialization and mixed local+published rendering conflict with the SCR-003-02 design contract. This plan prunes `SearchUiState.localResults`, `SearchItem.Local`, and `onLocalPoseClick`; `Navigation.kt:318-324` keeps only the published callback. The design marks local result cards optional/out-of-slice for FEAT-002. Recent-search persistence and a mixed-source filter are unresolved, not invented here.
- `GalleryViewModel.kt:22-39` currently injects a database only to construct `PhotoRepository` and collects `PhotoRepository.getAllPhotos()`. The evidence-backed seam is an additional injected `PoseRepository` on the same database, combining its existing `getMyPoses()` flow with the Photo flow in `GalleryViewModel`; no `PhotoRepository.kt` edit is needed.
- `PhotoRepository.kt:31-34` and `PoseRepository.kt:38-46` map SQLDelight query flows to lists on `Dispatchers.Default`. Repositories own DB access/dispatch; `GalleryViewModel` owns the joined `poseId -> Pose.name` projection and query filtering in the existing collector context. `Pose.sq:26-30` proves the linked-name flow is local-only (`status = 'local'`); a nonlocal/published linked Pose is unresolved rather than fetched through a new API.
- `GalleryScreen` keeps the dense `GalleryGridDefaults` geometry and hoisted `GalleryListStateHolder` contract.

## Ownership and write-set boundary

| Owner | Implementation write set | Explicit boundary |
|---|---|---|
| Search lane | `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/SearchScreen.kt` in place (VM `:91-155`, UI `:157-443`), `Navigation.kt`, and focused tests | Published cards, query states, paging, retry; prune local result/callback seams; no viewer/detail code |
| Gallery lane | `GalleryViewModel.kt`, the list/header/grid region of `GalleryScreen.kt`, and gallery/state-ownership tests | Combine existing Photo/Pose flows and filter/re-entry/dense grid; `PhotoRepository.kt` and `PoseRepository.kt` are read-only seams; no detail route or destructive action |
| Contract checks | Existing shared paging tests and `communityRoutes.test.ts` only where a regression is demonstrated | No API/schema expansion or production Kotlin/Swift edits in this planning task |

Do not edit `plans/260909-1137-gallery-photo-viewer-v2`, `Photo.sq` schema, viewer/detail hosts, save/delete/export/share behavior, Android targets, or unrelated docs.

## Phases

| # | Phase | Status |
|---|-------|--------|
| 1 | [Phase 1: Shared contracts and state seams](./phase-01-start.md) | Pending |
| 2 | [Phase 2: SearchScreen published leg](./phase-02-search-screen.md) | Pending |
| 3 | [Phase 3: Gallery local list](./phase-03-gallery-list.md) | Pending |
| 4 | [Phase 4: Verification and freeze evidence](./phase-04-verification.md) | Pending |

## Acceptance evidence

- Backend route tests prove trimmed/nonblank `q`, published-only records, fixed search limit, stable pagination metadata, and explicit empty `data: []`.
- Shared tests prove stale-generation completion is ignored, refresh/load-more are single-flight, pages dedupe by `poseId`, successful refresh replaces confirmed data, and failures retain confirmed data with retry.
- Search tests prove blank state, query loading/results, absence of local result/callback seams, published-only cards, empty/error/retry, load-more, and unchanged published-detail navigation.
- Gallery tests prove combined reactive `Photo`/local `Pose` flows, case-insensitive `Photo.poseName`/linked local `Pose.name` matching, filter-empty versus gallery-empty, re-entry state ownership, and three columns/3dp/square cards.
- Verification records focused shared/compose/backend checks without claiming physical-device or Android evidence.

## Unresolved questions and risks

1. Live mobile-to-server `q` E2E and production public-asset readiness are not proven; mock coverage is not a substitute.
2. Mixed local/community source filtering and recent-search persistence have no accepted contract; local search is intentionally owned by Gallery.
3. Gallery sync/mixed-source semantics and a manual pull-to-refresh affordance are unspecified; reactive local-flow reconciliation is the minimum defined refresh.
4. The only existing reactive linked-name query is local `Pose` (`Pose.sq:29-30`). Whether a local Photo can reference a published/nonlocal Pose is unresolved; no API fallback is allowed in this plan.
5. Historical FEAT-002 notes call search “resolved,” but checked-in `GalleryViewModel`/`GalleryScreen` have no query projection; current source and tests are the implementation baseline.
6. Prototype notes show a staggered two-column exploration, while DEC-004 and current source require dense three columns. Real iPhone evidence is pending; no Android target exists.

## Success Criteria

- [ ] Four implementation-ready phases are hydrated and have no duplicate phase numbers.
- [ ] Focused tests and `ak plan validate plans/260910-1151-search-gallery-list-refresh --json` pass with zero validation errors.
- [ ] Independent Planning Reviewer READY_FOR_WORK is recorded before PLAN_FINAL finalization; implementation remains gated by the mission handoff.

<!-- slug: search-gallery-list-refresh -->
