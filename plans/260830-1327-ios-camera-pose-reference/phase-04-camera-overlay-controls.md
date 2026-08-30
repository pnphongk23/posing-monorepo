---
phase: 4
title: "Durable overlay ownership"
status: pending
priority: P0
effort: "5h"
dependencies: ["phase-03"]
---

# Phase 4: Durable Overlay Ownership

## Mục tiêu

Rebind `CameraScreen` overlay từ session-only `PreparedPoseReference` sang **`ActivePoseReference` single owner**; giữ behavior render/controls hiện hữu (Harness WI-04 scope adjustment).

## Goals

- Read overlay asset from durable store + managed cache (restore after relaunch).
- **Preserve:** opacity default ~50%, Show/Hide toggle, opacity slider, line color, **pan/zoom** (`detectTransformGestures`).
- Add explicit **clear** action: clear durable reference + hide overlay (2241) — không chỉ đóng tab về Poses.
- Capture/shutter unchanged (FEAT-001).

## Non-goals

- Remove pan/zoom (không có authority ngược lại).
- Dual-layer source background (plan `260510-1726`).
- Re-enable fictional `if (false)` guard — **không tồn tại** trong code hiện tại; chỉ stale comments.

## Contracts

### UI

- Prototype visual reference: `camera-pose-overlay.html`.
- Overlay gestures **interactive** cho pan/zoom/opacity — camera preview gestures coexist; không claim “non-interactive overlay”.

### Data

- Camera composable consumes `ActivePoseReference` only after Phase 2/3; no parallel stale session copy after relaunch.

## Tasks

1. Replace `PoseServiceLocator.preparedReference`-only `remember` keying with durable store observer.
2. Implement clear control per 2241 (More menu or dedicated control per parity matrix).
3. Update stale `Navigation.kt` / harness docs comments at cook (optional separate hygiene).
4. Regression tests: pan/zoom/opacity/toggle with durable fixture.

## Acceptance (future cook)

- [ ] Relaunch → overlay restored from durable store.
- [ ] Clear → empty state + cache evicted.
- [ ] Pan/zoom/opacity/toggle match pre-cook behavior snapshots/tests.

## Verification

- Compose UI tests (Harness WI-04 adapted).
- Manual pan/zoom smoke on device.

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Gesture conflict | Medium | Keep existing `pointerInput` pattern |
| Aspect mismatch | Medium | Existing `ContentScale.Fit` + padding |

## Rollout / Rollback (future execution)

Revert durable binding; session overlay remains as today.

## Gate

Phase 3 promotion merged + device smoke.
