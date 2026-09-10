---
phase: 2
title: "SearchScreen published leg"
status: pending
priority: P2
effort: ""
dependencies:
  - 1
---

# Phase 2: SearchScreen published leg

## Objective

Make SCR-003-02/FEAT-003 a published catalogue search surface while preserving the existing paging and navigation seams. `SearchViewModel` is declared inside `SearchScreen.kt:91-155`; edit that file in place rather than extracting a new primary file. The screen must not show unconfirmed content or imply an unaccepted mixed local/community contract.

## Requirements

- Explicit query-trigger policy: blank or whitespace-only entry, initial composition, and clear action never call `communityPaging.search("")` or any network path. Only a query whose `trim()` is nonblank dispatches the existing search; clear resets the published UI state in memory without a request. Do not invent recent-search persistence; if the existing UI has no persisted recent source, keep that region absent/empty.
- On query intent, pass the query through the existing `CommunitySearchPagingController`/`CommunitySearchRepository`; preserve trim/nonblank `q`, page-one reset, generation safety, dedupe, and retry.
- Prune `SearchUiState.localResults` (`SearchScreen.kt:52-61`), `SearchItem.Local` (`:86-89`), the local `PoseRepository` collector/filter (`:91-109`, `:147-154`), and `onLocalPoseClick` (`:157-160`). The published leg is the only rendered result source.
- Update `Navigation.kt:318-324` to remove the local callback closure and retain only `onPublishedPoseClick`; `SearchNavigationWiringTest` must assert the published-only constructor/wiring.
- Expose loading, explicit empty, error with retry, and load-more states without clearing confirmed results on recoverable failure. Preserve confirmed results while a replacement refresh is in flight.
- Keep SearchScreen entry/back/search-icon wiring and the detail boundary. Do not edit `PhotoDetailDialog`, `GalleryPhotoDetailScreen`, `GalleryDetailVoyagerScreen`, or viewer actions.

## Architecture and ownership

Modify:

- `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/SearchScreen.kt` in place (`SearchViewModel`: `:91-155`; UI: `:157-443`)
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt` (`createSearchNavigationAction`: `:313-328`)
- `mobile/composeApp/src/commonTest/kotlin/com/aipose/ui/screens/poses/SearchViewModelTest.kt`
- `mobile/composeApp/src/commonTest/kotlin/com/aipose/navigation/SearchNavigationWiringTest.kt`

Read/verify `CommunitySearchRepository.kt`, `PoseApiService.kt`, the existing `CommunityPose` card/detail callback, and `docs/harness/designs/basic-design/screens/scr-003-02-search.md:58-73`. `srcwalk trace callers SearchScreen` shows the single production caller is `createSearchNavigationAction`; the design labels the local result card optional/out-of-slice FEAT-002. Update only the published-leg behavior required by SCR-003-02 and make the removed local boundary explicit in tests.

## Implementation steps

1. Update view-model/UI tests to remove assertions on local results and constructor callbacks; record repository calls and assert initial composition, blank/whitespace changes, and clear produce zero blank-query dispatches. Add coverage for query transition, published-only rendering, empty, error/retry, loading retention, page append, and query-reset generation safety.
2. In the single `SearchScreen.kt` write set, remove the local repository dependency/collector/filter and local item branch; derive count, empty, keys, and grid content from `publishedResults` only.
3. Remove `onLocalPoseClick` from `SearchScreen` construction and `Navigation.kt:318-324`; keep the published `PosePreview` callback and existing detail route.
4. Wire loading/error/empty/retry/load-more states to the existing controller and run focused compose/navigation tests.

## Acceptance criteria

- [x] Initial, blank, whitespace-only, and clear states never dispatch `communityPaging.search("")`; only `trim().isNotEmpty()` triggers a request, and blank reset is in-memory.
- [x] `SearchUiState` has no local result collection, `SearchItem.Local` branch, or local callback; `Navigation.kt` wires only the published callback.
- [x] Query changes cannot let an older completion replace the newer query; paging has no duplicate `poseId`.
- [x] Empty and error states are distinct; retry recovers while confirmed results remain visible when available.
- [x] Search icon/back and published-card detail navigation continue to work without touching the gallery viewer boundary.

## Checks and risks

- Check `./gradlew :composeApp:iosSimulatorArm64Test` (or focused SearchViewModel/navigation tests).
- Risk: design leaves recent-search persistence and source filtering unresolved; keep both out of the write set. Removing the local callback is safe for the traced single caller, but any new caller would require an explicit scope decision. Live server E2E is still an open evidence item.
