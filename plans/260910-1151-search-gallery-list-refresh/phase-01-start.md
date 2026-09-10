---
phase: 1
title: "Shared contracts and state seams"
status: pending
priority: P2
effort: ""
dependencies: []
---

# Phase 1: Shared contracts and state seams

## Objective

Freeze the observed backend/mobile contracts and add regression evidence before changing either screen. Keep the implementation inside existing seams; if focused tests expose a real gap, make the smallest compatible change and do not expand the API.

## Requirements and decisions

- `GET /api/community/poses` receives a trimmed nonblank `q`; the server searches published names only, uses the existing fixed search page limit, and returns `{data, pagination}`. Blank query omission remains the existing browse behavior.
- Community results retain the existing generation guard, one in-flight refresh/load-more operation, page-plus-one sequencing, stable `poseId` dedupe, retry, and confirmed-item retention on failure.
- Browse refresh replaces data only after a confirmed successful page one; empty success is an explicit empty list. No cursor, ordering, or new error envelope is invented.
- `PhotoRepository.getAllPhotos()` remains the reactive local source. `GalleryListStateHolder` remains above the detail push/pop boundary.
- `SearchViewModel` is co-located in `SearchScreen.kt:91-155`; Phase 2 edits that file in place and does not create a `SearchViewModel.kt` file.
- The gallery join uses existing `PhotoRepository.getAllPhotos()` and `PoseRepository.getMyPoses()` flows on their repository-owned `Dispatchers.Default` mapping. `GalleryViewModel` owns the in-memory `poseId -> Pose.name` projection; no database access moves into the Composable.

## Architecture and ownership

`communityRoutes.ts` -> `PoseApiService` -> `LiveCommunitySearchRepository` -> `CommunitySearchPagingController` supplies SearchScreen and the existing community browse coordinator. The contract tests are the evidence gate; the route and DTO are read/verified and are modified only if a focused regression proves a current defect.

Modify only focused tests in this phase:

- `mobile/shared/src/iosSimulatorArm64Test/kotlin/com/aipose/data/CommunitySearchRepositoryTest.kt`
- `mobile/shared/src/iosSimulatorArm64Test/kotlin/com/aipose/data/PosesLibraryCoordinatorTest.kt`
- `web/services/pose-extract-server/src/routes/communityRoutes.test.ts` if route coverage is missing

Read/verify `CommunitySearchRepository.kt`, `PosesLibraryCoordinator.kt`, `PoseApiService.kt`, `communityRoutes.ts`, `api-contract.md`, `PhotoRepository.kt`, `PoseRepository.kt`, `Pose.sq`, and `GalleryListStateHolder` ownership. Do not touch the viewer plan or production source in this planning task.

## Implementation steps

1. Add or tighten tests for exact nonblank `q` forwarding, published projection, fixed search limit, empty response, stale generation, page dedupe, refresh replacement, failure retention, and retry.
2. Run the focused shared/backend checks and capture the observed contract.
3. If a test fails because the current implementation violates an observed contract, patch only the named state seam; do not introduce a new endpoint, cursor, source filter, or persistence model.

## Acceptance criteria

- [ ] Tests demonstrate published-only query results and no duplicate active `poseId` after paging or refresh.
- [ ] A stale completion cannot replace newer query/refresh state; a failed refresh/load-more retains confirmed items and exposes retry.
- [ ] No contract change is required to support Phase 2 or Phase 3.

## Checks and risks

- Check `./gradlew :shared:iosSimulatorArm64Test` (or the focused test task) and `npm test -- --run src/routes/communityRoutes.test.ts` from `web/services/pose-extract-server`.
- Risk: live mobile/server E2E and public-asset readiness remain unresolved. Android is not a configured target.
