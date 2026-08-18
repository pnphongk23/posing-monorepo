---
work_item: 3
title: Regression verify poses-list browse and remove search affordance
status: pending
priority: P1
effort: M
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 3: Regression verify poses-list browse and remove search affordance

**Kind:** regression + product-surface delta (search removal)

## Tasks

### Regression (2240 / REP-003 read-only)

- Verify My Poses tab (`PosesScreen.kt:213-281`) and Community tab with
  `PosesLibraryCoordinator` paging, refresh, E1 recovery (`PosesScreen.kt:284-462`).
- Confirm community cards navigate to detail (`Navigation.kt:128`, `CommunityPoseCard`).
- Re-run coordinator tests unless already green; **do not** refactor 2240-delivered
  code unless a named regression fails.

### Delta — search OUT of product surface (C2)

- Hide or remove search toolbar button (`PosesScreen.kt:179-193`, test tag
  `poses-search-button`).
- Remove `onSearchClick` / `SearchScreen` push from `Navigation.kt:130-136`; drop
  unused `SearchScreen` import if safe.
- **Do not** delete `SearchScreen.kt`, `CommunitySearchProvider.kt`, or server
  search routes — read-only for Plan `260818-2112`.

## Scope and affected files

- `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PosesScreen.kt`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt`
- `mobile/shared/.../PosesLibraryCoordinator.kt` (regression tests only unless fix needed)
- `docs/prototype/screens/poses-list.html` (tabs/grid; search not in acceptance)

## Success criteria

- Browse/paging/refresh match DEC-003 **Aligned** rows (regression).
- **Negative acceptance:** poses-list shows **no** search affordance; no route to
  SearchScreen from library (evidence ID **E-SEARCH-NEG**).
- No server `q` or `CommunitySearchProvider` behavior added.

## Risks

- Deleting search implementation files needed by Plan 2112.

## Required evidence

- **E-BROWSE-REG**: coordinator + compose tests for tabs, retry banners.
- **E-SEARCH-NEG**: UI test or snapshot proving search button absent / unwired.
