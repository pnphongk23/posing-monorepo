---
work_item: 1
title: Close Camera authority and build the parity matrix
status: pending
priority: P1
effort: M
dependencies: []
decision_dependencies: []
---

# Work Item 1: Close Camera authority and build the parity matrix

**Kind:** docs

## Tasks

- Obtain Maintainer decisions for Approach B, iOS-only delivery slice, and every
  conflict listed in `design.md`.
- Update FEAT-001 and linked specs so approved behavior, platform scope, static
  guide versus selected-pose overlay, defaults, and evidence are unambiguous.
- Update the Camera prototype so shutter, flip, grid/default, ratio, and thumbnail
  interactions demonstrate the approved behavior rather than contradictory mock
  navigation.
- Build a parity matrix for all Camera states: initial/permission, preview,
  settings, grid, zoom, capture in-flight, success, failure, and interruption.
- Approve FEAT-001 through the proper Feature workflow before requesting Plan
  approval; regenerate/check Harness graph.

## Scope and affected files

- `docs/harness/features/FEAT-001-capture-a-photo-on-mobile.md`
- `docs/harness/specs/product-feature-inventory.md`
- `docs/harness/specs/technical-architecture.md`
- `docs/harness/specs/ui-ux-system.md`
- `docs/prototype/screens/camera-live.html`, Camera scripts/styles, and prototype
  README only where needed to express approved Camera authority.

## Success criteria

- FEAT-001 is approved, no blocking Camera Decision remains, and document versus
  prototype precedence is explicit.
- Every Camera control/state has one approved behavior and visual mapping; zero
  unresolved parity conflicts remain.
- Prototype no longer redirects a normal shutter capture to extraction or uses
  flip as unrelated navigation unless the Maintainer explicitly chooses that.

## Risks

- The prototype files contain preserved user edits; make surgical changes only
  after comparing the current diff.
- Calling an iOS slice complete must not imply Android FEAT delivery.

## Required evidence

- Approved Feature provenance, graph/index checks, prototype interaction run,
  parity matrix, and `git diff` proving Camera-only documentation scope.
