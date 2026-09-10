---
phase: 4
title: "Verification and freeze evidence"
status: pending
priority: P2
effort: ""
dependencies:
  - 2
  - 3
---

# Phase 4: Verification and freeze evidence

## Objective

Prove the hydrated implementation against the accepted contracts and record limitations for the already-approved final plan. This phase does not alter the frozen `PLAN_FINAL.md`, launch another review, reindex, commit, or claim device parity.

## Verification matrix

- Shared/mobile contract: query forwarding, published-only projection, blank omission, page sequencing, stale-generation protection, dedupe, refresh replacement, failure retention, retry, and explicit empty.
- Search UI: blank/query transition with an instrumented assertion that initial/blank/clear paths never dispatch `communityPaging.search("")`, no local result/callback seam, published cards, loading, empty, error/retry, load-more, query reset, and existing detail/back/search-icon wiring.
- Gallery UI: combined reactive local Photo/local Pose flows, accepted pose-name mapping, gallery-empty/filter-empty, metadata-only nonmatches, unresolved non-local link exclusion, cancel/reuse load lifecycle, re-entry ownership, and dense 3-column geometry.
- Path audit: `SearchViewModel` remains in `SearchScreen.kt:91-155`; no `SearchViewModel.kt` write path is present. `Navigation.kt:318-324` carries only the published callback.
- Boundary audit: no changes to viewer/detail/delete/export/share/save or `plans/260909-1137-gallery-photo-viewer-v2`.

## Checks

Run, as available in the repository:

- `./gradlew :shared:iosSimulatorArm64Test`
- `./gradlew :composeApp:iosSimulatorArm64Test`
- `cd web/services/pose-extract-server && npm test -- --run src/routes/communityRoutes.test.ts`
- `cd web/services/pose-extract-server && npm run lint`
- `ak plan validate plans/260910-1151-search-gallery-list-refresh --json`

Record command results and any unavailable simulator/device evidence. Android has no configured target; real iPhone live-server evidence and public-asset readiness remain unresolved. Do not convert these gaps into invented acceptance claims.

## Implementation steps

1. Run the focused tests, then the relevant shared/compose/backend checks.
2. Inspect changed-file boundaries and confirm only the approved source/test write sets were touched by implementation; `PhotoRepository.kt`, `PoseRepository.kt`, `Photo.sq`, and `Pose.sq` remain unchanged dependencies.
3. Validate this plan directory and record its deterministic candidate identity from sorted relative filenames plus file bytes.
4. Stop and hand verification evidence to the General Lead for mission-level final validation/reindex/commit decisions; this phase does not launch another reviewer.

## Acceptance criteria

- [ ] Relevant checks pass or failures are recorded with an actionable owner; plan validation reports zero errors.
- [ ] Evidence distinguishes mock/unit coverage from live server and physical-device evidence.
- [ ] Search query-trigger tests prove only trimmed nonblank query intent dispatches community search; blank/clear is in-memory.
- [ ] Gallery lifecycle tests prove one active combined collector across cancellation/re-entry, and filter tests exclude null/empty-name unresolved links without metadata matching.
- [ ] Scope boundary is clean: PLAN_FINAL remains frozen; no additional reviewer, reindex, commit, viewer-plan, or unrelated-doc mutation occurs in this lane.
