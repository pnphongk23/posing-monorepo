---
title: "ios-camera-pose-reference"
description: "Lane BACKLOG — durable Try Pose → Camera handoff trên iOS; bổ sung executable phases cho Harness plan 260809-2241."
status: pending
priority: P0
branch: "backlog/ios-camera-pose-reference"
tags: ["ios", "camera", "pose-overlay", "try-pose", "feat-003", "feat-008"]
blockedBy:
  - "docs/harness/plans/260809-2240-pose-reference-library-convergence"
  - "docs/harness/plans/260809-1806-camera-source-of-truth-convergence"
created: "2026-08-30T13:27:00+07:00"
source_report: "docs/harness/reports/REP-012-backlog-lane-documentation-survey.md"
harness_plan: "docs/harness/plans/260809-2241-selected-pose-camera-handoff/plan.md"
---

# iOS Camera Pose Reference (Try Pose Handoff)

## Overview

**Hiện trạng (evidence, không claim ship durable):**

- `REP-006` `E-TRY-EMIT`: Try Pose thành công → `PoseServiceLocator.preparedReference` + chuyển `CameraTab`.
- `CameraScreen.kt`: đã render overlay khi có reference session-scoped — opacity/toggle, **pan/zoom** (`detectTransformGestures`), line color.
- `REP-006` `E-2241-BOUNDARY` (2026-08-19) ghi `CameraScreen.kt:173` = `if (false)` — **stale**; line 173 hiện là `LaunchedEffect(permissionState)`. Comment tương tự còn trong `Navigation.kt:282`.
- `prepared-pose-reference.md` `BR-PREPREF-002`: transient — **không** persist qua relaunch.

**Vấn đề còn lại:** thiếu **durable** `ActivePoseReference` (app-level), promotion/migration từ transient `PreparedPoseReference`, managed cache path, clear/replace lifecycle, restore sau relaunch theo FEAT-008 + Harness plan `260809-2241`.

**Phạm vi plan lane BACKLOG:** ghi contract freeze + phases cho **future cook handoff** — không phải Maintainer approval hay ship claim.

Plan này **không thay** Harness authority — map WI 2241 sang phase executable tại `plans/` root.

## Goals

- Promote Try Pose success → durable `ActivePoseReference` + managed render asset trước/sau vào Camera.
- Giữ overlay behavior hiện hữu: default opacity ~50%, toggle, **pan/zoom**, line color — không loại bỏ gesture overlay trừ khi Harness đảo authority.
- Selection + render asset survive app termination + relaunch until replaced/cleared.
- Clear lifecycle explicit (clear action + cache cleanup); không chỉ ẩn overlay trong session.
- Shutter / capture semantics unchanged (FEAT-001).

## Non-goals

- Saved Poses server sync (FEAT-008 Phase 3 business).
- Paywall / entitlement gates (FEAT-011).
- Dual-layer source image background (plan `260510-1726`).
- Admin UI hoặc extract server changes.
- Android build target.
- Re-build overlay render từ đầu (đã partial — scope là ownership + persistence).

## Contracts (frozen)

### API

- **Không HTTP mới.** Try Pose local prepare; community skeleton qua catalogue URL hiện có.
- Lỗi fetch/decode: `docs/spec/api/conventions.md` khi community fail.

### Data — hai lớp reference

| Contract | Layer | Authority | Fields / semantics |
| --- | --- | --- | --- |
| `PreparedPoseReference` | **Transient** (in-memory emit) | `docs/spec/data/entities/prepared-pose-reference.md` | `poseId`, `mediaId`, `name`, `skeletonLocator` (spec); runtime code hiện `poseId`, `poseName`, `skeletonPath` — **migration target** align spec tại cook |
| `ActivePoseReference` | **App-level durable** | Harness plan 2241 `design.md` + FEAT-008 | `poseId`, `mediaId`, `skeletonLocator` → **managed cache path** on disk; `source` discriminator: `local` \| `community`; lifecycle: `select` → persist → restore → `clear` \| `replace` |

**Promotion mapping (cook):**

```text
Try Pose prepare OK
  → emit PreparedPoseReference (transient, BR-PREPREF-003 verify)
  → promote/copy to ActivePoseReference
  → write managed cache file (collision-resistant path)
  → Camera reads ActivePoseReference (single owner), not parallel PoseServiceLocator-only session
```

**Không tạo** entity `CommunityPose` mới — dùng canonical `Pose` + `MediaAsset` terminology; community chỉ là `source = community` trên reference.

**Migration / clear / restore:**

- Relaunch: read durable store → restore `ActivePoseReference` + validate cache file → render or empty state + recovery.
- Clear: null durable record + delete managed cache (best-effort).
- Replace: atomic swap reference + evict prior cache.
- **Authority gate:** Phase 1 parity + Maintainer approve Harness 2241 trước cook Phase 2+.

