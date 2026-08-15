---
work_item: 4
title: Complete local and community detail flows
status: completed
priority: P1
effort: M
dependencies:
  - 3
decision_dependencies: []
---

# Work Item 4: Complete local and community detail flows

**Kind:** story

## Tasks

- Replace long-ID-only routing with source-qualified keys and inject the shared
  repository/detail loader rather than creating a database inside the view model.
- Add community detail retrieval and published/not-found/error states; map both
  sources into the approved source-specific detail presentation.
- Display the name and every available source field. Map absent author,
  difficulty, or outline values to null, render no fabricated substitute, and
  include no prototype-only social UI.
- Make missing local records show the approved alert and return to My Poses;
  expose recoverable community failures without navigating to a wrong record.
- Expose Try Pose as a typed output contract consumed by the dependent Camera
  handoff Plan, not as a tab change with discarded data.
- Add view-model, route, rendering, missing-record, and API detail tests.

## Scope and affected files

- `PoseDetailScreen.kt`, `Navigation.kt`, detail/domain contracts, repository/API
  service, and focused tests.

## Success criteria

- Personal/community detail routes cannot collide or expose invalid destructive
  actions, and available/null metadata/outline states are explicit.
- Missing and failed detail loads have deterministic recovery behavior.

## Risks

- Backend detail GET increments `downloadCount`; decide whether opening detail is
  intended to mutate analytics before relying on it.

## Required evidence

- Detail contract tests for both sources, navigation tests, missing/error state
  screenshots, and confirmation that excluded social controls are absent.
