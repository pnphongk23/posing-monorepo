---
phase: 3
title: "Viewer UI and navigation"
status: pending
priority: P1
effort: "5h"
dependencies: [1, 2]
---

# Phase 3: Viewer UI and navigation

## Overview

Apply v2’s viewer-first composition to the existing Voyager detail destination
while preserving list state, matched-image forward/reverse motion, and iOS safe
areas.

## TDD steps

1. **RED:** add Compose/semantics contract tests for image-dominant content,
   date/time-only header, Share/Save/Trash labels, disabled unavailable actions,
   44dp touch targets, retry affordance, and no favorite/title/tag controls.
2. **GREEN:** update `GalleryPhotoDetailScreen`/viewer implementation with
   these exact signatures and forwarding anchors:
   ```kotlin
   @Composable
   fun GalleryPhotoDetailScreen(
       photo: Photo,
       onBack: () -> Unit,
       onDelete: suspend (Long) -> Boolean,
       onSave: suspend (Photo) -> Boolean,
       onShare: ((Photo) -> Unit)? = null,
       purchaseGateway: PurchaseGateway = PurchaseGatewayProvider.current,
       imageContent: @Composable (
           model: String?,
           attempt: Int,
           contentDescription: String?,
           modifier: Modifier,
           onLoading: () -> Unit,
           onSuccess: () -> Unit,
           onError: () -> Unit,
       ) -> Unit = ::GalleryPhotoImageContent,
   )
   ```
   `GalleryPhotoImageContent` is the addressable production symbol in
   `PhotoDetailDialog.kt`; its exact declaration is frozen in Phase 2 and uses
   `key(attempt) { AsyncImage(...) }`. `GalleryPhotoDetailScreen` forwards
   `imageContent` directly to `PhotoDetailDialog` with no wrapper/default change.
   The shared dialog declaration is exact: `PhotoDetailDialog(photo: Photo,
   onDismiss: () -> Unit, onDelete: suspend (Long) -> Boolean,
   onSave: suspend (Photo) -> Boolean, onShare: (Photo) -> Unit,
   purchaseGateway: PurchaseGateway = PurchaseGatewayProvider.current,
   imageContent: @Composable (String?, Int, String?, Modifier, () -> Unit,
   () -> Unit, () -> Unit) -> Unit = ::GalleryPhotoImageContent)`. The
   `GalleryScreen` inline fallback forwards all of these named arguments,
   including `onSave` returning `saveToPhotos(...)` and `imageContent`, in the
   same write-set; it does not retain `onToggleFavorite`.
   The Voyager route `GalleryDetailVoyagerScreen(photo: Photo, onDeletePhoto: suspend (Long) -> Unit)`
   performs the exact `CancellationException` rethrow / other-`Exception` → `false` mapping from
   `onDeletePhoto` to `GalleryPhotoDetailScreen(onDelete: suspend (Long) -> Boolean)`.
   Inside `PhotoDetailDialog`, `MatchedImageDestination` invokes `imageContent` directly with
   `resolvedPath`, `state.loadAttempt`, `photo.poseName`, and event dispatches.
   The `GalleryScreen` inline fallback is updated to the same save seam in the same write-set.
   Reuse `MatchedImageDestination`, key `photo:<id>`, `resolveImagePath`, design-token
   components, and pop-first `resolveBackAction` behavior.
3. **REFACTOR:** keep `GalleryScreen` list callback and hoisted
   `GalleryListStateHolder` unchanged; remove/retire only legacy overlay wiring
   that is no longer reachable from the route.
4. **Deterministic Loader Seam Verification:**
   In production, the default parameter wraps `key(attempt) { AsyncImage(...) }`, guaranteeing Coil re-execution with the exact same path on retry.
   In Compose unit tests (`GalleryPhotoViewerContractTest`), tests inject a fake `imageContent` harness to trigger `onError()` without live Coil runtime, asserting:
   - Missing UI replaces the image frame (never a blank framed box).
   - Save/Share/Trash buttons become disabled; Back remains enabled.
   - Retrying increments `loadAttempt` while retaining `resolvedPath` and the `Photo` database row.

5. **Feedback and header:** render one viewer-local SnackbarHostState in the
   detail destination. Reducer Save feedback drives `Save failed`/`Saved to
   Photos.`; host/UI-only Delete false drives exact `Delete failed` with action
   `Retry`, and successful `shareImage` drives `Share sheet ready`. These
   messages are visible while Voyager owns the route; only Save messages are
   stored in reducer `feedback`. Parse the decimal epoch-millisecond
   `Photo.createdAt: String` and format it as UTC `MMM dd, yyyy` and `h:mm a`
   via the pure formatter tested in Phase 1. Keep
   Share/Save/Trash as the complete action row, with no overflow/options button.

## Related code files

- Modify or split: `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/PhotoDetailDialog.kt`
- Modify caller compatibility path: `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/GalleryScreen.kt` (inline fallback callback signatures/outcome handling)
- Modify only if needed: `mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt`
- Extend: `mobile/composeApp/src/commonTest/kotlin/com/aipose/navigation/MatchedImageTransitionTest.kt`
- Add: `mobile/composeApp/src/commonTest/kotlin/com/aipose/ui/screens/gallery/GalleryPhotoViewerContractTest.kt`

## Success criteria

- [ ] V2 layout has dominant capture, date/time, and three native-feeling
      actions; no title/tag/favorite detail chrome.
- [ ] Forward/reverse transition has no blank frame or double image.
- [ ] Back performs exactly one Voyager pop and preserves gallery scroll/data.
- [ ] Semantics labels and reduced-motion behavior are explicit/testable.
- [ ] No overflow “Photo options” control is introduced; the approved three
      actions are the complete v2 action surface.
- [ ] `GalleryListScreen` supplies `state.viewModel::deletePhoto` when pushing
      the detail screen, proving the list owner—not detail—owns deletion.
- [ ] Save/Share paywall behavior is explicit: non-premium action taps present
      the existing `PaywallScreen`; premium Save invokes `onSave` and maps its
      Boolean result through the reducer.
- [ ] The legacy inline `PhotoDetailDialog` caller compiles against the same
      `suspend (Photo) -> Boolean` save seam and reducer; no duplicate detail
      behavior is left behind.
- [ ] Save false and delete false produce visible, retryable viewer-local
      feedback (delete via Snackbar-only UI boundary); date/time header output
      is deterministic UTC formatting.
- [ ] Missing media disables all three actions. Ready non-premium actions stay
      semantically enabled and route to the existing FEAT-011 paywall.
