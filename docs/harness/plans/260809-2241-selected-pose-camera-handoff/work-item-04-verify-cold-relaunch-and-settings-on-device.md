---
work_item: 4
title: Verify cold relaunch and settings on device
status: pending
priority: P1
effort: S
dependencies:
  - 3
decision_dependencies: []
---

# Work Item 4: Verify cold relaunch and settings on device

**Kind:** verification

## Tasks

- Automated matrix: cold relaunch × {no pose, valid pose, corrupt pose} ×
  settings restore; replace; clear; capture after restore.
- Real-iPhone manual or Mobile MCP scenario: terminate app from app switcher,
  relaunch, open Camera — record screenshots/accessibility for all eight settings.
- Confirm no crash on corrupt snapshot injection test.
- Update plan Verification ledger: move persistence + device rows from
  **Unresolved** → **Verified** with evidence IDs.
- Run `ckh workflow check 260809-2241-selected-pose-camera-handoff --workspace . --json`.

## Scope and affected files

- Test targets under `mobile/composeApp/src/commonTest`, `mobile/shared/...Test`
- Delivery report reference in Harness (optional REP; not required in this docs lane)

## Success criteria

- FEAT-012 Acceptance checklist items have **Verified** evidence or explicit
  **Unresolved** with blocker note.
- `./gradlew` focused iOS simulator tests pass for new suites.

## Risks

- Simulator relaunch ≠ physical device kill — iPhone evidence still required for
  FEAT-012 cold relaunch acceptance.

## Required evidence

- Test run log + device scenario notes; ledger updated in `plan.md`.
