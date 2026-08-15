---
work_item: 1
title: Close selected-pose handoff and overlay authority
status: pending
priority: P1
effort: S
dependencies: []
decision_dependencies: []
---

# Work Item 1: Close selected-pose handoff and overlay authority

**Kind:** decision/authority gate

## Tasks

- Confirm prerequisite Plan outcomes and approve FEAT-001/003 ownership boundary.
- Verify the approved choices in `design.md`: relaunch persistence, existing
  transparent-image rendering, prepare-before-route community behavior, 50%
  default opacity, and prototype-presented toggle/clear controls.
- Add parity rows for personal/community Try Pose, selection replacement,
  missing/unavailable asset, toggle/clear, back navigation, orientation, and
  capture coexistence; update authority/prototype together on conflict.
- Freeze typed active-reference and Camera input/output contracts before code.

## Scope and affected files

- FEAT-001, FEAT-003, both Plan designs, Camera prototype, and linked specs.

## Success criteria

- No implementer must infer render representation, persisted lifetime, cache
  cleanup, opacity/control behavior, or unavailable-source recovery.

## Risks

- Treating the prototype SVG and extracted transparent raster as equivalent can
  produce an overlay that passes navigation but violates the user-visible goal.

## Required evidence

- Approved Features/decisions, resolved parity matrix, prerequisite workflow
  status, and successful Harness validation.
