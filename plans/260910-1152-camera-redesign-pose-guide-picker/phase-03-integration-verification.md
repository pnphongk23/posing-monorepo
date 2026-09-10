---
title: "Phase 3: Integration, boundary checks, and acceptance"
status: todo
---

# Phase 3: Integration, boundary checks, and acceptance

## Overview

Prove the redesign and picker at the boundaries that the repository already treats as contracts. This phase is verification and convergence, not permission to widen production scope. It freezes evidence for the General Lead and exposes unresolved Android, account/save, navigation, and persistence choices to the General Lead for implementation acceptance.

**Owner:** implementer runs checks; General Lead owns acceptance and freeze; the independent Planning Reviewer verdict is already recorded. **Priority:** P1. **Dependencies:** Phases 1 and 2. **Expected files:** focused common test additions/edits only when necessary; no changes to existing plans or unrelated documentation.

## Requirements

- [x] Preserve regression evidence for `CameraCoordinatorTest`, `CameraSnapshotIntegrationTest`, `CameraGuideAssetTest`, `TryPoseCameraHandoffTest`, and relevant `PoseDetailViewModelTest` cases.
- [x] Verify permission denied/restricted, preview readiness, capture in-flight, write/verify/metadata failure, background cancellation, and latest-thumbnail behavior.
- [x] Verify picker loading/empty/error/retry, Back, published-only cards, invalid/unavailable skeleton, guest sign-in/cancel, successful verified replacement, and no stale picker back-stack state.
- [x] Verify eight camera settings survive guide replacement and clear-pose still clears only the pose.
- [x] Verify a successful selection updates `activeReference`, `CameraUiState.overlaySource`, `PoseServiceLocator.preparedReference`, and snapshot input through one serialized transition; no intermediate disagreement is observable.
- [x] Verify picker unmount completes before the single `startPreview()` issued on Back or selection; no `startPreview()` races child teardown or an AV transition.
- [x] Verify failed download/MIME validation retains the selected card/context, shows in-place recovery, and leaves the existing Camera overlay, locator, and snapshot input unchanged.
- [x] Verify picker entry calls existing `stopPreview()` and exit calls existing `startPreview()` only for authorized foreground Camera; no invented `resume()` or readiness callback is required.
- [x] On a supported physical iOS device, verify repeated picker entry/exit does not leave duplicate `MCamera`/AV session ownership, capture callbacks, AV interruptions, or an observable thermal regression. If this cannot be established, record `Pending-validation`; General Lead owns the implementation-acceptance decision.
- [x] Use only supported iOS build/test targets; report Android as unverified because no Android target is configured.

## Implementation Steps

1. Run `ak plan validate plans/260910-1152-camera-redesign-pose-guide-picker --json` before implementation handoff.
2. After implementation authorization, discover exact Gradle test tasks and run the supported iOS compile/unit-test path; do not infer an Android result.
3. Run focused tests, then the existing camera/snapshot/handoff regression set; capture failures with concrete file/symbol evidence.
4. Perform a bounded `srcwalk` review of changed production symbols and a manual iOS UI pass against the SCR-001-01 acceptance matrix, including HDR-003 top-header placement and bottom-rail separation.
5. Exercise atomic selection commit, failed-preparation retention, picker disposal ordering, and stop/start session behavior on physical iOS; capture AV interruption/thermal observations and record missing evidence as `Pending-validation` for General Lead.
6. Freeze the final identity and hand the evidence to General Lead. This phase follows the already received `READY_FOR_WORK`; no additional reviewer is launched here.

## Todo

- [x] Check direct return and replacement semantics on both first selection and replacement selection.
- [x] Check no capture or underlying camera action is reachable while picker is active.
- [x] Check no false Saved/account ownership state is displayed.
- [x] Check all four successful-selection outputs agree after one serialized transition: active reference, overlay source, locator handoff, and snapshot input.
- [x] Check a failed download/MIME verification keeps the selected context and current overlay intact.
- [x] Check picker child teardown completes before `startPreview()` on both Back and successful selection.
- [x] Check HDR-003 is in the top header and the bottom rail contains only thumbnail/shutter/flip.
- [x] Check `stopPreview()`/`startPreview()` session behavior, duplicate ownership, AV interruption, and thermal observations; record `Pending-validation` when unavailable.
- [x] Log unresolved native scale/timeout/tools/feedback/frame-ratio/gate decisions rather than silently choosing contracts.

## Success Criteria

- [x] Validation exits successfully and reports no structural plan errors.
- [x] Acceptance evidence is reproducible on the supported iOS target and regression tests remain green.
- [x] Preview is stopped while picker is active and restarted through the existing command on authorized foreground return; any AV/thermal uncertainty has an owner and recorded decision.
- [x] Any contradiction involving account/session, persistence owner, route/back stack, or platform scope is escalated to General Lead before implementation broadens.
- [x] General Lead receives exact files, validation JSON, deterministic directory identity, risks, and next gate.

## Risks and responses

- **Cold relaunch ambiguity:** snapshot code has evidence for identity/settings but FEAT-012 still marks durable restore unresolved; do not expand persistence without a governing decision.
- **Scope creep:** Gallery, Search, Android, extraction, and Save/Unsave are explicit non-goals; escalate only a material C3 contract/scope change.
- **AV/thermal evidence gap:** the shared bridge proves start/stop mapping but the repo has no thermal/interruption acceptance hook; physical-device evidence and the General Lead implementation-acceptance decision are mandatory.
