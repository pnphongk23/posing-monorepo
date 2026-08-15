---
work_item: 4
title: Render and control the active Camera overlay
status: pending
priority: P1
effort: L
dependencies:
  - 3
decision_dependencies: []
---

# Work Item 4: Render and control the active Camera overlay

**Kind:** story

## Tasks

- Remove dead overlay gating and render the approved descriptor above preview
  using the existing transparent pose image with correct scaling, safe areas,
  orientation, 50% default opacity, pointer behavior, and pose title/active
  indication from Camera coordinator state.
- Implement toggle/clear/replace controls with prototype-owned placement and
  presentation plus accessible labels/test tags. Clear removes persistent active
  state/cache but never the source pose; keep grid/static composition guide
  visually and semantically distinct.
- Model loading/unavailable/decoding failure without crashing or obscuring the
  shutter; apply the approved fallback and retry path.
- Verify overlay does not alter camera facing, zoom, flash, frame ratio, shutter,
  persistence, preview lifecycle, or offline capture invariants.
- Add presentation/layout/accessibility and coordinator integration tests across
  supported sizes/orientations and both reference origins.

## Scope and affected files

- Camera common UI/state/coordinator and approved resource/decoder boundaries;
  native bridge only if the chosen render path genuinely requires it.

## Success criteria

- Selected outline is visibly identifiable, semi-transparent, controllable, and
  non-interactive over a functioning Camera preview.
- Clearing/toggling never deletes or mutates the underlying pose record.
- After relaunch, a valid persisted reference renders visibly at 50% opacity;
  cleared or invalid persisted state never resurrects or blocks Camera.

## Risks

- Async image composition can flash the previous pose; identity-key all loads
  and ignore stale completions.
- Large transparent raster assets can increase decode/memory cost; validate the
  managed image before persistence and avoid duplicate decoded copies.

## Required evidence

- State/layout/accessibility test output and named prototype-vs-app screenshots
  for active, hidden, replaced, unavailable, and cleared states.
