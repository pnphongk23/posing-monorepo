---
work_item: 1
title: Freeze behavior contract and state matrix
status: pending
priority: P1
effort: S
dependencies: []
decision_dependencies: []
---

# Work Item 1: Freeze behavior contract and state matrix

**Kind:** decision/authority gate

## Tasks

- Map FEAT-012 FR/BR to persisted vs transient fields using current evidence:
  `CameraUiState` (`CameraState.kt:14-27`), `CameraZoomUiState`
  (`CameraLayoutModel.kt:14-25`), `PreparedPoseReference` (`PreparedPoseReference.kt:25-29`).
- Freeze state matrix columns: field, in-scope restore (Y/N), default on corrupt,
  user-facing control location (`CameraScreen.kt:310-381`).
- Confirm **out of scope:** permission, in-flight capture, capture result, flash
  animation, popup visibility, `frameRatio` (BR-004).
- Confirm **no** `ActivePoseReference`; `PreparedPoseReference` remains transport.
- Document replace vs clear semantics (settings preserved; no ownership change).
- Align `docs/spec/data/entities/prepared-pose-reference.md` BR-PREPREF-002
  change proposal for Maintainer review (docs-only note in matrix; no spec edit
  in this WI unless Maintainer directs).

## Scope and affected files

- FEAT-012, `design.md`, parity matrix artifact in plan folder or WI body table.

## Success criteria

- Implementer có matrix đủ để code WI-02/03 without inferring scope.
- Every FEAT-012 FR/BR row marked in-scope owner WI.

## Risks

- Conflating `CameraUiState.overlaySource` persistence with
  `PreparedPoseReference` rehydrate causes double source of truth.

## Required evidence

- Approved matrix table linked from `plan.md` Coverage section.
- `ckh workflow check` passes after plan tree update.
