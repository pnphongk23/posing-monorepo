---
phase: 3
title: "Gallery local list"
status: pending
priority: P2
effort: ""
dependencies:
  - 1
---

# Phase 3: Gallery local list

## Objective

Refresh the FEAT-002 local gallery list from confirmed `Photo` data, add the accepted pose-name search projection through an evidence-backed reactive seam, and preserve the dense list/grid/detail boundary. “Refresh” is reactive local reconciliation and list re-entry; no server gallery endpoint is introduced.

## Requirements

- Keep `PhotoRepository.getAllPhotos()` as the reactive source and avoid duplicate collectors. Choose cancel/reuse lifecycle semantics: `GalleryViewModel` owns the active combined-flow load job; an active load is reused, a cancelled load is replaced once, and a second start cannot create a concurrent collector. The hoisted `GalleryListStateHolder` retains `GalleryViewModel` and viewport across detail push/pop; list composition cancellation stops the old load and re-entry starts exactly one fresh load.
- `PhotoRepository.kt:31-34` emits `Flow<List<Photo>>` using SQLDelight `asFlow().mapToList(Dispatchers.Default)`. `PoseRepository.kt:38-46` emits the existing local `Flow<List<Pose>>` with the same dispatcher; `Pose.sq:26-30` defines the linked lookup/query as `status = 'local'`.
- Add `private val poseRepository: PoseRepository = PoseRepository(database)` to the existing `GalleryViewModel` constructor, combine the two repository flows in `load()`, and let the ViewModel own the `poseId -> Pose.name` map and filtered projection. A photo matches case-insensitively when the query is a substring of either nonblank `Photo.poseName` or linked local `Pose.name`; if no local linked name exists, the stored name is the only available field. Repositories own DB access and Default query mapping; no database access moves into the Composable.
- Do not add a DB tag, schema migration, server lookup, or invented fallback mapping. A `Photo.poseId` pointing to a published/nonlocal Pose is not proven by the current local flow and remains an unresolved product/backend question, not an API fallback.
- Keep unfiltered photo presence so “no photos yet” and “no matching photos” are distinct. For a nonblank query, a non-local/unresolved `poseId` with null/empty stored `poseName` is excluded from pose-name results; date, image path, favorite, and other metadata never satisfy the query. Preserve existing date headers and reactive loading/error behavior; the exact new copy must follow current UI conventions rather than inventing a backend error contract.
- Preserve `GalleryGridDefaults.DENSE_COLUMN_COUNT == 3`, 3dp gap, square dense cards, and the current list-to-detail callback. Do not add a grid/list toggle in this phase.
- Edit only the list/header/grid region of `GalleryScreen.kt`. Viewer/detail hosts, delete/save/share/export actions, and the inline legacy detail fallback are explicitly out of scope.

## Architecture and ownership

Modify:

- `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/GalleryViewModel.kt`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/GalleryScreen.kt` (list/header/grid region only)
- `mobile/composeApp/src/commonTest/kotlin/com/aipose/ui/screens/gallery/GalleryViewModelTest.kt`
- `mobile/composeApp/src/commonTest/kotlin/com/aipose/navigation/ListStateOwnershipContractTest.kt`
- `mobile/composeApp/src/commonTest/kotlin/com/aipose/ui/screens/gallery/GalleryGridDefaultsTest.kt` only if a geometry regression appears

`PhotoRepository.kt` and `PoseRepository.kt` are explicit read-only dependencies in this phase: their existing Flow APIs and dispatcher behavior are reused, not edited. `GalleryViewModel.kt` owns the join/projection; `GalleryScreen.kt` owns query input and rendering only.

Read/verify `PhotoRepository.kt:31-34`, `PoseRepository.kt:31-46`, `Photo.sq`, `Pose.sq:26-30`, `PhotoCard.kt`, `GalleryGridDefaults.kt`, and the state-holder/navigation code. `Photo.sq`, `Pose.sq`, both repositories, and all detail/viewer files are read-only evidence for this phase.

## Implementation steps

1. Add database-backed tests with a local linked Pose and Photo, then verify `Pose.name` and stored `Photo.poseName` matching, case-insensitivity, stored-name fallback when the local link is absent, and updates when either existing flow emits.
2. Add tests for blank query, non-match filter-empty, gallery-empty, metadata-only nonmatches, and a non-local/unresolved link with null/empty stored name being excluded from query results while remaining in the unfiltered list.
3. Add a counting repository/Flow fixture and test detail push/pop cancellation plus repeated start: one active combined collector, cancellation releases it, and re-entry creates one replacement without duplication.
4. Add the injected `PoseRepository` seam and combine the existing flows in `GalleryViewModel.load`; keep the projection in the ViewModel and the query input/rendering in the list region.
5. Run gallery/state-ownership tests and inspect the dense three-column geometry regression checks.

## Acceptance criteria

- [ ] Local results update from both existing repository flows and match `Photo.poseName` or linked local `Pose.name` without a new schema/API.
- [ ] Repository query mapping remains on `Dispatchers.Default`; the ViewModel owns only the in-memory join/filter and the Composable does not query the database.
- [ ] `load()` cancel/reuse semantics guarantee one active combined collector across detail push/pop and no duplicate collectors on re-entry.
- [ ] A non-local/unresolved link with null/empty stored `poseName` is excluded only from nonblank pose-name results; no date or other metadata matches it, and it remains in the unfiltered gallery.
- [ ] Gallery-empty and filter-empty are distinguishable; date grouping remains correct after filtering.
- [ ] Three-column/3dp/square dense grid and list/detail state ownership remain intact.
- [ ] No viewer, delete, export, share, save, or existing gallery-v2 file is changed.

## Checks and risks

- Check `./gradlew :composeApp:iosSimulatorArm64Test` (or focused GalleryViewModel, grid, and state-ownership tests).
- Risk: a published/nonlocal `Photo.poseId` is not covered by the existing local `getMyPoses()` flow and needs product/backend clarification. Historical FEAT-002 notes claim search completion while checked-in source lacks the query projection; current source/tests are the baseline. Prototype two-column notes are visual exploration, not the approved three-column production target. Real iPhone evidence is pending.
