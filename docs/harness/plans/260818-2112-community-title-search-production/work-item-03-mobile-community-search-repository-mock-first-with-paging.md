---
work_item: 3
title: Mobile community search repository mock-first with paging
status: completed
priority: P1
effort: M
dependencies:
  - 2
decision_dependencies: []
---

# Work Item 3: Mobile community search repository mock-first with paging

**Kind:** story / mobile data contract

## Tasks

- Introduce a paginated `CommunitySearchRepository` contract with query, page,
  and fixed limit 20 inputs plus `data` and pagination metadata. Keep the
  contract independent of `PosesLibraryCoordinator` and browse-tab state.
- Make the mock implementation the default repository in `PoseServiceLocator`.
  It must return published community fixtures, apply case-insensitive title
  matching on `name`, and return the first page for blank or whitespace query.
- Expand deterministic mock fixtures to at least 21 published community poses so
  page one contains 20 and page two contains one. Include a draft/non-public
  fixture in the test source or adapter input to prove it cannot surface.
- Add repository tests for blank query, title match/no-match, filtered total,
  page one/page two, exact page size, stable ordering, and same-ID page overlap.
- Model load-more, refresh, stale-page, and provider-failure outcomes without
  dropping already confirmed results; preserve the existing retry/error contract
  rather than silently converting failures into an empty page.
- Keep the live API adapter intentionally absent from the locator. The backend
  `q` route is evidence and a future replaceable implementation target, not a
  provider wired in this WI.

## Scope and affected files

- `mobile/shared/src/commonMain/kotlin/com/aipose/data/CommunitySearchRepository.kt`
  (new contract and mock-first implementation boundary).
- `mobile/shared/src/commonMain/kotlin/com/aipose/data/CommunitySearchProvider.kt`
  (replace, adapt, or retain only as an internal mock implementation as the
  contract requires; do not leave two competing public authorities).
- `mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseServiceLocator.kt`
  (mock repository default only).
- `mobile/shared/src/iosSimulatorArm64Test/kotlin/com/aipose/data/CommunitySearchProviderTest.kt`
  or the corresponding repository test file.
- Existing `CommunityPose` and `PaginationInfo` DTOs are read-only inputs unless
  a compatible contract extension is required.
- Explicitly out of scope: `PosesLibraryCoordinator`, browse tabs, Navigation,
  Android targets, and live `PoseApiService` search wiring.

## Predecessors and dependencies

WI-02 establishes the shared page/limit and published-filter contract. WI-04
must wait for this repository state model and fixture shape. WI-03 does not wait
for a live backend provider because mock-first behavior is locked.

## Decision dependencies

**Locked contract reference:** plan.md Overview (approved 2026-08-18) fixes
`CommunitySearchRepository` as the mobile boundary, the mock as default, and no
live locator wiring; this WI implements that contract.

The repository is replaceable but the default is deterministic mock data. Blank
query means page one, not an empty “query mode”; page size is 20; title matching
is the only search predicate; and no live locator wiring is permitted.

## Success criteria

- A repository call with blank or whitespace query returns page 1 of published
  mock community results with `limit == 20`, total metadata, and no draft rows.
- With at least 21 fixtures, page 1 has 20 results and page 2 has the remaining
  result; IDs are source-qualified and stable across repeated calls.
- Query filtering is case-insensitive on title only, and a no-match query has
  zero data with a zero filtered total.
- Paging/retry state retains confirmed results, rejects stale or duplicate page
  application, and exposes a retryable error rather than fabricating emptiness.
- `PoseServiceLocator` still defaults to mock search and contains no live API
  community-search provider wiring.

## Risks

- Mock fixture collections with fewer than 21 items can make page-two logic look
  correct while never exercising the second page; enforce the fixture threshold.
- Offset paging and overlapping responses can duplicate IDs; dedupe by stable
  source-qualified identity and test an overlap explicitly.
- Replacing the old list provider can accidentally discard current failure,
  retry, or stale-completion semantics; retain those tests while changing shape.
- A mock-backed page can be mistaken for production API evidence; label it as
  mock and record the absent live adapter in WI-05.

## Required evidence

- iOS simulator shared-test output for repository contract, 21+ fixtures,
  page-two, no-match, dedupe, stale-page, and failure-retention cases.
- Direct inspection of `PoseServiceLocator` proving the mock is still the
  default and no live API provider is constructed.
- A state-transition trace for initial page, load-more, duplicate/stale page,
  failure, and retry.
