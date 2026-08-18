---
title: Community title search production
description: Close the FEAT-003 community title-search slice from authority through backend, mock-first mobile paging, prototype-parity UX, and cross-slice verification.
status: pending
approval:
  status: pending
  required_by: Repository Maintainer
priority: P1
effort: L
branch: codex/community-title-search-production
tags:
  - feat-003
  - community-search
  - pagination
  - ios
  - prototype-parity
blockedBy: []
blocks: []
relationships:
  specs:
    - "[[api-catalogue]]"
    - "[[model-entity-catalogue]]"
    - "[[product-feature-inventory]]"
    - "[[technical-architecture]]"
    - "[[ui-ux-system]]"
  decisions: []
  plans:
    - "[[260818-2105-feat-003-pose-library-slice/plan|260818-2105]]"
    - "[[260809-2240-pose-reference-library-convergence/plan|260809-2240]]"
  reports:
    - "[[REP-002-feature-gap-and-release-readiness-audit|REP-002]]"
    - "[[REP-003-pose-reference-library-convergence-delivery|REP-003]]"
    - "[[REP-004-backend-feature-and-model-entity-scout|REP-004]]"
  rules: []
  features:
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
  source_paths:
    - docs/harness/workflows/plan.md
    - docs/harness/features/FEAT-003-browse-and-search-published-poses.md
    - docs/harness/decisions/DEC-003-feat-003-scoped-parity-matrix.md
    - docs/spec/api/modules/community.md
    - docs/spec/api/conventions.md
    - docs/spec/data/entities/community-pose.md
    - docs/spec/data/erd/server.md
    - .rule/convention/neo-brutalism.md
    - docs/prototype/screens/search.html
    - docs/prototype/scripts/app.js
    - docs/prototype/scripts/fixtures.js
    - web/services/pose-extract-server/src/routes/communityRoutes.ts
    - web/services/pose-extract-server/src/db/communityStore.ts
    - web/services/pose-extract-server/src/routes/communityRoutes.test.ts
    - web/services/pose-extract-server/src/db/schema.sql
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/CommunitySearchProvider.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseServiceLocator.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/SearchScreen.kt
    - mobile/composeApp/src/commonTest/kotlin/com/aipose/ui/screens/poses/SearchViewModelTest.kt
    - mobile/shared/src/iosSimulatorArm64Test/kotlin/com/aipose/data/CommunitySearchProviderTest.kt
created: 2026-08-18T21:12:53+07:00
createdBy: Harness CLI
---

# Community title search production

## Overview

This pending Plan closes FEAT-003 FR-002 for title search on the public
community catalogue. It is a planning-only deliverable: no application source,
tests, configuration, or Git state is changed here. FEAT-003 is approved on
2026-08-18 by the Repository Maintainer; this Plan itself remains pending and
has no approval provenance yet.

The implementation contract is fixed for this draft: blank `q` requests the
first page of published community results; every page uses limit 20; search
matches `q` against `name` case-insensitively; mobile introduces
`CommunitySearchRepository`, keeps its mock adapter as the default, and does not
wire a live API provider in `PoseServiceLocator`. The UI retains the existing
mixed Personal/Community identity boundary, while the Community portion is
paginated through that repository.

Prototype-visible copy is exact: page title `Search`; placeholder `Type a title`;
empty title `No matching poses`; blank empty copy `No poses to search yet.`;
no-match copy `No poses match “{query}”. Try a different title.`; action
`Clear search`; and count `{n} pose(s)` or `{n} pose(s) for “{query}”`.
Loading, retry, and retained-result behavior must not replace confirmed content
with unconfirmed content. Existing error/retry semantics are preserved while
paging is added.

The sibling Plan `260818-2105` is still pending, but its declared draft scope
explicitly excludes SearchScreen, `CommunitySearchProvider`, and server `q`.
That is an overlap boundary, not a blocking dependency: this Plan must not
reopen its browse-tabs, coordinator, camera-handoff, Android, or admin-search
scope. The completed Plan `260809-2240` and REP-003 are historical evidence
only. Evidence limitation: a local GitNexus index artifact exists
(`.gitnexus/meta.json`, `indexedAt` 2026-08-18T14:25:35Z, `lastCommit`
`9ff4b136` = current HEAD), but no GitNexus MCP tool is connected in this
session and `ckh graph check` reports the harness retrieval-graph artifact
as stale; graph-derived impact evidence is therefore withheld and direct
canonical inspection of source, specs, tests, and reports is the grounding.

## Work Items

- [Work Item 1: Close FEAT-003 search authority and record Maintainer decisions](./work-item-01-close-feat-003-search-authority-and-record-maintainer-decisions.md)
- [Work Item 2: Backend title search q with pagination limit 20](./work-item-02-backend-title-search-q-with-pagination-limit-20.md)
- [Work Item 3: Mobile community search repository mock-first with paging](./work-item-03-mobile-community-search-repository-mock-first-with-paging.md)
- [Work Item 4: Search screen prototype parity and paging UX](./work-item-04-search-screen-prototype-parity-and-paging-ux.md)
- [Work Item 5: End-to-end search verification](./work-item-05-end-to-end-search-verification.md)

## Coverage

| Requirement or boundary | Work Item coverage |
| --- | --- |
| FEAT-003 authority, locked search decisions, sibling-plan boundary | WI-01 |
| `GET /api/community/poses?q`, published-only filtering, page/limit contract, limit 20, literal wildcard safety | WI-02 |
| `CommunitySearchRepository`, blank-query first page, mock default, page-2 fixtures, dedupe and paging errors | WI-03 |
| Exact prototype copy/layout, count, empty/loading/retry/paging states, accessible clear/retry controls | WI-04 |
| Backend/mobile/UI cross-slice and negative-scope verification | WI-05 |

