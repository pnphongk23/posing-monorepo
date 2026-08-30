---
phase: 4
title: "Camera overlay and controls"
status: pending
priority: P0
effort: "5h"
dependencies: ["phase-03"]
---

# Phase 4: Camera Overlay & Controls

## Mục tiêu

Render active pose overlay on Camera with controls (Harness WI-04); re-enable overlay path currently disabled.

## Goals

- Transparent PNG overlay aligned to viewport; default 50% opacity.
- Toggle visibility, adjust opacity, clear active pose.
- Overlay non-interactive; shutter/capture unchanged.

## Non-goals

- Dual-layer source photo background (plan 260510-1726).
- Live skeleton joint detection on camera feed.

## Contracts

### UI

- Prototype: `camera-pose-overlay.html` — banner, joint colors scoped per `design.md` § Camera viewport.
- Harness: FEAT-001 capture semantics unchanged.

### Data

- Read active reference from Phase 2 store only; Camera không giữ parallel copy lâu dài.

## Admin / Ops

- N/A.

## Tasks

1. Connect `CameraScreen` to active reference flow (remove `if (false)` guard at cook).
2. Implement opacity slider or stepped toggle per parity matrix.
3. Clear action resets store + hides overlay.
4. Orientation/layout tests; reduced motion respect.

## Acceptance

- [ ] Overlay visible at 50% default when reference ready.
- [ ] Toggle/clear match prototype semantics.
- [ ] Shutter still captures Photo; overlay not burned into capture unless spec says otherwise (verify FEAT-001).

## Verification

- Compose UI tests (Harness WI-04 list).
- Visual compare prototype screenshot optional.

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Overlay aspect mismatch | Medium | Letterbox scale; maintain aspect |
| Performance on old devices | Medium | Bitmap size cap at prepare |

## Rollout / Rollback

Disable overlay via revert Phase 4 commits; state store may remain harmless.

## Gate

Phase 3 navigation merged + device smoke test.
