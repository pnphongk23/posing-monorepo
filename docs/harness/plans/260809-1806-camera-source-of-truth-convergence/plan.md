---
title: Camera Source of Truth Convergence
description: Reconcile Camera authority, align the iOS app with the canonical documents and prototype, and verify it on a real iPhone.
status: pending
approval:
  status: pending
  required_by: Repository Maintainer
priority: P1
effort: XL
branch: codex/camera-source-of-truth-convergence
tags: [camera, ios, compose, prototype, source-of-truth]
blockedBy:
  - 260809-1805-iphone-mobile-mcp-test-harness
blocks: []
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[product-feature-inventory]]"
    - "[[ui-ux-system]]"
  decisions: []
  plans: []
  reports: []
  rules: []
  features:
    - "[[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]"
  source_paths:
    - docs/harness/plans/260809-1806-camera-source-of-truth-convergence/design.md
    - docs/harness/plans/260809-1805-iphone-mobile-mcp-test-harness/plan.md
    - docs/prototype/screens/camera-live.html
    - docs/prototype/scripts/app.js
    - docs/prototype/styles/components/camera-viewport.css
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera
    - mobile/composeApp/src/iosMain/kotlin/com/aipose/camera
    - mobile/iosApp/iosApp/CameraViewController.swift
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PhotoRepository.kt
    - mobile/shared/src/iosMain/kotlin/com/aipose/data/ImageStorage.kt
created: 2026-08-09T18:06:00+07:00
createdBy: Harness CLI
---

# Camera Source of Truth Convergence

## Overview

Make the Camera implementation converge on a deliberately reconciled pair of
authorities: approved Harness documents define behavior and constraints; the
approved prototype defines layout, visual states, control placement, and
interaction presentation. Current app code is delivery evidence, never a source
of truth. When document and prototype conflict, execution stops until the
Maintainer resolves the parity matrix; no implementer chooses silently.

The recommended delivery slice is iOS only because this request explicitly
requires iPhone testing and the repository has no Android Camera actual. This
does not complete FEAT-001's Android acceptance. See [design.md](./design.md) for
the Camera-only brainstorm, alternatives, recommendation, and unresolved human
choices.

Grounding findings:

- **Verified:** FEAT-001 is `draft`, so the Authority Closure Gate is not met.
- **Verified:** the prototype redirects shutter capture to extraction while
  FEAT-001 requires staying on Camera; this is a direct authority conflict.
- **Verified:** the prototype flip control navigates to an overlay screen rather
  than switching hardware Camera; its label and document intent disagree.
- **Verified:** `CameraScreen` owns UI, permission, native control, persistence,
  and transient feedback in one composable; only layout helpers have tests.
- **Verified:** grid/overlay rendering is disabled by `if (false)`, frame ratio
  changes only Compose state, and native `start`/`stop` bridge commands are no-ops.
- **Verified:** capture write then metadata insert lacks rollback/readability
  verification; filenames have second-level collision risk; native callbacks
  have no timeout.
- **Verified:** the simulator returns empty capture bytes and cannot prove real
  Camera behavior.

## Work Items

- [Work Item 1: Close Camera authority and build the parity matrix](./work-item-01-close-camera-authority-and-build-the-parity-matrix.md)
- [Work Item 2: Refactor Camera state and capture orchestration](./work-item-02-refactor-camera-state-and-capture-orchestration.md)
- [Work Item 3: Align the Camera UI with the canonical prototype](./work-item-03-align-the-camera-ui-with-the-canonical-prototype.md)
- [Work Item 4: Complete native iOS controls and lifecycle behavior](./work-item-04-complete-native-ios-controls-and-lifecycle-behavior.md)
- [Work Item 5: Make capture persistence atomic and recoverable](./work-item-05-make-capture-persistence-atomic-and-recoverable.md)
- [Work Item 6: Verify Camera behavior from unit tests through real iPhone](./work-item-06-verify-camera-behavior-from-unit-tests-through-real-iphone.md)

## Coverage

| FEAT-001 / design objective | Work Items |
| --- | --- |
| Authority closure and document/prototype parity | 1 |
| FR-001 permission gating and recovery | 2, 4, 6 |
| FR-002 duplicate capture protection | 2, 5, 6 |
| FR-003 exactly one file and metadata record | 5, 6 |
| FR-004 facing, zoom, flash, grid, frame ratio | 3, 4, 6 |
| FR-005 latest thumbnail and Gallery navigation | 2, 3, 6 |
| FR-006 readable-file verification | 5, 6 |
| BR-001 no broken metadata path | 5, 6 |
| NFR-001 offline Camera operation | 4, 5, 6 |
| Prototype visual/interaction convergence | 1, 3, 6 |
| Lifecycle interruption and late callback recovery | 2, 4, 5, 6 |

## Verification ledger

| Claim | Status | Evidence |
| --- | --- | --- |
| FEAT-001 can authorize implementation now | Failed | status is `draft` |
| Document and prototype currently agree on shutter flow | Failed | FEAT main flow vs `docs/prototype/scripts/app.js:157-162` |
| Frame ratio reaches native camera | Failed | `CameraScreen.kt:121-123`; no controller API |
| Preview lifecycle start/stop is effective | Failed | Swift bridge treats commands as no-op |
| Capture persistence is atomic/read-verified | Failed | `CameraScreen.kt:330-339`; `ImageStorage.kt` |
| Android is implementable in this Plan | Failed | no Android Camera actual/preview |
| Existing Camera behavior has automated coverage | Partially verified | layout model tests only; no orchestration/device tests |
| Real iPhone evidence path is ready | Failed | dependent Plan preflight not complete |

## Verification

- Unit/state-machine tests for permission, duplicate/late callbacks, timeout,
  controls, persistence compensation, and lifecycle transitions.
- `./gradlew :composeApp:allTests :shared:iosSimulatorArm64Test` after repairing
  the existing test dependency gap within explicitly approved scope.
- Signed iOS build plus Mobile MCP real-iPhone scenario matrix from the dependent
  testing Plan, including accessibility snapshots, screenshots, recording,
  crash delta, and file/database evidence.
- Prototype interaction checks for resolved shutter, flip, settings, grid,
  zoom, thumbnail, and pose-navigation behaviors.
- `ckh workflow check 260809-1806-camera-source-of-truth-convergence --workspace .`

Approval remains pending on FEAT-001 approval and the three material choices in
`design.md`. No Cook or application change is authorized by this draft.
