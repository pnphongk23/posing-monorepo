---
work_item: 5
title: End-to-end search verification
status: completed
priority: P1
effort: M
dependencies:
  - 2
  - 3
  - 4
decision_dependencies: []
---

# Work Item 5: End-to-end search verification

**Kind:** verification / cross-slice evidence gate

## Tasks

- Run backend route/store tests and build/lint checks for `q`, published-only
  filtering, literal wildcard escaping, fixed limit 20, filtered totals, page
  two, and no duplicate active IDs.
- Run shared iOS simulator repository tests and Compose common tests for blank
  query page one, mock page two, query reset, dedupe, stale/error retention,
  retry, exact copy, count, clear, and source-qualified card identity.
- Compare `SearchScreen.kt` and its tests against `search.html` and `app.js`;
  verify the required copy, loading/empty/error/retry/paging states, labels, and
  test tags without claiming unavailable screenshot/device evidence.
- Verify `PoseServiceLocator` still constructs the mock repository by default
  and does not wire a live `PoseApiService` community-search provider.
- Verify negative scope: no `PosesLibraryCoordinator`, browse tabs, camera
  handoff, Android, Admin UI search, tag/full-text behavior, or unrelated plan
  files were changed or accepted as evidence.
- Consume the required `ckh workflow status` and `ckh workflow check` results,
  record every claim as Verified, Failed, or Unresolved, and prepare the Plan
  for Maintainer review. Do not approve it.

## Scope and affected files

- This Plan directory's `plan.md` and Work Items 1–5 for the evidence packet.
- Test/build output from `web/services/pose-extract-server` and the iOS
  simulator/common test tasks.
- Read-only cross-slice files listed by WI-02, WI-03, and WI-04.
- No application source, tests, configuration, Git state, or sibling Plan files
  may be modified by this verification WI.

## Predecessors and dependencies

WI-02, WI-03, and WI-04 are all hard predecessors. Cross-slice verification must
not begin until each contract and state/test surface exists; a failed predecessor
is recorded as Failed, not silently bypassed.

## Decision dependencies

**Locked contract reference:** plan.md Overview (approved 2026-08-18) fixes the
verified contract (blank `q` page one, limit 20, published title match, mock
default, exact prototype copy); this WI verifies against it.

Verification uses the already locked contract only: blank query page one,
limit 20, published title match, mock default/no live locator wiring, and exact
prototype copy. It does not create or approve a new Decision.

## Success criteria

- Backend evidence proves the q/published/limit-20 contract, wildcard safety,
  filtered total, page-two behavior, and non-overlapping IDs.
- Mobile evidence proves `CommunitySearchRepository` blank/page-two/no-match/
  retry behavior, at least 21 mock fixtures, default mock wiring, and no live
  API provider locator path.
- UI evidence proves exact prototype copy and count, clear behavior, loading,
  empty/no-match/error/retry/paging states, stable identity, and accessibility
  hooks; unavailable screenshot or device evidence is explicitly Unresolved.
- Negative-scope inspection proves no browse/coordinator/camera/Android/Admin
  search/tag/full-text changes were included.
- The final Plan remains `status: pending` and approval `pending` even when
  mechanical validation passes.

## Risks

- A green backend or mobile test suite can still miss cross-slice page-shape
  drift; inspect the route envelope, repository mapping, and UI state together.
- Offset paging can pass isolated tests while duplicating after page overlap;
  retain the explicit page-one/page-two ID comparison.
- Mock fixtures can give false production confidence; report the absent live
  adapter and do not call mock evidence end-to-end API proof.
- Existing retry semantics can regress during page-state changes; require prior
  card retention after initial and load-more failures.
- The sibling pending Plan overlaps FEAT-003 but explicitly excludes search;
  record that dependency boundary and do not modify or approve the sibling.

## Required evidence

- Backend focused test output plus `npm run build` and `npm run lint` in the
  service package, with command status recorded.
- `./gradlew :shared:iosSimulatorArm64Test :composeApp:iosSimulatorArm64Test`
  output, including any known compile/device limitation.
- A cross-slice trace from query input → repository page → UI state/count/cards,
  plus page-two, retry, and no-match traces.
- Consumed outputs for:
  `ckh workflow status docs/harness/plans/260818-2112-community-title-search-production/plan.md`
  and
  `ckh workflow check docs/harness/plans/260818-2112-community-title-search-production/plan.md`.
- Maintainer review packet listing Verified, Failed, and Unresolved claims;
  no approval command or approval claim.

## Evidence (WI-05, 2026-08-19)

### Commands

```text
cd web/services/pose-extract-server && npm test -- communityRoutes communityStore
→ 43 passed, 0 failed (3 files, ~11.3s)

npm run build && npm run lint
→ exit 0

./gradlew :shared:iosSimulatorArm64Test :composeApp:iosSimulatorArm64Test --rerun-tasks
→ BUILD SUCCESSFUL; shared 41 tests / 0 failures; composeApp 33 tests / 0 failures

ckh workflow status docs/harness/plans/260818-2112-community-title-search-production/plan.md
→ Review State: approved; Execution State: in_progress (pre-completion)

ckh workflow check docs/harness/plans/260818-2112-community-title-search-production/plan.md
→ Harness validation passed
```

### Cross-slice trace (automated)

- Blank query → `MockCommunitySearchRepository` page 1 (20 items) → `SearchViewModel`
  mixed count → `SearchScreen` `No poses to search yet.` when empty personal set.
- Title query → repository filtered total → count `{n} pose(s) for “{query}”` helpers.
- Page 2 → `CommunitySearchPagingController` load-more; overlap dedupe tested in
  `CommunitySearchRepositoryTest` and load-more failure retention in `SearchViewModelTest`.
- Retry → `retrySearch()` retains prior cards after provider failure (ViewModel tests).

### Negative scope

- No Android target changes (`composeApp/src/androidMain` absent).
- `PosesLibraryCoordinator` browse refactor not in WI-02/03/04 delivery file list.
- Admin UI title-search feature not in slice; unrelated admin working-tree edits excluded.
- Plan `260818-2105` harness docs dirty in working tree but not 2112 delivery evidence.

### Delivery report

- `docs/harness/reports/REP-005-community-title-search-production-delivery.md`

### Unresolved (explicit)

- Mock default; no live `PoseApiService` community-search locator wiring.
- No Maestro / physical-device / screenshot capture in this WI.
