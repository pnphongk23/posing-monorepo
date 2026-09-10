# PLAN_FINAL — Search + Gallery List Refresh

## Goal

Deliver Plan 2’s published community browse/search and local captured-photo list refresh for `SCR-003-02`, `SCR-002-01`, `FEAT-003`, and `FEAT-002` without widening existing contracts. Search uses the existing published `GET /api/community/poses` path; Gallery uses local reactive `Photo` data. No viewer/detail action is part of this plan.

## Approach and decisions

1. Preserve existing `q` semantics and paging: trimmed nonblank title search, published-only records, fixed search page limit, generation safety, page dedupe, refresh replacement on success, confirmed-item retention on errors, retry, and explicit empty response.
2. Edit `SearchScreen.kt` in place because `SearchViewModel` is declared at `:91-155` and the UI at `:157-443`. Remove `SearchUiState.localResults`, `SearchItem.Local`, the local collector/filter, and `onLocalPoseClick`; update `Navigation.kt:318-324` and tests to published-only wiring. Explicit query policy: initial composition, blank/whitespace input, and clear never call `communityPaging.search("")` or the network. Only `query.trim().isNotEmpty()` dispatches search; blank clear resets paging UI in memory.
3. In `GalleryViewModel`, combine existing `PhotoRepository.getAllPhotos()` (`PhotoRepository.kt:31-34`) and local `PoseRepository.getMyPoses()` (`PoseRepository.kt:38-46`) flows using the same database. Their SQLDelight list mapping remains on `Dispatchers.Default`; the ViewModel owns the in-memory `poseId -> Pose.name` join and query projection. A nonblank query matches either nonblank stored `Photo.poseName` or linked local `Pose.name`. A non-local/unresolved link with null/empty stored name is excluded from query results; date/image/favorite metadata never matches. The unfiltered gallery still contains that photo.
4. Use cancel/reuse load lifecycle: `GalleryViewModel` owns one active combined-flow load job; an active start is reused, a cancelled start is replaced once, and concurrent starts cannot create duplicate collectors. Detail push cancels the list collection; re-entry starts exactly one replacement while the hoisted `GalleryListStateHolder` preserves VM and viewport.

## Ownership and write set

Search owns `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/SearchScreen.kt` in place, `Navigation.kt`, and focused search/wiring tests. Gallery owns `GalleryViewModel.kt`, only the list/header/grid region of `GalleryScreen.kt`, and gallery/state-ownership tests. `PhotoRepository.kt`, `PoseRepository.kt`, SQLDelight files, backend route/DTO code, and `plans/260909-1137-gallery-photo-viewer-v2` are read-only evidence or exclusions.

## Acceptance evidence

- Instrumented search tests prove zero blank-query dispatches on initial/blank/clear paths and dispatch only for trimmed nonblank intent.
- Shared/backend tests prove published-only `q`, paging dedupe, stale-generation protection, refresh/error retention, retry, and empty behavior.
- Search tests prove no local result/callback seam, published-only cards, state recovery, load-more, and existing detail/back/search-icon wiring.
- Gallery tests prove both accepted name fields, unresolved null/empty-name exclusion without metadata matching, reactive updates from both flows, one collector across cancel/re-entry, empty-state distinction, date grouping, and dense 3-column/3dp/square geometry.

## Risks and open questions

Live server E2E/public asset readiness, non-local Pose resolution, gallery sync/manual refresh semantics, recent-search persistence, mixed-source filters, real iPhone evidence, and Android parity remain unresolved. Current source is authoritative over historical FEAT-002 completion notes; no API fallback is allowed for unresolved Pose links.

## Simplest viable alternative

If the linked local-name join is deferred, filter only nonblank stored `Photo.poseName` and explicitly mark DEC-004 Option A incomplete. If callback compatibility is later required, restore it only through an accepted local/mixed-search scope change; neither is silently substituted.

Implementation proceeds only under the mission’s existing scope and checks; this finalization creates no production changes.
