---
work_item: 3
title: Implement browsable tabs and dedicated title search
status: completed
priority: P1
effort: L
dependencies:
  - 2
decision_dependencies: []
---

# Work Item 3: Implement browsable tabs and dedicated title search

**Kind:** story

## Tasks

- Render My Poses and Community as distinct, accessible tab states matching the
  approved prototype composition; make every pose card keyboard/VoiceOver
  actionable with stable labels/test tags.
- Route the toolbar search action to a dedicated Voyager screen with autofocus,
  clear, dynamic title filtering, mixed-source result identity, and source-aware
  detail routing.
- Define a source-neutral community title-search contract and implement the
  initial deterministic mock adapter without adding a server endpoint. Keep UI,
  domain state, and tests independent of the adapter so a later production
  server implementation can replace it without changing observable behavior.
- Add pull-to-refresh or approved reload controls, retry banner, initial/empty/
  retained-content states, load-more semantics, and extraction/search shortcuts.
- Keep FEAT-004 extraction orchestration outside the library coordinator; the
  CTA invokes a boundary callback rather than embedding extraction state.
- Add reducer and Compose/navigation/accessibility tests for tabs, results,
  empty tips, refresh/retry, card activation, and mixed IDs.

## Scope and affected files

- `PosesScreen.kt`, `PoseCard.kt`, new search screen/state, and `Navigation.kt`.
- Shared design-system components/tokens only for approved reusable corrections.

## Success criteria

- Both card types open the correct detail; search dynamically filters approved
  inputs, preserves source identity, and labels mock-backed community evidence
  as non-production.
- Empty/retry/refresh/load-more states are understandable and accessible while
  retaining existing content as required.

## Risks

- Mock results can be mistaken for production catalog coverage; keep the adapter
  explicit and never claim that the absent server endpoint was exercised.
- Masonry grids and nested scroll sentinels can retrigger pagination repeatedly.

## Required evidence

- Shared search-contract and mock-adapter test output, Compose/navigation test
  output, accessibility semantics snapshot, prototype comparison screenshots,
  and a page/retry state demonstration.
