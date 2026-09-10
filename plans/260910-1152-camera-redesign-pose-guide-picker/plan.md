---
title: "Camera Redesign & Published Pose Guide Picker"
description: "Redesign CameraScreen and add a full-screen published pose guide picker while preserving camera, local capture, snapshot, and PreparedPoseReference contracts."
status: pending
priority: P1
effort: "3d"
tags: [feature, mobile, camera, pose-guide, ios]
created: 2026-09-10
---

# Camera Redesign & Published Pose Guide Picker

## Overview

Plan 1 owns the SCR-001-01 CameraScreen redesign for FEAT-001 capture and the FEAT-008 full-screen picker for published pose guides. The picker is a camera-owned subordinate surface: it returns directly to Camera, verifies a selected published skeleton through the existing shared download/verification seams, and only then replaces the verified overlay reference. Camera permission, capture truth, local photo persistence, lifecycle cancellation, preview session stop/start, and the verified `PreparedPoseReference` handoff remain the governing contracts.

## Ownership and boundaries

- General Lead `b726ad3f-3a3c-49d2-926c-29d0d9610ce0` owns the outcome, freeze, and independent-review launch.
- Tiêu Hà `7ba538b7-add9-4971-9266-869478b2f8ea` owns this bounded decomposition, draft, write set, and handoff; no formal approval is claimed.
- An implementer assigned after `READY_FOR_WORK` owns production/test changes. A fresh Planning Reviewer owns independent reflection/challenge only.
- Current mutation write set is this new directory only. Expected implementation write set is `CameraScreen.kt`, new `PoseGuidePickerScreen.kt`, and focused common tests; no existing plan, source, docs, reindex, or commit is part of this lane.

## Scope and non-goals

In scope: camera visual hierarchy, accessible guide entry, dedicated full-screen published-guide grid, direct Back-to-Camera return, verified replacement of the active guide, and regression evidence for capture/snapshot/handoff boundaries.

Non-goals: Android implementation (no Android target is configured), new backend/API data, account/session or Save/Unsave contracts, Search/Home routing, Gallery redesign, pose extraction, or changing `CameraCoordinator`, `CameraContract`, snapshot schema, or the existing top-level Try Pose handoff. The picker may reuse the existing shared sign-in prompt for `TRY_POSE`; it does not create a camera-specific auth contract.

## Evidence anchors

- `docs/harness/designs/basic-design/screens/mobile/scr-001-01-camera.md`: SCR-001-01 layout, ownership, navigation, picker direction, and unresolved register.
- `docs/harness/features/FEAT-001-capture-a-photo-on-mobile.md`: permission/capture/persistence truth and known gaps.
- `docs/harness/features/FEAT-008-use-published-poses.md`: published Try Pose verification and account/save uncertainty.
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraCoordinator.kt`: capture state and atomic write/verification flow.
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraSnapshotWriter.kt` and `CameraSnapshotRepository.kt`: settings-preserving pose replacement and validity checks.
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt`: existing verified `PreparedPoseReference` to Camera handoff.
- `mobile/shared/src/commonMain/kotlin/com/aipose/data/PreparedPoseReference.kt:31-81`: existing structural image verifier and data-URI builder; `PoseApiService.kt:337-355`: existing community asset download; `PoseServiceLocator.kt:26-40` and `data/auth/SessionBoundary.kt:77-85`: existing session transport.
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PoseDetailScreen.kt:421-470,521-545`: current Try/auth coupling to remove from the picker, not to copy.
- `mobile/composeApp/src/iosMain/kotlin/com/aipose/camera/IOSCameraController.kt:50-56` and `mobile/iosApp/iosApp/CameraViewController.swift:64-73,359-393`: existing preview stop/start bridge; no thermal contract is present.
- Existing tests: `CameraCoordinatorTest`, `CameraSnapshotIntegrationTest`, `CameraGuideAssetTest`, `TryPoseCameraHandoffTest`, and `PoseDetailViewModelTest`.

## Resolved review challenges

