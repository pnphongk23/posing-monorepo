---
work_item: 3
title: Regression verify poses-list browse and retain search affordance
status: completed
priority: P1
effort: M
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 3: Regression verify poses-list browse and retain search affordance

**Kind:** regression + search affordance verification (not a product-surface removal)

## Tasks

### Regression (2240 / REP-003 read-only)

- Verify My Poses tab (`PosesScreen.kt:213-281`) and Community tab with
  `PosesLibraryCoordinator` paging, refresh, E1 recovery (`PosesScreen.kt:284-462`).
- Confirm community cards navigate to detail (`Navigation.kt:128`, `CommunityPoseCard`).
- Re-run coordinator tests unless already green; **do not** refactor 2240-delivered
  code unless a named regression fails.

### Search affordance retained (verify wired)

- Verify the search toolbar button (`PosesScreen.kt:179-193`, test tag
  `poses-search-button`) is **visible** on poses-list.
- Verify `onSearchClick` still pushes to `SearchScreen` via `Navigation.kt:130-136`
  (post-2112 delivery, or already wired).
- **Do not** hide or unwire the search icon; **do not** delete `SearchScreen.kt`,
  `CommunitySearchProvider.kt`, or server search routes — search behavior is
  read-only, owned by Plan `260818-2112`.

## Scope and affected files

- `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PosesScreen.kt` (verify only)
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt` (verify wired)
- `mobile/shared/.../PosesLibraryCoordinator.kt` (regression tests only unless fix needed)
- `docs/prototype/screens/poses-list.html` (tabs/grid; search icon retained in acceptance)

## Success criteria

- Browse/paging/refresh match DEC-003 **Aligned** rows (regression).
- **Positive acceptance:** poses-list shows the search button and navigating
  reaches `SearchScreen` (evidence ID **E-SEARCH-WIRED**).
- No server `q` or `CommunitySearchProvider` behavior added by this WI.

## Risks

- Accidentally hiding/unwiring the search icon that must remain wired for Plan 2112.

## Required evidence

- **E-BROWSE-REG**: coordinator + compose tests for tabs, retry banners.
- **E-SEARCH-WIRED**: UI test or snapshot proving search button visible and
  navigation to `SearchScreen` works.

## Evidence (2026-08-19)

- **E-BROWSE-REG**: `./gradlew :shared:iosSimulatorArm64Test` green (PosesLibraryCoordinatorTest, PoseRepositoryDeletionTest, CommunitySearchRepositoryTest). `PosesViewModelTest` green in composeApp.
- **E-SEARCH-WIRED**: `SearchNavigationWiringTest` — `POSES_SEARCH_BUTTON_TEST_TAG` contract + `createSearchNavigationAction` pushes `SearchScreen`. `Navigation.kt` uses extracted helper; search icon retained on `PosesScreen`.
- SearchScreen / CommunitySearchRepository / server `?q=` **unchanged**.
