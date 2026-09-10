# PLAN_DRAFT — Search + Gallery List Refresh

## Goal

Deliver Plan 2’s published pose search/browse and local gallery list refresh without widening contracts. SCR-003-02/FEAT-003 uses the existing `GET /api/community/poses?q=...` published leg; SCR-002-01/FEAT-002 uses local `Photo` data. “Refresh” means confirmed page-one/re-entry reconciliation and reactive local-flow updates, not a new endpoint.

## Approach

1. Lock server/mobile behavior with tests: trim blank `q`, published-only projections, fixed search page limit, pagination metadata, generation guards, single-flight refresh/load-more, `poseId` dedupe, confirmed-item retention on errors, retry, and explicit `data: []` empty.
2. Edit `SearchScreen.kt` in place: `SearchViewModel` is declared at lines 91-155 and the UI at 157-443. Prune `SearchUiState.localResults`, `SearchItem.Local`, the local repository collector/filter, and `onLocalPoseClick`. Update `Navigation.kt:318-324` to pass only `onPublishedPoseClick`. Render only published cards and retain existing detail/back/search-icon wiring.
3. Establish the gallery mapping seam without a new contract. `PhotoRepository.getAllPhotos()` already emits `Flow<List<Photo>>` and maps SQLDelight work on `Dispatchers.Default` (`PhotoRepository.kt:31-34`). `PoseRepository.getMyPoses()` supplies a reactive local `Flow<List<Pose>>` on the same dispatcher (`PoseRepository.kt:38-46`; `Pose.sq:29-30`). `GalleryViewModel` will inject `PoseRepository` on the same database, combine both flows, own the `poseId -> Pose.name` map and query projection, and fall back to the stored `Photo.poseName` when no linked local name exists. `PhotoRepository.kt` and `PoseRepository.kt` need no edits.
4. Verify focused shared/compose/backend checks and plan validation. Physical iPhone and Android evidence remain unclaimed.

## Ownership and write set

Search owns `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/SearchScreen.kt` in place, `Navigation.kt`, and focused search/wiring tests. Gallery owns `GalleryViewModel.kt`, only the list/header/grid region of `GalleryScreen.kt`, and gallery/state-ownership tests. `PhotoRepository.kt`, `PoseRepository.kt`, SQLDelight files, route/DTO code, and the viewer plan are read-only evidence. This draft changes no production Kotlin/Swift, docs, or existing plan.

## Acceptance evidence

Backend/shared tests prove published-only `q`, paging, dedupe, refresh replacement, error retention, retry, and empty. Search tests prove blank/query states, absence of local result/callback seams, published-only cards, and navigation. Gallery tests prove combined reactive Photo/local-Pose flows, both accepted name fields, empty distinctions, re-entry ownership, and 3-column/3dp/square geometry. Verification separates mock/unit from live/device evidence.

## Risks and open questions

Live mobile/server `q` E2E and public asset readiness are unresolved. Mixed-source search filters and recent-search persistence lack contracts. The current linked-name evidence is local-only; if a Photo can reference a published/nonlocal Pose, the required lookup is unresolved and must not become an API fallback. Gallery sync/manual refresh semantics are unspecified. Historical FEAT-002 notes conflict with the current source gap; current source wins. Prototype two-column notes conflict with the approved dense three-column target. Android has no target; real iPhone evidence is pending.

## Non-goals

The draft stage did not authorize implementation; no viewer/detail/delete/export/share/save implementation; no `Photo.sq` schema/tag or repository API expansion; no Android target; no edits to `plans/260909-1137-gallery-photo-viewer-v2`; no reindex, reviewer launch, or commit.

## Simplest viable alternative

If linked local-name joins are deferred, filter only stored `Photo.poseName` and explicitly mark DEC-004 Option A incomplete; if local callback compatibility is required, preserve it only behind a separately accepted mixed/local-search contract. Both alternatives require an explicit scope decision and are not the selected path.
