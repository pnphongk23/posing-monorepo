---
work_item: 2
title: Refactor Camera state and capture orchestration
status: pending
priority: P1
effort: L
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 2: Refactor Camera state and capture orchestration

**Kind:** technical

## Tasks

- Introduce the approved state/action coordinator and explicit Camera, storage,
  repository, ID/clock, and timeout ports without changing navigation contracts.
- Model permission, preview, capturing, persisting, success, recoverable error,
  lifecycle active/inactive, cancellation, timeout, and late/duplicate callback.
- Make `CameraScreen` render state and dispatch actions rather than directly
  orchestrating native callbacks and persistence.
- Preserve one active capture ID; invalidate it on timeout/interruption and ignore
  or clean up late results deterministically.
- Add unit tests for all transitions before adapting native/UI behavior.

## Scope and affected files

- `mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt`
- `CameraState.kt`, `CameraContract.kt`, and new narrowly scoped coordinator/port
  files under the same package.
- `mobile/composeApp/src/commonTest/kotlin/com/aipose/camera/**`

## Success criteria

- UI has no direct file/database transaction and no unbounded capture-in-flight
  state.
- Duplicate tap, timeout, backgrounding, failure, and late callback transitions
  are deterministic and unit tested.
- Existing visible behavior remains unchanged until the UI/native Work Items
  deliberately switch it to approved behavior.

## Risks

- Kotlin/Native callback threading may mutate Compose state off-main; define and
  test dispatch ownership.
- Over-generalizing the coordinator would expand scope; keep it Camera-specific.

## Required evidence

- State transition table, focused unit test output, compile output for iOS
  simulator/device targets, and review showing no persistence calls in UI code.
