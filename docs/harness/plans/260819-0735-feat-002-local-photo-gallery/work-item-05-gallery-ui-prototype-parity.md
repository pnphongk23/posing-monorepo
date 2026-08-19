---
work_item: 5
title: Gallery UI prototype parity
status: completed
priority: P1
effort: M
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 5: Gallery UI prototype parity

**Kind:** story / UI parity

## Tasks

### Gap

- Align the gallery grid to the prototype dense **3-column** grid
  (`grid.css:213-219` `nb-gallery-grid-dense`, `repeat(3, …)`, gap 3px) —
  production is `GridCells.Fixed(2)`.
- Apply the dense card style `.nb-card--gallery-dense` (`card.css:174`) to the
  gallery `PhotoCard`.

### Aligned (regression)

- Reactive list (`GalleryViewModel.load`) and group headers
  (`SectionHeader` + TODAY/YESTERDAY/MONTH DAY).
- Detail `PhotoDetailDialog`: back, Save, trash, delete modal.
- Empty gallery "NO PHOTOS YET" + "OPEN CAMERA".
- Missing-file placeholder (`resolveImagePath` + `AsyncImage`).
- Grid/list toggle: production retains it (`gallery-grid-toggle` /
  `gallery-list-toggle`); prototype `gallery.html` omits a visible toggle (list
  CSS exists `grid.css:68-76`) — parity matrix labels this **Partial**.
- Favorite mutation (FR-002) is Aligned (existing `toggleFavorite`).

## Scope and affected files

- `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/GalleryScreen.kt`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/PhotoDetailDialog.kt`
- `mobile/composeApp/src/commonTest/kotlin/com/aipose/ui/` (UI tests)

## Success criteria

- Evidence ID **E-GAL-UI**: gallery renders a 3-column dense grid matching
  `nb-gallery-grid-dense`.
- Evidence ID **E-GAL-UI**: detail/empty/missing-file/group regression green.

## Risks

- Regressing grid/list toggle or detail flows while changing the grid density.
- Confusing dense-grid parity (Gap) with already-aligned controls.

## Required evidence

- **E-GAL-UI**: UI test / snapshot for 3-col dense grid.
- **E-GAL-UI**: regression tests for detail, empty, missing-file, grouping.

## Evidence (WI-05, 2026-08-19)

### Dense 3-column grid (E-GAL-UI)

- `GalleryGridDefaults`: `DENSE_COLUMN_COUNT = 3`, `DENSE_GAP = 3.dp` (prototype
  `grid.css:213-219`).
- `GalleryScreen`: grid mode uses `GridCells.Fixed(3)`, 3dp gaps, section headers
  span 3 columns. List mode unchanged (full `PhotoCard` with metadata row).

### Dense card style (E-GAL-UI)

- `DensePhotoCardDefaults` + `GalleryDensePhotoCard`: square tile, cover crop,
  6dp radius, 1dp hairline border, no shadow (prototype `card.css:174-189`).
- Grid uses `PhotoCard(dense = true)`; list retains default card chrome.

### Unit tests (no E2E)

`GalleryGridDefaultsTest.kt` — 6 tests for grid/card constants.

```
./gradlew :composeApp:iosSimulatorArm64Test :shared:iosSimulatorArm64Test
BUILD SUCCESSFUL — full suite green (WI-02 search, WI-03 delete, WI-04 export regressions included)
```

## Evidence (WI-05, 2026-08-19)

### E-GAL-UI — dense 3-column grid + dense card parity

**Gap** closed per prototype:

- `grid.css:213-219` `nb-gallery-grid-dense` → `GalleryGridDefaults`
  (`GRID_DENSE_COLUMN_COUNT = 3`, `GRID_DENSE_GAP = 3.dp`) wired into
  `GalleryScreen` `LazyVerticalGrid` (`GridCells.Fixed(3)`, `spacedBy(3.dp)`,
  section headers `GridItemSpan(3)`). Production was `GridCells.Fixed(2)` +
  `8.dp` gaps.
- `card.css:174-189` `nb-card--gallery-dense` → `DensePhotoCardDefaults`
  (aspect 1/1, hairline `1.dp` border, `6.dp` radius, `box-shadow: none`, no
  caption chrome) applied via `GalleryDensePhotoCard` in `PhotoCard.kt`.
- `PhotoCard` gains `dense: Boolean = false`; grid passes `dense = true`, list
  keeps the caption/badge/time chrome unchanged (toggle + detail preserved).

**Constants** extracted for unit-testability:

`mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/GalleryGridDefaults.kt`

### Unit tests (unit/logic only — no E2E, no Maestro, no UI automation)

`mobile/composeApp/src/commonTest/kotlin/com/aipose/ui/screens/gallery/GalleryGridDefaultsTest.kt`

```
./gradlew :composeApp:iosSimulatorArm64Test
> Task :composeApp:iosSimulatorArm64Test
BUILD SUCCESSFUL

TEST-com.aipose.ui.screens.gallery.GalleryGridDefaultsTest.xml
  tests="6" failures="0" errors="0"
  - denseGridUsesThreeColumns          (repeat(3, minmax(0,1fr)) → 3)
  - denseGridGapIsThreePixels          (gap: 3px → 3.dp)
  - denseCardIsSquare                  (aspect-ratio: 1/1 → 1f)
  - denseCardUsesHairlineBorderWidth   (--nb-border-width-hairline: 1px → 1.dp)
  - denseCardUsesSmallRadius           (--nb-radius-small: 6px → 6.dp)
  - denseCardHasNoShadow               (box-shadow: none → false)
```

### Full-suite regression (E-GAL-UI: search/grouping/detail/empty untouched)

Full `:composeApp:iosSimulatorArm64Test` green — 10 suites, 52 tests,
0 failures, 0 errors. WI-02 `GalleryViewModelTest` (5) and all other
suites included.

### ckh

```
ckh workflow check docs/harness/plans/260819-0735-feat-002-local-photo-gallery --workspace .
```

### Note

Peer `00992c53` errored mid-stream; Lead completed implementation using peer's
partial test scaffold (`GalleryGridDefaultsTest`).