Explicit non-goals are PosesLibraryCoordinator or browse-tab refactoring,
camera handoff changes, tag or general full-text search, Android, Admin UI
search, and mobile live API provider wiring.

## Verification

### Verification ledger

| Claim | Status | Evidence or fallback |
| --- | --- | --- |
| FEAT-003 is approved (2026-08-18, Repository Maintainer) and governs title search via FR-002 | **Verified** | `docs/harness/features/FEAT-003-browse-and-search-published-poses.md:26-31,100-110` |
| The canonical API contract defines `q` as case-insensitive title search on `name`, published-only, with `page`/`limit`/`total` envelope (public default limit 20) | **Verified** | `docs/spec/api/modules/community.md:7-32`; `docs/spec/api/conventions.md:50-61`; `docs/spec/api/openapi.yaml:453-486` |
| The prototype fixes the exact search copy, count format, empty states, and published-only filtering | **Verified** | `docs/prototype/screens/search.html:44-65`; `docs/prototype/scripts/app.js:447-552` |
| Existing backend tests cover published filtering and filters but not `q`, wildcard escaping, or page two | **Verified** | `web/services/pose-extract-server/src/routes/communityRoutes.test.ts:36-104` |
| Current mobile search is a list-returning mock provider; blank query returns all four fixtures | **Verified** | `mobile/shared/src/commonMain/kotlin/com/aipose/data/CommunitySearchProvider.kt:5-56`; `mobile/shared/src/iosSimulatorArm64Test/kotlin/com/aipose/data/CommunitySearchProviderTest.kt:8-37` |
| `PoseServiceLocator` defaults to the mock provider and has no live community-search API wiring | **Verified** | `mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseServiceLocator.kt:12-15,32-49` |
| Existing search preserves prior results on provider failure and ignores stale completions | **Verified** | `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/SearchScreen.kt:103-129`; `mobile/composeApp/src/commonTest/kotlin/com/aipose/ui/screens/poses/SearchViewModelTest.kt:178-231` |
| Backend `GET /api/community/poses` accepts and forwards `q` (FR-002) | **Failed** (gap — closed by WI-02) | `web/services/pose-extract-server/src/routes/communityRoutes.ts:6-11,24-36` — `listQuerySchema` has `page`/`limit`/`difficulty`/`tag`, no `q` |
| `CommunityStore.listPoses` applies a title predicate | **Failed** (gap — closed by WI-02) | `web/services/pose-extract-server/src/db/communityStore.ts:34-40,94-123` — `ListPosesFilter` has no query field |
| A paginated `CommunitySearchRepository` exists on mobile | **Failed** (gap — closed by WI-03) | `mobile/shared/src/commonMain/kotlin/com/aipose/data/` contains `CommunitySearchProvider.kt` only; no repository type |
| `SearchScreen` renders the exact prototype copy and paginates community results | **Failed** (gap — closed by WI-03/WI-04) | `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/SearchScreen.kt:62-63,213,288,296,312` — old copy (`Type to filter...`, `Clear Search`, `No poses found.`), list-only provider |
| DEC-003 is an approved authority governing this slice | **Unresolved** (non-blocking context) | DEC-003 `status: proposed` (2026-08-18); its No-Search row bounds sibling Plan 260818-2105, not this slice; excluded from `relationships.decisions` because only approved Decisions are authority links; grounded recommendation is non-blocking, Maintainer confirms at Plan approval |
| GitNexus graph/impact tooling is queryable in this session | **Unresolved** (evidence limitation) | Local index artifact exists (`.gitnexus/meta.json`, indexed 2026-08-18T14:25:35Z at HEAD `9ff4b136`) but no GitNexus MCP tool is connected and `ckh graph check` reports the harness retrieval-graph artifact stale; direct canonical inspection is used instead |
| Sibling pending Plan `260818-2105` owns this search slice | **Failed** (no overlap ownership) | `docs/harness/plans/260818-2105-feat-003-pose-library-slice/plan.md:62-64,96-101` explicitly excludes search; this Plan owns the slice |

**Ledger semantics.** Verified rows are grounding facts the Plan relies on.
Failed rows are implementation gaps owned by the named Work Items, not failed
planning assumptions; they are the reason this Plan exists. Unresolved rows
remain open at submission: DEC-003's blocking status is a Maintainer
confirmation at Plan approval (grounded recommendation: non-blocking,
evidence-only), and GitNexus/graph tooling is recorded as an evidence
limitation rather than silently skipped. No Verified grounding fact is
contradicted, and no Work Item depends on a Failed or Unresolved claim being
silently repaired.

### Required validation commands

- `ckh workflow status docs/harness/plans/260818-2112-community-title-search-production/plan.md`
- `ckh workflow check docs/harness/plans/260818-2112-community-title-search-production/plan.md`
  (at drafting, the expected residual finding is `Plan is not approved`;
  schema parse errors and unresolved link findings must be zero).
- Backend focused route/store tests and TypeScript build from
  `web/services/pose-extract-server`.
- `./gradlew :shared:iosSimulatorArm64Test :composeApp:iosSimulatorArm64Test`
  for the repository, ViewModel, and UI contract tests.

No command result in this Plan grants approval. Repository Maintainer approval
is still pending; WI-05 must record any failed test or unavailable device
evidence rather than infer success.
