---
title: "Phase 2: Full-screen published pose guide picker"
status: todo
---

# Phase 2: Full-screen published pose guide picker

## Overview

Build the dedicated subordinate picker direction described by SCR-001-01: a full-screen `Choose a guide` surface with Back to Camera, published guide cards, and recoverable loading/empty/error states. Remove the `PoseDetailViewModel` dependency from this surface. Reuse the existing shared sign-in prompt for the existing `TRY_POSE` intent, then use the existing `PoseApiService.downloadImageBytes` and `PoseImageVerification` seams to prepare a verified reference. The picker must not become Search, Home, Gallery, or a Saved/account feature.

**Owner:** implementer assigned by General Lead after `READY_FOR_WORK`; independent Planning Reviewer verdict is recorded. **Priority:** P1. **Dependencies:** Phase 1 camera child-surface callback. **Expected files:** create `mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/PoseGuidePickerScreen.kt`; integrate from `CameraScreen.kt`; add `mobile/composeApp/src/commonTest/kotlin/com/aipose/camera/PoseGuidePickerTest.kt` or the repository-equivalent focused test location.

## Requirements

- [ ] Render a full-screen header with Back to Camera, title `Choose a guide`, and a published-only guide grid using stable pose IDs and existing image fallback behavior.
- [ ] Reuse `PosesLibraryCoordinator`/`CommunityPose` data and paging/dedupe behavior; do not reuse the mixed local/published `SearchScreen`.
- [ ] Show deterministic loading, empty, load-more, error, and retry states without claiming a selected guide before verification.
- [ ] Do not instantiate `PoseDetailViewModel` or copy its private `_signInIntent`/`pendingTrySuccess` state. Retain the selected `CommunityPose` locally in the picker.
- [ ] For a signed-in selection, call existing `PoseApiService.downloadImageBytes` and `PoseImageVerification.detectImageMimeType`/`toDataUri`, then emit only the existing `PreparedPoseReference` on success.
- [ ] For a guest selection, reuse existing `SignInPromptController`/`SignInPrompt` with `SignInIntent.TRY_POSE`; after real success retry the retained selection. Cancellation clears the existing interrupted intent and stays recoverable.
- [ ] On failed download or MIME verification, retain the selected `CommunityPose` and show an in-place retryable error; do not clear, replace, or corrupt the current Camera overlay, active reference, locator handoff, or snapshot input.
- [ ] Do not invent account, SavedEntry, Save, or Unsave APIs; the shared prompt is only the existing Try sign-in seam, not account persistence.
- [ ] Back returns directly to Camera. Successful selection returns directly to Camera and replaces the current guide; the picker is not left in the Back stack.

## Implementation Steps

1. Define the smallest internal picker state needed for community paging, retained selection, sign-in visibility, and action states; keep public models and API DTOs unchanged.
2. Compose the full-screen header/grid and reuse existing community card/image conventions and semantics.
3. On signed-in card activation, retain the selected `CommunityPose`, download its `skeletonUrl` through the existing API service, verify bytes with `PoseImageVerification`, and build the existing data-URI-backed `PreparedPoseReference`; keep the current overlay visible until success.
4. On download/MIME failure, keep the retained card selected, render the picker error/retry state in place, and leave Camera-owned state untouched.
5. On guest activation, show the existing shared `TRY_POSE` prompt; on real success retry the retained pose exactly once, and on cancellation clear/recover without a reference.
6. Wire Back and verified success callbacks into Phase 1’s post-unmount exit transition. On success pass the verified reference only; Camera owns the serialized overlay/locator/snapshot commit.
7. Exercise sign-in cancellation, retry, unavailable skeleton, duplicate pose IDs, and paging boundaries with focused tests.

## Todo

- [ ] Confirm `PoseGuidePickerScreen` can reuse `SignInPromptController`/`SignInPrompt` directly without a `Navigation.kt` change; otherwise stop and escalate rather than reintroducing `PoseDetailViewModel`.
- [ ] Confirm `PoseApiService.downloadImageBytes` plus `PoseImageVerification` is the only preparation boundary; do not add a new public preparation API.
- [ ] Confirm failed download/MIME verification retains selection context and does not mutate Camera-owned state.
- [ ] Confirm no route is added through old Search/Home or the existing top-level Poses navigation.
- [ ] Confirm native image/loading/empty/error details from accepted evidence during implementation; if absent, record them unresolved rather than inventing a backend response shape.

## Success Criteria

- [ ] Picker is full-screen, published-only, directly reversible, and accessible.
- [ ] Only a verified `PreparedPoseReference` can replace the camera guide.
- [ ] Failed preparation keeps the selected card and in-place recovery state while preserving the existing overlay and handoff state.
- [ ] Picker has no `PoseDetailViewModel` or detail-owned `_signInIntent` dependency; guest Try uses the existing shared prompt and remains truthful on cancel/failure.
- [ ] Unavailable/invalid data remains recoverable and does not produce false Saved or ownership state.
- [ ] Existing Try Pose handoff behavior and camera snapshot settings are unchanged.

## Risks and responses

- **Auth boundary:** current detail flow gates guests at `PoseDetailScreen.kt:430-437`, while the shared prompt is reusable. If the picker cannot host that existing prompt without a new public/navigation contract, leave guest selection unresolved and escalate; never bypass the gate.
- **Data duplication:** community paging already dedupes by `poseId`; reuse it rather than adding a second repository.
- **False persistence:** do not write camera state from the picker before verification succeeds.
