---
work_item: 4
title: Search screen prototype parity and paging UX
status: completed
priority: P1
effort: M
dependencies:
  - 3
decision_dependencies: []
---

# Work Item 4: Search screen prototype parity and paging UX

**Kind:** story / Compose UI and interaction states

## Tasks

- Inject/use `CommunitySearchRepository` in the search view model without
  changing `PosesLibraryCoordinator`, browse tabs, Navigation camera handoff, or
  live API wiring. Keep source-qualified Personal and Community result identity.
- Render the first published community page for blank query and page results as
  the user reaches the paging affordance/sentinel. Keep personal local title
  filtering if already rendered by this screen; count the currently rendered
  mixed result set consistently.
- Match the prototype exactly: title `Search`, placeholder `Type a title`, empty
  title `No matching poses`, blank copy `No poses to search yet.`, no-match copy
  `No poses match “{query}”. Try a different title.`, action `Clear search`, and
  count `{n} pose(s)` / `{n} pose(s) for “{query}”`.
- Add explicit initial loading, load-more loading, success, blank empty,
  non-blank no-match, retryable error, and retained-content states. A failed
  load-more must retain prior cards and expose retry; it must not show an
  unconfirmed empty catalogue.
- Preserve autofocus, clear behavior, stale-query protection, accessible
  content descriptions, stable test tags, and card activation callbacks. Use
  existing Neo-Brutalism tokens/components rather than raw Material elevation or
  ripple-only interactions.
- Add ViewModel/state and Compose semantics tests for copy, counts, blank/no-match
  branches, clear, first/page-two loading, duplicate-page suppression, retry
  retention, and error recovery. Where screenshot automation is unavailable,
  record source-level parity evidence instead of claiming a screenshot.

## Scope and affected files

- `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/SearchScreen.kt`
- `mobile/composeApp/src/commonTest/kotlin/com/aipose/ui/screens/poses/SearchViewModelTest.kt`
- Existing pose card components only for compatible test-tag/accessibility hooks
  (`PoseCard.kt:41` and `CommunityPoseCard` at `PosesScreen.kt:466`, same
  `ui/screens/poses` package); no browse-tab or coordinator refactor.
- Read-only visual references: `docs/prototype/screens/search.html`,
  `docs/prototype/scripts/app.js`, `docs/prototype/scripts/fixtures.js`,
  `.rule/convention/neo-brutalism.md`, and `docs/harness/specs/ui-ux-system.md`.

## Predecessors and dependencies

WI-03 is a hard predecessor. The screen cannot claim paging behavior until the
repository contract, mock page-two fixture, and failure semantics are available.
WI-04 does not depend on a live API provider and must not add one.

## Decision dependencies

**Locked contract reference:** plan.md Overview (approved 2026-08-18) locks the
exact prototype copy and community paging through the repository; this WI
implements that contract.

The exact prototype strings and the fixed community paging decisions are locked.
The existing error/retry behavior is a compatibility constraint: confirmed cards
survive failures, stale completions are ignored, and clear returns to blank
query/page one.

## Success criteria

- The screen displays the exact locked title, placeholder, count, empty, no-match,
  and clear-action strings, including curly quotes and singular/plural forms.
- Blank query requests the first community page, a matching query resets to page
  one, and load-more appends only new source-qualified IDs.
- Initial loading, page loading, empty, no-match, error, retry, and retained
  content are distinguishable and testable; retry recovers without fabrication.
- Existing autofocus, clear, personal/community card routing, accessibility
  labels, and stable test tags remain intact or are updated compatibly.
- No `PosesLibraryCoordinator`, browse tab, camera handoff, Android, Admin UI,
  tag/full-text, or live API provider behavior is changed.

## Risks

- Replacing a list provider with pages can accidentally clear personal/community
  results during a load-more failure; assert retained-content behavior.
- A paging sentinel can retrigger repeatedly or append overlapping pages; guard
  by request identity and dedupe before rendering.
- Mock-backed cards can appear production-ready; preserve explicit mock labeling
  or an equivalent truthful indicator without changing the required copy.
- Prototype comparison screenshots and Compose UI infrastructure are not proven
  available; report source/test evidence and any unavailable visual evidence.

## Required evidence

- Compose/common test output for the ViewModel/state contract and copy branches.
- Direct source inspection or available semantics evidence for test tags,
  content descriptions, autofocus, clear, retry, and card routing.
- A page/retry trace showing blank page one, matching query reset, page two,
  duplicate suppression, and retained results after failure.
- Prototype comparison evidence from `search.html`/`app.js`; explicitly mark
  screenshots as Unresolved if the harness cannot capture them.
