---
work_item: 2
title: Backend title search q with pagination limit 20
status: completed
priority: P1
effort: M
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 2: Backend title search q with pagination limit 20

**Kind:** story / backend API and persistence

## Tasks

- Extend the public list query schema with optional `q`; treat absent or blank
  `q` as the first page of the published catalogue and match non-blank `q`
  case-insensitively against `community_poses.name` only.
- Thread `q` through `CommunityStore.listPoses` so the count query and data
  query use the identical predicate and always retain `status = published`.
- Keep the public search page size at exactly 20 and return pagination metadata
  with the requested page, limit 20, and filtered total. Preserve the existing
  page/offset contract; make ordering deterministic before offset paging.
- Escape `\\`, `%`, and `_` before constructing the SQL LIKE pattern and use an
  explicit escape clause. Add tests proving wildcard characters are literals,
  not unbounded matches or injection-shaped fragments.
- Add route/store tests for blank query, case-insensitive substring, draft
  exclusion, empty filtered result, filtered total, exact 20-item pages, page
  two, and invalid pagination values. Test that page-one/page-two fixtures do
  not duplicate active IDs.

## Scope and affected files

- `web/services/pose-extract-server/src/routes/communityRoutes.ts`
- `web/services/pose-extract-server/src/db/communityStore.ts`
- `web/services/pose-extract-server/src/routes/communityRoutes.test.ts`
- `web/services/pose-extract-server/src/db/communityStore.test.ts`
- `web/services/pose-extract-server/src/db/schema.sql` only if a compatible
  title-search index is evidenced as necessary; no schema migration is assumed.
- Read-only contract: `docs/harness/specs/api-contract.md#community-public` and
  `docs/harness/specs/api-contract.md#conventions`.

## Predecessors and dependencies

WI-01 must close the FEAT-003 authority and scope boundary first. WI-03 consumes
this pagination envelope conceptually, but its default remains a mock and does
not require live API wiring.

## Decision dependencies

**Locked contract reference:** plan.md Overview (approved 2026-08-18) fixes
blank `q` = first published page, limit 20, and case-insensitive `name` match;
this WI implements that contract.

The route is public and published-only. The fixed page limit is 20. This WI does
not decide tags, general full-text search, publication readiness, asset linkage,
or admin behavior; those are outside this Plan.

## Success criteria

- `GET /api/community/poses?q=...` returns only published records whose `name`
  contains the query case-insensitively, with the same filtered `total` used by
  the response page.
- Blank or missing `q` returns page one of published results, never draft rows,
  with `pagination.limit == 20`.
- A seeded catalogue larger than 20 returns stable, non-overlapping page-one
  and page-two IDs and the correct total; an empty match returns `data: []`.
- `%`, `_`, and backslash in `q` are matched literally, while parameter binding
  remains intact; no SQL fragment is interpolated from user input.
- Existing public detail behavior and non-search filters are not broadened into
  this WI's scope.

## Risks

- Unescaped SQL LIKE wildcards (`%` and `_`) can turn a title search into a
  broad data disclosure; tests must cover escaped literals and backslash order.
- Offset paging can overlap or skip rows when ordering is unstable or the data
  changes between requests; use deterministic ordering and validate page IDs.
- A published row may still have an unproven ready asset in the existing server
  pipeline; this Plan consumes the published route contract and does not claim
  to repair publication readiness.

## Required evidence

- Focused route/store test output covering every success criterion, including
  21+ records for page two and wildcard literals.
- TypeScript build/lint output for the backend package.
- Direct diff or source inspection showing the public `status = published`
  predicate is shared by count and data queries.
- No mobile live API adapter or unrelated backend/admin files changed as part
  of this planning scope.
