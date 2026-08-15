---
work_item: 5
title: Verify the handoff through real iPhone evidence
status: pending
priority: P1
effort: M
dependencies:
  - 4
decision_dependencies: []
---

# Work Item 5: Verify the handoff through real iPhone evidence

**Kind:** verification

## Tasks

- Run active-store, detail adapter, navigation, Camera coordinator, layout, and
  accessibility suites plus prerequisite Camera/library regressions.
- Build/install on the approved real iPhone and use the Mobile MCP harness to
  execute personal and community Try Pose scenarios, replacement, toggle/clear,
  unavailable asset, background/resume, terminate/relaunch restore, clear then
  relaunch, orientation, and capture with overlay.
- Capture accessibility snapshots, screenshots or recording, crash/log delta,
  and an observable selected-reference/state artifact at named checkpoints.
- Confirm capture output remains readable, terminate/relaunch restores the same
  source-qualified cached transparent image without network, and clear remains
  cleared across another relaunch without deleting the source pose.
- Record Android execution if included by authority; otherwise retain the
  explicit platform gap and do not claim full FEAT-003 completion.
- Run Harness workflow checks and publish a Report linking every acceptance row.

## Scope and affected files

- Automated tests, Mobile MCP scenario/evidence artifacts, and Harness status/
  Report files only, aside from defects found within approved Plan scope.

## Success criteria

- FEAT-003's community Try Pose scenario is proven end-to-end on a real iPhone,
  relaunch persistence is proven with identity/cache evidence, and no Camera
  regression or crash is observed across the scenario matrix.
- Every platform claim names the actual device/runtime used.

## Risks

- A screenshot alone cannot prove reference identity or capture coexistence;
  combine UI evidence with state/log and saved-output evidence.
- Mobile MCP may automate a connected target differently by tool version; record
  tool inventory/preflight from the prerequisite testing Plan.

## Required evidence

- Exact commands/tool calls, device/build identity, accessibility snapshots,
  screenshot/recording paths, crash delta, selected-reference proof, capture
  artifact proof, pre/post-relaunch persistence/cache proof, clear persistence,
  test reports, and successful Harness workflow check.
