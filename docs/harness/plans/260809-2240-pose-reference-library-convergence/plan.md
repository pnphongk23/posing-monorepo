---
title: Pose Reference Library Convergence
description: Deliver the approved iOS-first FEAT-003 personal/community pose library with mock-first replaceable community title search.
status: completed
approval:
  status: approved
  required_by: Repository Maintainer
  decided: 2026-08-09
priority: P1
effort: XL
branch: codex/pose-reference-library-convergence
tags:
  - poses
  - ios
  - compose
  - community
  - search
  - persistence
blockedBy: []
blocks:
  - 260809-2241-selected-pose-camera-handoff
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[product-feature-inventory]]"
    - "[[ui-ux-system]]"
  decisions: []
  plans: []
  reports:
    - "[[REP-003-pose-reference-library-convergence-delivery|REP-003]]"
  rules: []
  features:
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
  source_paths:
    - docs/harness/plans/260809-2240-pose-reference-library-convergence/design.md
    - docs/prototype/screens/poses-list.html
    - docs/prototype/screens/pose-detail.html
    - docs/prototype/screens/search.html
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseRepository.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt
    - web/services/pose-extract-server/src/routes/communityRoutes.ts
created: 2026-08-09T22:40:00+07:00
createdBy: Harness CLI
---

# Pose Reference Library Convergence

## Overview

Converge the personal/community pose-library behavior on approved FEAT-003 for
an iOS-first slice. Feature and Spec documents govern behavior and exclusions;
the prototype governs concrete composition and presentation inside that
authority. This Plan ends at a selected pose reference; the cross-tab Camera
handoff and overlay belong to the dependent
`260809-2241-selected-pose-camera-handoff` Plan.

The recommended design is a small testable library coordinator plus explicit
repository/transport/storage ports. It keeps SQLDelight, Ktor, Compose, Voyager,
and the existing backend, while removing hidden construction and silent failure
paths. Community title search is defined behind a replaceable boundary with a
mock adapter for this slice; the absent production server endpoint is deferred.
See [design.md](./design.md) for the approved choices and alternatives.

Grounding findings:

- **Verified:** Product Authority selected an iOS-first slice, mock-first
  replaceable community title search, nullable missing detail fields,
  local-only My Poses deletion, and document-over-prototype behavior authority.
- **Verified:** Community cards accept an `onClick` callback but never apply a
  clickable modifier, and navigation supplies no community callback.
- **Verified:** refresh ignores its argument, pagination appends without ID
  dedupe, and request failures are swallowed.
- **Verified:** the production search action is empty and no search screen route
  exists; the prototype filters one combined fixture collection by title and no
  production server title-search endpoint currently exists.
- **Verified:** only local detail exists; its repository is constructed inside
  the view model, and it lacks FEAT-003 author/difficulty data.
- **Verified:** deletion removes only SQL metadata; `ImageStorage` has no delete
  contract and extracted pose paths may be embedded data rather than files.
- **Verified:** the server already filters list/detail responses to published
  records, but its payload contains fields omitted by the mobile DTO.
- **Verified:** the shared module declares iOS targets only and the existing API
  test source set lacks the coroutine-test dependency used by `runTest`.

## Work Items

- [Work Item 1: Close FEAT-003 authority and freeze library contracts](./work-item-01-close-feat-003-authority-and-freeze-library-contracts.md)
- [Work Item 2: Correct community transport pagination refresh and recovery](./work-item-02-correct-community-transport-pagination-refresh-and-recovery.md)
- [Work Item 3: Implement browsable tabs and dedicated title search](./work-item-03-implement-browsable-tabs-and-dedicated-title-search.md)
- [Work Item 4: Complete local and community detail flows](./work-item-04-complete-local-and-community-detail-flows.md)
- [Work Item 5: Make personal pose deletion atomic and recoverable](./work-item-05-make-personal-pose-deletion-atomic-and-recoverable.md)
- [Work Item 6: Verify iOS library behavior and deferred boundaries](./work-item-06-verify-library-behavior-and-platform-parity.md)

## Coverage

| FEAT-003 objective | Work Items |
| --- | --- |
| Authority closure, platform slice, prototype parity | 1 |
| FR-002/003/008/009, NFR-001 community correctness | 2, 6 |
| FR-001/007/010 tabs, search, empty states | 3, 6 |
| FR-004 local/community detail and missing record | 4, 6 |
| FR-006, BR-001 atomic personal deletion | 5, 6 |
| FR-005 selected pose Camera use | Dependent Plan 260809-2241 |

## Verification

- Reducer/coordinator tests for initial load, tab changes, refresh, pagination,
  ID dedupe, stale/late response handling, retry, and content retention.
- Ktor MockEngine contract tests against representative list/detail success and
  nested error payloads, with production-equivalent JSON configuration.
- SQLDelight/storage integration tests for reactive local updates, missing
  records, file-backed deletion, embedded data, and compensation failures.
- Compose/navigation tests for card activation, dedicated search, both result
  origins, detail variants, destructive confirmation, empty states, retry
  banner, and accessibility semantics.
- Shared search-contract tests run against the initial mock adapter; evidence
  must label the production server adapter as deferred rather than exercised.
- iOS simulator build/tests plus real-iPhone interaction evidence where file
  lifecycle or native rendering matters. Android is outside this approved slice.
- `ckh workflow check 260809-2240-pose-reference-library-convergence --workspace .`.

FEAT-004 extraction and FEAT-005 administration/publication remain external
integration boundaries rather than governing Features for this library slice.
This Plan consumes their existing entry points/contracts without implementing
or claiming their unfinished behavior.
