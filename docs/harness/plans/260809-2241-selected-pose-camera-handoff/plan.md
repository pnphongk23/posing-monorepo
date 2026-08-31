---
title: Pose and Camera Settings Relaunch Restore
description: Persist and restore selected pose identity plus user-facing Camera settings across cold relaunch on iOS, reusing PreparedPoseReference transport and session overlay behavior already on main.
status: cancelled
approval:
  status: pending
  required_by: Repository Maintainer
priority: P1
effort: M
branch: codex/pose-camera-relaunch-restore
tags:
  - camera
  - pose-overlay
  - persistence
  - ios
  - compose
  - relaunch
blockedBy: []
blocks: []
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[ui-ux-system]]"
    - "[[product-feature-inventory]]"
  decisions: []
  plans: []
  reports: []
  rules: []
  features:
    - "[[FEAT-012-restore-pose-and-camera-settings-across-relaunch|FEAT-012]]"
    - "[[FEAT-008-use-published-poses|FEAT-008]]"
    - "[[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]"
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
  source_paths:
    - docs/harness/plans/260809-2241-selected-pose-camera-handoff/design.md
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PreparedPoseReference.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseServiceLocator.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PoseDetailScreen.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraState.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraContract.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraLayoutModel.kt
status_reason: Superseded by the new FEAT-012 relaunch restore plan; old plan history and files are retained.
created: 2026-08-09T22:41:00+07:00
createdBy: Harness CLI
---

# Pose and Camera Settings Relaunch Restore

## Status note

Plan này đã bị **cancelled/superseded** bởi `docs/harness/plans/260831-0000-feat-012-relaunch-restore/plan.md` vì Product Authority yêu cầu một Plan mới riêng, giới hạn đúng FEAT-012. Toàn bộ file và lịch sử của Plan cũ được giữ nguyên.

## Overview

Implement **FEAT-012** on top of behavior already **Observed** on `main` @
`ca33cc2`:

- Try Pose verify + emit `PreparedPoseReference` (`PoseDetailScreen.kt:317-351`).
- Session handoff via `PoseServiceLocator.preparedReference` +
  `createTryPoseCameraHandoffAction` (`Navigation.kt:285-291`).
- Overlay + user-facing settings in `CameraUiState` / `CameraZoomUiState`
  (`CameraState.kt:14-27`, `CameraLayoutModel.kt:14-25`, `CameraScreen.kt:104-124`,
  `248-287`, `310-381`).

**Gap (Unresolved):** selection và settings chỉ sống trong session; cold relaunch
mất state (`BR-PREPREF-002`, `REP-012` BL-GAP-01).

Plan này **không** tạo runtime contract mới (`ActivePoseReference`). Giữ
`PreparedPoseReference` làm transport; persist snapshot nhỏ (pose identity +
local asset locator khi có + 8 settings in-scope) và rehydrate khi relaunch.

**Obsolete assumptions removed:** overlay disabled behind `if (false)`; durable
store requiring new active-reference type. Overlay rendering đã **Observed**
shipped — scope còn lại là persistence + restore + lifecycle integration.

Prerequisites `260809-2240` / `260809-1806` delivered; không block execution.

## Work Items

- [Work Item 1: Freeze behavior contract and state matrix](./work-item-01-freeze-behavior-contract-and-state-matrix.md)
- [Work Item 2: Persist and restore pose + camera settings snapshot](./work-item-02-persist-and-restore-pose-and-camera-settings-snapshot.md)
- [Work Item 3: Integrate select, replace, clear, relaunch, and capture](./work-item-03-integrate-select-replace-clear-relaunch-and-capture.md)
- [Work Item 4: Verify cold relaunch and settings on device](./work-item-04-verify-cold-relaunch-and-settings-on-device.md)

## Coverage

| FEAT-012 requirement | Work Items |
| --- | --- |
| FR-001 settings restore independent of pose | 1, 2, 3, 4 |
| FR-002 rehydrate `PreparedPoseReference` after relaunch | 1, 2, 3, 4 |
| FR-003 invalid/corrupt pose fallback | 1, 2, 3, 4 |
| FR-004 replace keeps settings | 1, 3, 4 |
| FR-005 explicit clear keeps settings | 1, 3, 4 |
| FR-006 single-device snapshot | 2 |
| FR-007 capture semantics unchanged | 3, 4 |
| BR-001 verify before emit | 3 (regression) |
| BR-002 clear no ownership change | 1, 3, 4 |
| BR-003 transient state excluded | 1 |
| BR-004 frameRatio out of scope | 1 |
| NFR-001 no crash on corrupt snapshot | 2, 3, 4 |

## Verification ledger

| Claim | Status | Evidence |
| --- | --- | --- |
| `CameraUiState` fields for facing, flash, grid, overlay visibility, opacity, color, offset, scale | **Verified** | `CameraState.kt:14-27` |
| Zoom 1f–3f + slider UI | **Verified** | `CameraLayoutModel.kt:14-25`, `CameraScreen.kt:358-380` |
| Session init from `preparedReference` only | **Verified** | `CameraScreen.kt:104-114` |
| Overlay `AsyncImage` + gestures | **Verified** | `CameraScreen.kt:248-287` |
| Flash/grid/opacity/color controls in More popup | **Verified** | `CameraScreen.kt:310-337` |
| `PreparedPoseReference` fields poseId, poseName, skeletonPath | **Verified** | `PreparedPoseReference.kt:25-29` |
| `PoseServiceLocator.preparedReference` holder | **Verified** | `PoseServiceLocator.kt:12-21` |
| Handoff action | **Verified** | `Navigation.kt:285-291` |
| Try Pose prepare/verify | **Verified** | `PoseDetailScreen.kt:317-351` |
| No relaunch persistence today | **Verified** | `PreparedPoseReference.kt:13-14`, `BR-PREPREF-002` |
| `frameRatio` no user-facing restore requirement | **Verified** | `CameraScreen.kt:338` control exists; **Inferred** no shipped user entry — FEAT-012 BR-004 |
| Persistence implementation | **Unresolved** | WI-02 |
| Real-iPhone cold relaunch matrix | **Unresolved** | WI-04 |

## Verification

- Unit/contract tests: snapshot serialize/deserialize, atomic write, corrupt
  snapshot fallback, replace/clear semantics, settings-only restore.
- Navigation/Camera integration tests: relaunch bootstrap, invalid asset path,
  capture regression (`CameraCoordinator` path unchanged).
- Real-iPhone evidence (WI-04): cold relaunch with valid pose, no pose, corrupt
  pose, all eight settings, replace, clear, capture success, no crash.
- `ckh workflow check 260809-2241-selected-pose-camera-handoff --workspace . --json`

**Approval:** pending — FEAT-012 `proposed`, Plan `pending`; Repository Maintainer
and Product Authority chưa formal approve.
