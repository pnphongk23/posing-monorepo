---
phase: 2
title: "Persistence and action contract"
status: pending
priority: P1
effort: "3h"
dependencies: [1]
---

# Phase 2: Persistence and action contract

## Overview

Bind the pure viewer actions to existing local repository and platform seams,
preserving FEAT-002 deletion guarantees and FEAT-011 entitlement behavior.

## TDD steps

1. **RED:** extend focused tests for the exact injected callbacks
   `onSave: suspend (Photo) -> Boolean`, `onDeletePhoto: suspend (Long) -> Unit`,
   and `onDelete: suspend (Long) -> Boolean`: save false/true mapping, missing
   image retry, delete exception/false retention, and successful delete
   dismissal; add fake action ports rather than mocking native frameworks.
2. **GREEN:** route Save through `saveToPhotos`’s boolean result, Share through
   `shareImage`, and Delete through the hoisted `GalleryViewModel` callback;
   surface Save outcome through the reducer and a viewer-local
   `SnackbarHostState`, and surface Delete outcome through that same viewer-local
   host/UI surface, so failures are visible in the detail destination even when
   Voyager owns the route. `SaveResult(false)`
   emits `FeedbackMessage.Error("Save failed", canRetry = true)` and remains
   retryable; `RetrySave` invokes `onSave` again.
3. **REFACTOR:** preserve `CancellationException`, storage ownership checks,
   last-reference cascade, and existing `PhotoRepositoryDeletionTest` behavior.

## Exact Route and Seam Signatures

1. **Delete Seam:**
   - Host `GalleryListScreen` (the inline fallback is updated in the same
     write-set):
     `onPhotoClick = { photo -> navigator.push(GalleryDetailVoyagerScreen(photo = photo, onDeletePhoto = { id -> state.viewModel.deletePhoto(id) })) }`
   - Voyager route `GalleryDetailVoyagerScreen`:
     `class GalleryDetailVoyagerScreen(private val photo: Photo, private val onDeletePhoto: suspend (Long) -> Unit) : Screen`
   - Shared production image helper and exact detail declarations:
     ```kotlin
     @Composable
     fun GalleryPhotoImageContent(
         model: String?,
         attempt: Int,
         contentDescription: String?,
         modifier: Modifier,
         onLoading: () -> Unit,
         onSuccess: () -> Unit,
         onError: () -> Unit,
     ) {
         key(attempt) {
             AsyncImage(
                 model = model,
                 contentDescription = contentDescription,
                 modifier = modifier,
                 contentScale = ContentScale.Crop,
                 onLoading = { onLoading() },
                 onSuccess = { onSuccess() },
                 onError = { onError() },
             )
         }
     }

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

     @Composable
     fun PhotoDetailDialog(
         photo: Photo,
         onDismiss: () -> Unit,
         onDelete: suspend (Long) -> Boolean,
         onSave: suspend (Photo) -> Boolean,
         onShare: (Photo) -> Unit,
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
   - Exception mapping inside `GalleryDetailVoyagerScreen.Content()`:
     ```kotlin
     onDelete = { id ->
         try {
             onDeletePhoto(id)
             true
        } catch (ce: CancellationException) {
            throw ce
        } catch (_: Exception) {
            false
        }
     }
     ```

2. **Save Seam:**
   - Injected callback: `onSave: suspend (Photo) -> Boolean`
   - Platform delegate: `com.aipose.platform.saveToPhotos(imagePath, context)` returns real write outcome.
   - Outcome copy: `com.aipose.platform.saveToPhotosConfirmation(saved: Boolean)`
     maps `true` -> `"Saved to Photos."`, `false` -> `"Save failed"`; the
     reducer stores the exact `FeedbackMessage` and `RetrySave` clears the
     retryable error before invoking the callback again.

3. **Inline fallback forwarding:** the legacy `GalleryScreen` fallback calls
   the same `PhotoDetailDialog` declaration with named `photo`, `onDismiss`,
   `onDelete`, `onSave`, `onShare`, `purchaseGateway`, and `imageContent`
   arguments. Its `onSave` is `suspend { selected ->
   saveToPhotos(resolveImagePath(selected.imagePath) ?: selected.imagePath,
   null) }`; no `onToggleFavorite` parameter remains. Voyager and inline paths
   therefore share one exact dialog contract and one production
   `GalleryPhotoImageContent` default.

## Delete host/UI-only contract

Delete is deliberately outside the pure reducer because repository deletion is
an irreversible host side effect and successful deletion immediately changes
Voyager navigation. `GalleryPhotoDetailScreen` calls its exact
`onDelete: suspend (Long) -> Boolean` callback from the confirmation sheet.
Normal `true` completion calls `onBack()` exactly once. `false` leaves the row
and detail in place and shows viewer-local Snackbar text `Delete failed` with
action `Retry` that calls the same callback again. `CancellationException` is
rethrown by the route adapter and never
becomes feedback. Delete failure is Snackbar-only and does not mutate reducer
`feedback`; `GalleryPhotoViewerContractTest` is the required Compose
integration test: fake false/true callbacks, assert exact snackbar text
`Delete failed` and action `Retry`, retained detail/row, and exactly-one
`onBack()`; no `DeleteRequested`,
`DeleteResult`, `isDeleting`, or production `Deleted` state is added to the
reducer.

## Deterministic date/time and feedback contract

- `Photo.createdAt` is a decimal epoch-millisecond `String`. The viewer header renders a pure,
  injected formatter using UTC date `MMM dd, yyyy` and time `h:mm a`; fixed-epoch
  unit tests freeze this output rather than relying on device locale/time zone.
- Save false and delete false both retain the detail and publish a viewer-local
  retryable message (delete uses the UI-only Snackbar, not reducer feedback). A
  successful delete returns `true` to the host and causes exactly one pop; there
  is no production `Deleted` reducer state. Share invokes `shareImage` and then
  shows the viewer-local `Share sheet ready` Snackbar; it has no reducer event.

## Related code files and symbols

- Modify: `com.aipose.ui.screens.gallery.GalleryPhotoDetailScreen` (`PhotoDetailDialog.kt:56-84`)
- Modify: `com.aipose.navigation.GalleryDetailVoyagerScreen` (`Navigation.kt:260-285`)
- Modify: `com.aipose.navigation.GalleryListScreen` (`Navigation.kt:243-258`)
- Reuse: `com.aipose.platform.saveToPhotos` (`SaveToPhotos.kt:25-29`)
- Reuse: `com.aipose.platform.shareImage` (`ExternalActions.kt`)
- Reuse: `com.aipose.data.PhotoRepository.deletePhoto` (`PhotoRepository.kt:35-59`)
- Extend tests: `mobile/composeApp/src/commonTest/.../GalleryViewModelTest.kt`,
  `mobile/shared/src/iosSimulatorArm64Test/.../PhotoRepositoryDeletionTest.kt`

## Success criteria

- [ ] Save success/failure copy is truthful and retryable.
- [ ] Delete failure leaves the row/detail recoverable; success dismisses once.
- [ ] `GalleryListScreen` passes its hoisted ViewModel delete callback through
      the detail route; detail catches non-cancellation exceptions and maps
      them to `false` without constructing a second ViewModel.
- [ ] The exception boundary is exact: `CancellationException` is rethrown;
      every other `Exception` becomes `false`; `true` is returned only after
      the suspend delete callback completes normally.
- [ ] `onSave` returns the actual `saveToPhotos(path, null)` Boolean; no
      callback discards it.
- [ ] No direct file or SQL mutation is introduced in the Composable.
- [ ] Existing premium gate remains intact unless the unresolved authority
      decision explicitly changes it.
