---
work_item: 4
title: Complete native iOS controls and lifecycle behavior
status: pending
priority: P1
effort: L
dependencies:
  - 3
decision_dependencies: []
---

# Work Item 4: Complete native iOS controls and lifecycle behavior

**Kind:** technical

## Tasks

- Evolve `CameraController` results to explicit success/failure/cancellation with
  capture identity; marshal callbacks onto the owned UI/state dispatcher.
- Implement effective start/stop preview and app foreground/background handling;
  release hardware locks and cancel active capture on interruption.
- Ensure facing, zoom, flash, grid, and approved frame-ratio behavior reach the
  native layer or remove/disable any control the approved Feature narrows.
- Report native configuration/capture failures rather than using empty bytes as
  an undifferentiated signal.
- Add bridge-level tests/fakes where possible and real-iPhone scenarios for every
  physical control claim.

## Scope and affected files

- `mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraContract.kt`
- `mobile/composeApp/src/iosMain/kotlin/com/aipose/camera/**`
- `mobile/iosApp/iosApp/CameraViewController.swift`
- iOS app lifecycle wiring only where required for Camera ownership.

## Success criteria

- Start/stop are not no-ops; interruption/re-entry yields one healthy preview and
  no stuck capture.
- Each exposed control has observable native/captured-output evidence on a real
  iPhone; unsupported hardware states produce truthful UI.
- Simulator behavior is explicitly a fixture/unsupported result and never counts
  as successful physical capture.

## Risks

- MijickCamera API/version constraints and native session threading must be
  verified from resolved dependency source before implementation.
- Flash availability varies by facing/device; model capability rather than
  promising all modes unconditionally.

## Required evidence

- Resolved native dependency/API citations, iOS compile/build logs, lifecycle
  recording, real-device control matrix, and crash-list delta.
