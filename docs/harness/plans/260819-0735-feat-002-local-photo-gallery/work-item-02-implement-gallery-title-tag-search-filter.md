---
work_item: 2
title: Implement gallery title-tag search filter
status: completed
priority: P1
effort: M
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 2: Implement gallery title-tag search filter

**Kind:** story

## Tasks

- Add a `searchQuery` to `GalleryUiState` (`GalleryViewModel.kt`) and filter the
  reactive `photos` list before `groupPhotosByDate` is applied.
- Match the prototype filter semantics (`app.js:348-352`): case-insensitive
  **substring** on `Photo.poseName` **OR** linked `Pose.name` when
  `poseId != null` (prototype title OR tag — both map to pose-name text).
- **Option A (Maintainer 2026-08-19):** no separate title field; no new DB tag
  column in this slice. Join or lookup `Pose.name` when `poseId != null`.
- Add a search affordance to `GalleryScreen.kt` (prototype `gallery.html` has no
  visible search input — `app.js:384` removed the listener — so affordance
  placement is a Cook/UI decision; filter semantics are the authority).
- Add an empty-result state ("No photos found", prototype `app.js:355-363`).
- Add tests: query matches `poseName`, matches linked `Pose.name`, matches
  neither, case-insensitive substring, empty query returns all.

## Scope and affected files

- `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/GalleryViewModel.kt`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/GalleryScreen.kt`
- `mobile/composeApp/src/commonTest/kotlin/com/aipose/ui/` (search/filter tests)
- `docs/prototype/scripts/app.js` (read-only authority)

## Success criteria

- Evidence ID **E-GAL-SEARCH**: query filters by substring on `Photo.poseName`
  and linked `Pose.name` (OR, case-insensitive); empty query returns all;
  no-match shows empty state. Mapping **Resolved** (Maintainer 2026-08-19,
  Option A).

## Risks

- Misimplementing OR semantics (must match `poseName` **or** linked `Pose.name`).

## Required evidence

- **E-GAL-SEARCH**: `GalleryViewModelTest` search filter tests green (Option A).
- **E-GAL-SEARCH**: mapping recorded in DEC-004 / design.md (Resolved 2026-08-19).

## Evidence (WI-02, 2026-08-19)

### Search filter implemented (Option A, closed)

- `GalleryUiState.searchQuery: String = ""` added.
- `GalleryViewModel.setSearchQuery(query)` filters the reactive `photos` list
  **before** `groupPhotosByDate`; `photos` stays the unfiltered source so the UI
  can distinguish gallery-empty from filter-empty.
- Filter semantics (contract): case-insensitive **substring** on
  `Photo.poseName` **OR** linked `Pose.name` when `photo.poseId != null`. Pose
  name is resolved via `database.poseQueries.getPoseById(id)` when `poseId` is
  non-null. No new DB tag column (Option A, Maintainer 2026-08-19).
- `GalleryScreen`: search affordance (`OutlinedTextField`, `testTag =
  "gallery-search-field"`) shown only when photos exist; filter-empty state
  ("No photos found") is distinct from gallery-empty ("NO PHOTOS YET").

### Unit tests (unit only — no E2E/UI per Maintainer directive)

`mobile/composeApp/src/commonTest/kotlin/com/aipose/ui/screens/gallery/GalleryViewModelTest.kt`

```
./gradlew :composeApp:iosSimulatorArm64Test
> Task :composeApp:iosSimulatorArm64Test
BUILD SUCCESSFUL

TEST-com.aipose.ui.screens.gallery.GalleryViewModelTest.xml
  tests="5" failures="0" errors="0"
  - emptyQueryReturnsAllPhotos
  - queryMatchesPhotoPoseName
  - queryMatchesLinkedPoseNameWhenPoseIdNotNull
  - queryMatchesNeitherReturnsEmptyFilterResult
  - unmatchedPhotoWithNullPoseIdIsNotMatchedViaPoseNameOfOthers
```

### E-GAL-SEARCH mapping

Mapping recorded **Resolved** (Maintainer 2026-08-19, Option A) in DEC-004 /
design.md: `Photo.poseName` ≈ title and tag both resolve to pose-name text; no
separate title field, no new DB tag column. Search filter semantics = authority.

### `ckh validate` / `ckh workflow check`

```
Harness validation passed
```