- **Auth seam:** Do not instantiate `PoseDetailViewModel` in the picker. Its private `_signInIntent`/`pendingTrySuccess` and `resumeSignInIntent` flow (`PoseDetailScreen.kt:383-395,421-470,521-545`) couples detail-owned auth to Camera. The picker instead retains the selected `CommunityPose`, reuses shared `SignInPromptController`/`SignInPrompt` with existing `SignInIntent.TRY_POSE` for guests, and uses `PoseApiService.downloadImageBytes` plus `PoseImageVerification` to produce the existing `PreparedPoseReference`. The prompt resumes the same pending selection after real auth; Save/Unsave remains out of scope. Direct unauthenticated download is rejected because the current Try flow gates guests at `PoseDetailScreen.kt:430-437`.
- **Affordance:** SCR-001-01 §5 rows 6–8 are the HDR group; row 8 `SCR-001-01-HDR-003` requires the image action (`scr-001-01-camera.md:146-155`). It governs placement in the top header beside Tools. The old bottom-right `CameraUsersButton` (`CameraScreen.kt:377-383,592-620`) is not the acceptance coordinate; the bottom rail remains thumbnail/shutter/flip (`CameraScreen.kt:429-455`).
- **Preview lifecycle:** `CameraContract.kt:39-54` exposes `stopPreview()` and `startPreview()`; there is no `resume()` API. Entering the picker stops preview, leaves capture unavailable, and keeps the child surface active. Back or verified selection starts preview only when permission is authorized and the app is foreground; capture remains gated by the existing coordinator/permission state. The Swift bridge maps start/stop to `setSessionActive` and mounts/unmounts `MCamera` (`CameraViewController.swift:64-73,359-393`). AV contention/thermal behavior is not proven; General Lead owns the implementation-acceptance decision, with the Phase 3 device check below.

## Phases

| # | Phase | Status |
|---|-------|--------|
| 1 | [Camera surface and contract preservation](./phase-01-start.md) | Pending |
| 2 | [Full-screen published pose guide picker](./phase-02-guide-picker.md) | Pending |
| 3 | [Integration, boundary checks, and acceptance](./phase-03-integration-verification.md) | Pending |

## Acceptance evidence and checks

- iOS preview/capture checks prove permission-denied recovery, `PreviewReady`/active gating, in-flight disabling, verified local-photo persistence, and truthful failure behavior.
- Picker checks prove the HDR-003 top-header entry, full-screen header/title/grid, loading/empty/error/retry behavior, Back-to-Camera with no picker back-stack residue, preview stop/start, and replacement only after verified preparation.
- A supported physical-iOS check proves picker entry stops the `MCamera`/AV session, repeated Back/selection does not create duplicate session ownership or capture callbacks, and the resumed session has no observed AV interruption or thermal regression. If the device/runtime cannot establish this evidence, mark it `Pending-validation`; General Lead owns the implementation-acceptance decision.
- Regression checks retain existing `TryPoseCameraHandoffTest`, `CameraSnapshotIntegrationTest`, `CameraCoordinatorTest`, and `CameraGuideAssetTest` behavior; add focused picker tests without inventing a new public contract.
- Implementation validation is the repository’s iOS compile/test path discovered from Gradle tasks, followed by bounded `srcwalk` review and manual UI evidence on the supported iOS target.

## Unresolved questions / risks

Android support is unproven. The shared sign-in prompt is reusable, but account/session support and Save/Unsave remain unresolved in FEAT-008; this plan does not claim account persistence. Snapshot code persists pose identity and settings, while FEAT-012 still marks durable cold-relaunch behavior unresolved. Native picker loading/data/empty/error states, scale range/timeout, tools presentation, capture success feedback, frame-ratio control, and FEAT-011 gate timing remain design decisions. AV contention/thermal behavior lacks runtime evidence. Any answer that changes a public contract, persistence owner, or scope must stop and escalate to the General Lead.

The pre-review draft remains in `PLAN_DRAFT.md` for traceability. `PLAN_FINAL.md` is authoritative after the recorded `READY_FOR_WORK`; no further reviewer is launched by this lane.

## Success Criteria

- [ ] Camera redesign and picker stay within the explicit implementation write set.
- [ ] Existing permission, capture, persistence, snapshot, and verified handoff contracts remain green.
- [ ] Published selection replaces the in-memory guide only after verification and returns directly to Camera.
- [ ] All unresolved account, Android, and persistence questions are surfaced to the reviewer/General Lead.

<!-- slug: camera-redesign-pose-guide-picker -->
