---
title: Selected Pose Camera Handoff
description: Persist a selected personal or community transparent pose image across relaunch and render a controllable Camera overlay with real-device evidence.
status: pending
approval:
  status: pending
  required_by: Repository Maintainer
priority: P1
effort: L
branch: codex/selected-pose-camera-handoff
tags:
  - camera
  - pose-overlay
  - navigation
  - ios
  - compose
  - persistence
blockedBy:
  - 260809-2240-pose-reference-library-convergence
  - 260809-1806-camera-source-of-truth-convergence
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
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]"
  source_paths:
    - docs/harness/plans/260809-2241-selected-pose-camera-handoff/design.md
    - docs/prototype/screens/pose-detail.html
    - docs/prototype/screens/camera-pose-overlay.html
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraState.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt
created: 2026-08-09T22:41:00+07:00
createdBy: Harness CLI
---

# Selected Pose Camera Handoff

## Overview

Deliver FEAT-003's final user outcome after the library can resolve a typed
personal/community reference and the Camera convergence Plan supplies a stable
Camera coordinator. Tapping Try Pose must download/read and decode the existing
transparent pose image, durably persist the source-qualified selection and
managed render asset, switch to Camera only after success, render it at 50%
default opacity, and support prototype-presented clear/toggle actions without
changing capture semantics. The selection survives app termination and relaunch
until replaced or cleared.

The app currently switches tabs without transferring the pose; Camera owns
local state, receives no selection input, and its overlay rendering is disabled
behind `if (false)`. The existing `OverlaySourceState.PoseImage` is useful
evidence but not yet an application-level ownership contract.

## Work Items

- [Work Item 1: Close selected-pose handoff and overlay authority](./work-item-01-close-selected-pose-handoff-and-overlay-authority.md)
- [Work Item 2: Introduce a shared active pose reference contract](./work-item-02-introduce-a-shared-active-pose-reference-contract.md)
- [Work Item 3: Wire local and community Try Pose navigation](./work-item-03-wire-local-and-community-try-pose-navigation.md)
- [Work Item 4: Render and control the active Camera overlay](./work-item-04-render-and-control-the-active-camera-overlay.md)
- [Work Item 5: Verify the handoff through real iPhone evidence](./work-item-05-verify-the-handoff-through-real-iphone-evidence.md)

## Coverage

| Objective | Work Items |
| --- | --- |
| Authority, ownership, persistent lifetime, prototype parity | 1 |
| Typed persistent active-reference state and managed render asset | 2 |
| Local/community Try Pose navigation | 3 |
| Camera guide render/toggle/clear and capture coexistence | 4 |
| FEAT-003 scenario and real-iPhone evidence | 5 |

## Verification

- State-store tests for select/replace/clear, source identity, atomic persistence,
  terminate/relaunch restoration, corrupt-state recovery, and managed cache cleanup.
- Navigation tests proving both detail variants set state before switching tabs
  and never route Camera with a missing/unresolvable reference.
- Camera presentation tests for the existing transparent image, 50% default
  opacity, prototype control semantics,
  orientation/layout, loading/failure fallback, and unchanged shutter behavior.
- Real-iPhone Mobile MCP scenario with accessibility snapshot, screenshots or
  recording, crash delta, and selected-reference evidence.
- `ckh workflow check 260809-2241-selected-pose-camera-handoff --workspace .`.

The material choices are resolved in `design.md`. Approval remains pending on
FEAT-001 authority and completion of both prerequisite Plans. FEAT-003 carries
the relaunch persistence acceptance governing this Plan.
