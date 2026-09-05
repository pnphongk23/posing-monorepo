---
title: FEAT-012 Relaunch Restore
description: "Kế hoạch docs-only cho FEAT-012: khôi phục pose identity và đúng tám nhóm Camera settings sau cold relaunch, dùng lại contract và persistence hiện có."
status: completed
approval:
  status: approved
  required_by: Repository Maintainer
  decided: 2026-09-01
priority: P1
effort: M
branch: codex/feat-012-relaunch-restore
tags:
  - camera
  - pose-overlay
  - persistence
  - ios
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
  reports:
    - "[[REP-012-feat-012-relaunch-restore-delivery|REP-012]]"
  rules: []
  features:
    - "[[FEAT-012-restore-pose-and-camera-settings-across-relaunch|FEAT-012]]"
  source_paths:
    - docs/harness/plans/260831-0000-feat-012-relaunch-restore/design.md
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PreparedPoseReference.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseServiceLocator.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PoseDetailScreen.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraState.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraContract.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraLayoutModel.kt
    - docs/harness/specs/data-contract.md
created: 2026-08-31T00:00:00+07:00
createdBy: Harness CLI
---

# FEAT-012 Relaunch Restore

## Overview

Plan mới này thực hiện riêng **FEAT-012** sau khi Feature đã được Product Authority approve. Baseline tại `main` @ `ca33cc2` đã **Observed**: `PreparedPoseReference` là runtime transport; `PoseServiceLocator.preparedReference` truyền handoff; `CameraUiState` và `CameraZoomUiState` giữ overlay/settings trong session; Try Pose verify trước khi emit. REP-012 BL-GAP-01 ghi nhận gap: state mất sau process death.

Mục tiêu là persist/restore pose identity hợp lệ và đúng tám nhóm Camera settings: `facing`, `flash`, `grid`, guide visibility, opacity, line color, overlay pan/position + scale, và zoom. Restore settings độc lập với pose; pose invalid không crash và không render broken overlay.

Phạm vi loại trừ: Saved Poses, Albums, account sync, history, cloud sync, multi-device behavior, semantics capture/gallery, transient state, `frameRatio`, dependency mới, và runtime model mới. `PreparedPoseReference` vẫn là transport hiện có; không tạo hoặc thay thế bằng `ActivePoseReference`.

## Work Items

- [Work Item 1: Freeze restore contract and state matrix](./work-item-01-freeze-restore-contract-and-state-matrix.md)
- [Work Item 2: Persist and restore existing pose plus eight camera settings](./work-item-02-persist-and-restore-existing-pose-plus-eight-camera-settings.md)
- [Work Item 3: Integrate select replace clear and relaunch behavior](./work-item-03-integrate-select-replace-clear-and-relaunch-behavior.md)
- [Work Item 4: Verify cold relaunch on real iPhone and regression](./work-item-04-verify-cold-relaunch-on-real-iphone-and-regression.md)

## Coverage

| FEAT-012 requirement | Work Items | Evidence target |
| --- | --- | --- |
| FR-001: restore tám nhóm settings độc lập với pose | 1, 2, 3, 4 | state matrix, snapshot tests, cold-relaunch evidence |
| FR-002: rehydrate `PreparedPoseReference` khi pose hợp lệ | 1, 2, 3, 4 | contract evidence, integration/device evidence |
| FR-003: pose invalid/corrupt không crash, settings vẫn restore | 1, 2, 3, 4 | corrupt snapshot test, device log |
| FR-004: replace pose giữ settings | 1, 3, 4 | integration/regression evidence |
| FR-005: clear gỡ pose, giữ settings và ownership | 1, 3, 4 | behavior test/evidence |
| FR-006: single-device snapshot, không sync | 1, 2 | design decision + persistence evidence |
| FR-007: capture/gallery semantics không đổi | 3, 4 | regression evidence |
| BR-001/002/003/004 và NFR-001 | 1, 2, 3, 4 | matrix + test/device ledger |

## Baseline and evidence

- Feature authority: FEAT-012 `approved`, approved by `Product Authority`, 2026-08-31.
- Existing flow: `PoseDetailScreen.tryPose` verify rồi emit `PreparedPoseReference`; `Navigation.createTryPoseCameraHandoffAction` đặt `PoseServiceLocator.preparedReference`; `CameraScreen` render overlay và controls.
- Existing fields: `CameraState.kt`, `CameraLayoutModel.kt`, `CameraContract.kt`; exact line references phải được cập nhật theo source tại thời điểm execution.
- Historical predecessor: `docs/harness/plans/260809-2241-selected-pose-camera-handoff/plan.md` đã `cancelled`, superseded; giữ nguyên lịch sử và file.

## Dependencies and exclusions

Dependencies chỉ gồm các flow/model và persistence layer đã có trong mobile; WI-01 phải xác nhận path cụ thể trước execution. Không thêm dependency, account sync, history, cloud sync, Saved Poses, hoặc Albums.

## Verification

- Plan status là `in_progress`; approval là `approved`, `decided: 2026-09-01`, `required_by: Repository Maintainer`.
- Chạy targeted `ckh validate` cho plan root và từng Work Item; `ckh workflow status/check` cho Feature, plan cũ và plan mới.
- WI-04 ghi verification ledger với snapshot round-trip/corrupt, select/replace/clear, cold relaunch valid/no-pose/invalid, capture regression, và real-iPhone evidence. Unresolved item phải ghi blocker thay vì claim Verified.
