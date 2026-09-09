---
phase: 1
title: "Contract and state model"
status: pending
priority: P1
effort: "3h"
dependencies: []
---

# Phase 1: Contract and state model

## Overview

Freeze the viewer state/action contract before touching Compose layout. The
model must represent honest media readiness and recoverable action outcomes
without changing `Photo` persistence.

## TDD steps

1. **RED:** add common tests for ready/loading/missing states, action
   availability, save failure retry, and UTC date/time formatting (`MMM dd,
   yyyy` plus `h:mm a`) from a fixed epoch. Delete is intentionally not a
   reducer event; its host/UI integration test is specified in Phase 2.
2. **GREEN:** implement the single pure `GalleryPhotoViewerState`/reducer seam
   (no in-place-flags alternative). Freeze these exact declarations:

   ```kotlin
   enum class MediaStatus { Loading, Ready, Missing }
   sealed interface SaveStatus {
       data object Idle : SaveStatus
       data object Saving : SaveStatus
       data object Saved : SaveStatus
       data class Failed(val message: String) : SaveStatus
   }
   sealed interface FeedbackMessage {
       data class Info(val text: String) : FeedbackMessage
       data class Error(val text: String, val canRetry: Boolean) : FeedbackMessage
   }
   data class GalleryPhotoViewerState(
       val photo: Photo,
       val resolvedPath: String?,
       val transitionKey: String,
       val loadAttempt: Int,
       val media: MediaStatus,
       val save: SaveStatus,
       val feedback: FeedbackMessage?,
   )
   fun reduce(
       state: GalleryPhotoViewerState,
       event: GalleryPhotoViewerEvent,
   ): GalleryPhotoViewerState
   ```

   Initial state is `loadAttempt = 0`, `media = Loading`, `save = Idle`, and
   `feedback = null`. Events are `ImageLoading`, `ImageReady`, `ImageFailed`,
   `RetryImage`, `SaveRequested`, `SaveResult(Boolean)`, and `RetrySave`.

### Full Event Transition Table

| Initial state | Event | Required next state |
|---|---|---|
| Initial | — | `Loading`, attempt `0`, exact path/key, `Idle`, no feedback |
| Any | `ImageLoading` | `media = Loading`; identity/save/feedback retained |
| Loading/Ready/Missing | `ImageReady` | `media = Ready`; identity retained |
| Loading/Ready | `ImageFailed` | `media = Missing`; identity retained; actions unavailable |
| Missing | `ImageFailed` (repeated) | `Missing`; exact identity/save/feedback retained (no-op) |
| Missing | `RetryImage` | `loadAttempt + 1`, `media = Loading`; exact path/key retained |
| Loading/Ready | `RetryImage` outside `Missing` | State unchanged (no-op) |
| Ready | `SaveRequested` | `save = Saving`, feedback cleared; UI invokes `onSave(photo)` |
| Loading/Missing/Saving | `SaveRequested` | State unchanged (no-op) |
| Saving | `SaveResult(true)` | `save = Saved`, `Info("Saved to Photos.")` |
| Loading/Ready/Missing/Idle/Failed | `SaveResult(true)` | State unchanged (no-op) |
| Saving | `SaveResult(false)` | `save = Failed("Save failed")`, `Error("Save failed", true)` |
| Loading/Ready/Missing/Idle/Failed | `SaveResult(false)` | State unchanged (no-op) |
| Failed | `RetrySave` | `save = Saving`, feedback cleared; UI invokes `onSave(photo)` again |
| Idle/Saving/Saved | `RetrySave` | State unchanged (no-op) |

Media `Missing` disables Save/Share/Trash, keeps Back enabled, retains the
`Photo` row, and renders a missing state rather than a blank image frame.
Delete remains host/UI-only: the reducer has no delete or `Deleted` state.

3. **REFACTOR:** keep platform callbacks at the boundary; no Coil, SQLDelight,
   or Voyager dependency in the pure model.

## Related code files

- Create: `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/GalleryPhotoViewerState.kt`
- Create: `mobile/composeApp/src/commonTest/kotlin/com/aipose/ui/screens/gallery/GalleryPhotoViewerStateTest.kt`
- Reuse/read-only: generated `Photo`, `ImagePathResolver.kt`,
  `MatchedImageTransition.kt`

## Success criteria

- [ ] Tests enumerate all v2 query-state equivalents and action outcomes.
- [ ] No new database/API field is required.
- [ ] State transitions never claim save/share/delete success before callback
      evidence and keep failed records/actions recoverable.
- [ ] `RetryImage` increments only `loadAttempt`, retaining the same
      `resolvedPath` and `transitionKey`; repeated `ImageFailed` is `Missing`
      with Save/Share/Trash disabled and Back enabled.
- [ ] `SaveResult(false)` is `Failed("Save failed")`/retryable;
      `RetrySave` returns to Saving and permits a second injected callback
      invocation.
- [ ] Successful delete is represented by the host callback's `true` and
      one dismiss/pop; the reducer has no persistent `Deleted` state.
- [ ] `FeedbackMessage.Info("Saved to Photos.")` and
      `FeedbackMessage.Error("Save failed", canRetry = true)` are deterministic;
      `RetrySave` clears the error and returns to the callback-invocation path.
- [ ] Delete false publishes viewer-local Snackbar text `Delete failed` with
      Retry while retaining the detail; it is not reducer feedback and
      `CancellationException` is never converted to a user-visible failure.
