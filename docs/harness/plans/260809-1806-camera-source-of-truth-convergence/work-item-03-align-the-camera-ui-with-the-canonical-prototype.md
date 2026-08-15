---
work_item: 3
title: Align the Camera UI with the canonical prototype
status: pending
priority: P1
effort: L
dependencies:
  - 2
decision_dependencies: []
---

# Work Item 3: Align the Camera UI with the canonical prototype

**Kind:** story

## Tasks

- Implement the approved full-bleed preview, safe-area treatment, settings/more,
  zoom, poses shortcut, shutter bar, thumbnail, shutter, and flip composition.
- Render explicit permission, capture-in-flight, success, and failure states from
  the coordinator; remove dead `if (false)` behavior.
- Implement the approved grid/default and static composition guide while keeping
  selected-pose overlay outside this Plan.
- Add stable accessibility labels/test tags, VoiceOver order, dynamic type,
  contrast, hit target, and reduced-motion behavior for critical controls.
- Add focused presentation/layout tests and prototype-vs-app visual checklists
  across supported real-iPhone sizes/orientations.

## Scope and affected files

- `mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt`
- Camera UI components/state/layout models and shared theme/components only when
  the approved prototype requires a reusable token/component correction.
- Common Camera tests and approved visual evidence fixtures.

## Success criteria

- Every approved parity-matrix row is implemented or explicitly marked as a
  later Feature dependency; no unexplained UI divergence remains.
- All controls remain operable with VoiceOver semantics and minimum hit targets.
- Capture remains visually distinct from navigation and does not navigate to
  extraction on normal success.

## Risks

- Pixel matching without safe-area/device normalization can regress smaller
  iPhones; validate structure and tokens, not one hard-coded screenshot.
- Prototype external image URLs cannot be production runtime dependencies.

## Required evidence

- Unit/layout test output, accessibility snapshots, approved prototype and app
  screenshots at named checkpoints, and token-bypass review command/results.