### UI

- Visual: `docs/prototype/screens/camera-pose-overlay.html`, `design.md` / `tokens.css`.
- Interaction: `docs/harness/specs/ui-ux-system.md` § Camera; **preserve** pan/zoom overlay gestures (`CameraScreen.kt:274-280`).
- Controls hiện hữu: Show/Hide, opacity slider, line color — gắn durable reference, không rewrite UX.

### Admin / Ops

- Không đổi admin surface.
- Future cook: Mobile MCP real iPhone evidence (Harness WI-05).

## Parity matrix (camera handoff)

| Khía cạnh | Prototype | Harness 2241 | Current code | Residual gap (scope plan) |
| --- | --- | --- | --- | --- |
| Try Pose → Camera | Mock notice | Prepare + navigate | `E-TRY-EMIT` session handoff | Durable promotion + store |
| Overlay render | Static HTML | 50% default PNG | `AsyncImage` when `hasOverlay` | Bind `ActivePoseReference` |
| Opacity / toggle | Demo controls | Toggle + opacity | More menu + Slider | Wire to durable owner |
| Pan / zoom | N/A | Not forbidden | `detectTransformGestures` | **Keep** — out of removal scope |
| Relaunch | N/A | Must restore | BR-PREPREF-002 no persist | **Primary gap** |
| Clear | N/A | Clear until replaced | Close tab keeps reference | Explicit clear + cache |

## Phases

| Phase | Name | File | Effort |
| --- | --- | --- | --- |
| 1 | Authority & parity matrix | [phase-01-authority-and-parity.md](./phase-01-authority-and-parity.md) | 2h |
| 2 | Active pose reference state | [phase-02-active-pose-reference-state.md](./phase-02-active-pose-reference-state.md) | 4h |
| 3 | Try Pose promotion wiring | [phase-03-try-pose-navigation-wiring.md](./phase-03-try-pose-navigation-wiring.md) | 3h |
| 4 | Durable overlay ownership | [phase-04-camera-overlay-controls.md](./phase-04-camera-overlay-controls.md) | 5h |
| 5 | Verification handoff | [phase-05-verification-rollout.md](./phase-05-verification-rollout.md) | 4h |

## Phase dependencies

```text
Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5
Prerequisites (Harness): 260809-2240, 260809-1806 authority closure
```

## Acceptance (plan-level — future cook)

- [ ] Try Pose promote `ActivePoseReference` trước/khi vào Camera; transient không phải sole owner sau relaunch.
- [ ] Relaunch restore overlay hoặc explicit empty/recovery state (FEAT-008 / 2241).
- [ ] Clear/replace lifecycle + managed cache cleanup.
- [ ] Pan/zoom/opacity/toggle behavior preserved vs current `CameraScreen.kt`.
- [ ] Capture Photo local không regression FEAT-001.
- [ ] `ckh workflow check 260809-2241-selected-pose-camera-handoff` pass tại cook time.

## Verification

| Layer | Evidence |
| --- | --- |
| Unit | Active reference store select/replace/clear/relaunch |
| Navigation | Promotion after Try Pose prepare |
| Compose | Overlay bound to durable reference; pan/zoom regression |
| Device | Mobile MCP real iPhone (Harness WI-05) |

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Prerequisite plans chưa land | High | Gate Phase 2+ cook |
| Spec/code field drift (`skeletonPath` vs `skeletonLocator`) | Medium | Migration table in Phase 2 |
| Large image decode | Medium | Managed cache downscale at promote |
| Stale Navigation comment | Low | Update comment at cook; docs không sửa code trong lane này |

## Rollout / Rollback (future execution)

**Rollout (cook handoff):** ship sau real-iPhone evidence + Maintainer approve 2241 — **không** approval từ plan docs lane.

**Rollback:** revert durable store; fallback session `PreparedPoseReference` behavior như hiện tại.

## Gates

| Gate | Owner |
| --- | --- |
| Harness 2241 approval | Repository Maintainer |
| Prerequisites 2240/1806 | Maintainer |
| REP-012 remediation | Lead |
| Real-iPhone evidence | Executor / QA at cook |

## Cross-references

- Roadmap: [`../260830-1327-snap-pose-roadmap/roadmap.md`](../260830-1327-snap-pose-roadmap/roadmap.md)
- Survey: [`docs/harness/reports/REP-012-backlog-lane-documentation-survey.md`](../../docs/harness/reports/REP-012-backlog-lane-documentation-survey.md)
- Harness: [`docs/harness/plans/260809-2241-selected-pose-camera-handoff/plan.md`](../../docs/harness/plans/260809-2241-selected-pose-camera-handoff/plan.md)
- Relaunch authority: FEAT-008; session emit: `REP-006` `E-TRY-EMIT`
