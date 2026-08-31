---
work_item: 2
title: Persist and restore pose + camera settings snapshot
status: pending
priority: P1
effort: M
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 2: Persist and restore pose + camera settings snapshot

**Kind:** implementation

## Tasks

- Implement minimal single-device snapshot (reuse existing persistence layer on
  mobile — **Unresolved:** exact store chosen here with path evidence).
- Persist on change: eight settings in-scope + optional pose identity
  (`poseId`, `poseName`, verified local `skeletonPath` or managed file key).
- Atomic write + schema version; corrupt/missing pose → clear pose portion,
  restore settings; corrupt settings → safe defaults (FEAT-012 E1/E2).
- On cold start / Camera entry: load snapshot → apply `CameraUiState` +
  `CameraZoomUiState` → rehydrate `PoseServiceLocator.preparedReference` when
  pose portion valid.
- Copy data-URI assets to managed local file before persist when needed
  (**Inferred** from BR-PREPREF-001).

## Scope and affected files

- `mobile/shared/.../PreparedPoseReference.kt` (read contract only)
- `mobile/shared/.../PoseServiceLocator.kt`
- `mobile/composeApp/.../camera/CameraState.kt`
- `mobile/composeApp/.../camera/CameraLayoutModel.kt`
- New or existing persistence module under `mobile/shared` (path TBD in PR)

## Success criteria

- Unit tests: round-trip all eight settings; pose optional; corrupt pose clears
  overlay but keeps settings; corrupt file → defaults without crash.
- No new runtime type replacing `PreparedPoseReference`.

## Risks

- Partial write leaves pose without asset — must never show broken overlay.

## Required evidence

- Test names + paths in PR; snapshot schema documented in `design.md` or WI notes.
