---
work_item: 4
title: Execute and report the iPhone baseline
status: pending
priority: P1
effort: M
dependencies:
  - 3
decision_dependencies: []
---

# Work Item 4: Execute and report the iPhone baseline

**Kind:** verification

## Tasks

- Run native unit/build prerequisites and stop on failed required gates.
- Install/launch the identified build and execute the approved baseline scenario
  matrix in a controlled order, refreshing elements after each transition.
- Save screenshots and one recording for timing/lifecycle flows; capture crash
  list before and after, retrieving new crash dumps when present.
- Collect application-level file/database evidence for successful capture and
  partial-failure scenarios.
- Publish a Harness report with Passed/Failed/Blocked/Not tested results,
  environment, evidence paths, limitations, cleanup, and follow-up gaps.

## Scope and affected files

- Test evidence/report locations selected by Harness conventions.
- No product fix is permitted in this Work Item; failures feed the Camera Plan.

## Success criteria

- The baseline is reproducible from recorded inputs and contains no ambiguous
  pass based only on screenshot appearance.
- New crashes, stuck capture, orphan files/records, or untestable controls are
  reported as failures/blockers, not silently retried into a pass.
- Device/tunnel/recording state is deliberately cleaned up without deleting app
  data unless an approved scenario requires it.

## Risks

- Real-device availability and signing are external blockers.
- Screen recordings and screenshots may contain personal data; use controlled
  scenes and apply the approved retention policy.

## Required evidence

- Native command logs; Mobile MCP action trace; semantic snapshots; screenshots;
  recording; crash delta; file/database assertions; final Harness validation.
- Explicit phrase `Tôi không thể xác minh điều này hoạt động vì...` for every
  claim blocked by unavailable real-device evidence.
