---
schema_version: 1
title: Community title search production delivery
relationships:
  specs:
    - "[[api-catalogue]]"
    - "[[model-entity-catalogue]]"
    - "[[product-feature-inventory]]"
    - "[[ui-ux-system]]"
  decisions: []
  plans:
    - "[[260818-2112-community-title-search-production/plan|260818-2112]]"
  reports:
    - "[[REP-003-pose-reference-library-convergence-delivery|REP-003]]"
  rules: []
  features:
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
  source_paths:
    - web/services/pose-extract-server/src/routes/communityRoutes.ts
    - web/services/pose-extract-server/src/db/communityStore.ts
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/CommunitySearchRepository.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseServiceLocator.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/SearchScreen.kt
    - docs/prototype/screens/search.html
    - docs/prototype/scripts/app.js
type: report
id: REP-005
status: completed
delivered: 2026-08-19
---

# REP-005: Community title search production delivery

## Delivered outcome

Plan `260818-2112-community-title-search-production` delivered the approved
FEAT-003 FR-002 community title-search slice: public `GET /api/community/poses?q`
with published-only case-insensitive `name` matching, fixed limit 20 when `q` is
present, literal wildcard escaping, and offset paging with filtered totals;
mobile `CommunitySearchRepository` with mock-first default (21+ published
fixtures, page-one/page-two paging, dedupe and error retention); and
`SearchScreen` prototype-parity copy, count format, clear/retry/load-more states,
and ViewModel contract tests. Live `PoseApiService` community-search wiring in
`PoseServiceLocator` was intentionally not added; mock remains the default adapter.

## Changed files

### Backend (WI-02)

- `web/services/pose-extract-server/src/routes/communityRoutes.ts` — optional `q`,
  `SEARCH_PAGE_LIMIT` 20 when `q` present, forwards filter to store.
- `web/services/pose-extract-server/src/db/communityStore.ts` — `q` on
  `ListPosesFilter`, `ILIKE` with `escapeLikePattern`, shared count/data predicate.
- `web/services/pose-extract-server/src/routes/communityRoutes.test.ts` — title
  search route contract, wildcard literals, page two, limit enforcement.
- `web/services/pose-extract-server/src/db/communityStore.test.ts` — store-level
  `q`, totals, paging overlap, wildcard safety.

### Mobile (WI-03 / WI-04)

- `mobile/shared/src/commonMain/kotlin/com/aipose/data/CommunitySearchRepository.kt`
  — paginated contract, `MockCommunitySearchRepository`, 21 published fixtures,
  `CommunitySearchPagingController`.
- `mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseServiceLocator.kt` —
  `communitySearchRepository` defaults to `MockCommunitySearchRepository()`.
- `mobile/shared/src/iosSimulatorArm64Test/kotlin/com/aipose/data/CommunitySearchRepositoryTest.kt`
  — blank query, match/no-match, page two, dedupe, stale/error retention.
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/SearchScreen.kt`
  — repository injection, exact prototype copy, paging UX, retry retention.
- `mobile/composeApp/src/commonTest/kotlin/com/aipose/ui/screens/poses/SearchViewModelTest.kt`
  — copy, count, clear, load-more failure retention, paging controller integration.

Removed superseded mock list provider: `CommunitySearchProvider.kt` (replaced by
repository contract).

## Verification evidence

| Claim | Status | Evidence |
| --- | --- | --- |
| Backend `q` route: published-only, limit 20, case-insensitive title, page two, wildcard literals | **Verified** | `npm test -- communityRoutes communityStore` — 43 passed / 0 failed (2026-08-19); `communityRoutes.test.ts` `describe("title search (q)")`; `communityStore.test.ts` `describe("title search (q)")` |
| Backend TypeScript build and lint | **Verified** | `npm run build` and `npm run lint` exit 0 (2026-08-19) |
| `CommunitySearchRepository` mock default, 21+ fixtures, paging, dedupe, error retention | **Verified** | `CommunitySearchRepositoryTest` — 12 passed / 0 failed; `buildMockCommunityFixtures()` ≥ 21 published entries in `CommunitySearchRepository.kt` |
| `PoseServiceLocator` has no live community-search API provider | **Verified** | `PoseServiceLocator.kt:14` — `MockCommunitySearchRepository()` default; no `PoseApiService` search adapter on locator |
| `SearchScreen` prototype copy, count, clear, empty/no-match, paging, retry retention | **Verified** | Source: `SearchScreen.kt` copy helpers; `SearchViewModelTest` — 10 passed / 0 failed including `testEmptySearchCopyMatchesPrototype` |
| Cross-slice iOS simulator + Compose common tests | **Verified** | `./gradlew :shared:iosSimulatorArm64Test :composeApp:iosSimulatorArm64Test --rerun-tasks` — BUILD SUCCESSFUL (2026-08-19); shared 41 tests / 0 failures; composeApp 33 tests / 0 failures |
| Harness workflow schema and links | **Verified** | `ckh workflow check docs/harness/plans/260818-2112-community-title-search-production/plan.md` — passed (2026-08-19) |
| Negative scope: no `PosesLibraryCoordinator` browse refactor, plan 2105 implementation, Android, or Admin UI title-search work in this slice | **Verified** | WI-02/03/04 affected-file lists exclude coordinator, Android targets, admin UI; delivery file list above is the slice boundary; unrelated working-tree edits to sibling harness docs / `PosesScreen.kt` are not counted as 2112 evidence |
| Live API end-to-end against production/staging backend | **Unresolved** | Mock default by design; no locator wiring to `PoseApiService` community search |
| Screenshot / device / Maestro interaction evidence | **Unresolved** | No Maestro run or physical-device session in WI-05; Compose UI screenshot automation absent (same as REP-003) |
| DEC-003 as approved authority for this slice | **Unresolved** (non-blocking) | DEC-003 remains `proposed`; bounds sibling Plan 260818-2105 only |
| GitNexus graph/impact queryable in verification session | **Unresolved** (evidence limitation) | Direct canonical inspection and test output used instead |

## Plan variance

- Mobile remains mock-first: backend `q` route is contract evidence and a future
  replaceable target, not wired through `PoseServiceLocator` in this delivery.
- Visual parity is enforced via exact string helpers and ViewModel tests, not
  captured screenshots against `search.html`.
- `PosesLibraryCoordinator` and browse-tab pagination were explicitly out of
  scope; community search paging is isolated in `CommunitySearchRepository` and
  `SearchScreen`.

## Repeated friction

- Gradle iOS simulator tests report Koin `kotlin.uuid` informational linker
  warnings during `linkDebugTestIosSimulatorArm64`; suite still completes with
  BUILD SUCCESSFUL.
- First `gradlew` invocation returned UP-TO-DATE; WI-05 re-ran with
  `--rerun-tasks` to produce fresh execution evidence.
