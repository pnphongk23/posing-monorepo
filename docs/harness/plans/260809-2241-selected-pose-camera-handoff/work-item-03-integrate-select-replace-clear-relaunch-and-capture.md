---
work_item: 3
title: Integrate select, replace, clear, relaunch, and capture
status: pending
priority: P1
effort: M
dependencies:
  - 2
decision_dependencies: []
---

# Work Item 3: Integrate select, replace, clear, relaunch, and capture

**Kind:** implementation

## Tasks

- **Select/replace:** extend `createTryPoseCameraHandoffAction` /
  `PoseDetailScreen.tryPose` path (`Navigation.kt:285-291`,
  `PoseDetailScreen.kt:317-351`) to persist new pose snapshot; preserve settings.
- **Clear:** explicit clear action removes pose snapshot + overlay; settings and
  source Pose unchanged (no delete/save/publish).
- **CameraScreen:** bootstrap from persisted snapshot on compose, not only
  `remember(preparedReference)` (`CameraScreen.kt:104-124`); sync native
  controller flash/grid/zoom/facing (`CameraContract.kt:43-52`).
- **Relaunch:** app/process restart path loads snapshot before first Camera frame.
- **Capture regression:** verify `CameraCoordinator` capture/persist path
  unchanged; overlay remains non-blocking (`CameraScreen.kt:248-287`).

## Scope and affected files

- `Navigation.kt`, `PoseDetailScreen.kt`, `CameraScreen.kt`, `CameraContract.kt`
- Snapshot API from WI-02

## Success criteria

- Integration tests: replace keeps zoom/flash; clear keeps settings; relaunch
  bootstrap; capture still writes gallery row.
- No regression in Try Pose verify-before-route (BR-001).

## Risks

- `remember(preparedReference)` reset fights persisted bootstrap — single owner
  for initial state required.

## Required evidence

- `TryPoseCameraHandoffTest` or successor + Camera contract tests green.
