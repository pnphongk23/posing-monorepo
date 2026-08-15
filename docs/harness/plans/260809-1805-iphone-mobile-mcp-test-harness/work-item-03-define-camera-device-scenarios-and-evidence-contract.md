---
work_item: 3
title: Define Camera device scenarios and evidence contract
status: pending
priority: P1
effort: M
dependencies:
  - 2
decision_dependencies: []
---

# Work Item 3: Define Camera device scenarios and evidence contract

**Kind:** verification

## Tasks

- Convert FEAT-001 acceptance and the approved Camera parity matrix into atomic
  real-iPhone scenarios: permission, preview, controls, capture, duplicate tap,
  thumbnail/Gallery, failure recovery, background/foreground, and crash delta.
- Define preconditions, semantic targets/test tags, actions, expected state,
  cleanup, and minimum evidence for every scenario.
- Separate claims Mobile MCP can observe from file/database assertions that need
  app debug hooks, repository probes, or integration tests.
- Define screenshot golden/checklist policy tolerant of device dimensions and
  safe areas without allowing visual drift.
- Add simulator-only scenarios only for states that do not claim physical Camera
  correctness.

## Scope and affected files

- Plan-local design and scenario documents or a focused mobile test directory.
- `CameraScreen.kt` semantics/test tags may be listed as implementation needs,
  but behavior changes belong to the Camera convergence Plan.

## Success criteria

- Every in-scope FEAT-001 acceptance criterion maps to at least one scenario and
  one exact evidence type.
- Every scenario has deterministic setup/cleanup and a non-visual assertion.
- Physical Camera claims explicitly require a real iPhone.

## Risks

- Coordinate-only automation is fragile; use fresh accessibility bounds and
  stable semantics.
- Permission reset and app data reset are destructive; isolate such scenarios
  and request the authorized reset boundary.

## Required evidence

- Reviewed coverage matrix linking FEAT-001 IDs, prototype states, tool calls,
  app assertions, and output files.
- A dry-run validation of selectors/evidence paths on the chosen device without
  claiming unresolved Camera behavior passed.
