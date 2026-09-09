---
title: "Gallery photo viewer v2"
description: "TDD implementation plan for applying the approved viewer-first gallery detail flow to the iOS-first Compose/KMP app without changing the local Photo/API contract."
status: pending
priority: P1
effort: M
tags: [gallery, photo-viewer, compose, kmp, tdd, ios]
blockedBy: []
blocks: []
created: 2026-09-09
---

# Gallery photo viewer v2

## Outcome and boundary

Apply the approved `docs/prototype/screens/gallery-detail-v2.html` behavior to
the current mobile gallery detail route. The detail screen remains a local
`Photo` viewer: a dominant captured image, capture date/time, and native-feeling
Share / Save / Trash actions with honest loading, missing-file, export-failure,
and post-delete recovery states.

This is a planning artifact only. It does not authorize Cook or source edits
until the plan gate returns `READY_FOR_WORK` and the relevant Feature/Plan
authority is satisfied.

## Bounded scout (PLAN_DRAFT evidence)

| Area | Observed evidence | Planning consequence |
|---|---|---|
| List/navigation | `GalleryScreen.kt:59-225` loads reactive `Photo` rows; `Navigation.kt:243-285` pushes `GalleryDetailVoyagerScreen`; list state is hoisted above Voyager. | Keep the route and pop-first matched-image transition; change only the detail destination contract/presentation. |
| Current detail | `PhotoDetailDialog.kt:56-293` already resolves the local path, uses `MatchedImageDestination`, supports Save/Share/Delete, and gates Save/Share through `PurchaseGateway`. It has no explicit missing-file or loading UI and its standalone delete callback rethrows. | Add an explicit viewer state/action reducer and make every failure recoverable; do not infer success from callback completion. |
| Transition | `PhotoCard.kt:166-221` captures `photo:<id>` bounds; `MatchedImageTransition.kt:309-353` hides destination chrome until media readiness and coordinates reverse pop. | Preserve key `photo:<id>`, resolved image model, crop continuity, and `destinationChromeVisible`; add tests for viewer state around the existing transition contract. |
| Persistence | `Photo.sq:2-47` is local-only (`imagePath`, optional `poseId`, `poseName`, `createdAt`, `isFavorite`); `PhotoRepository.kt:30-66` streams/deletes rows and owned files; no gallery HTTP API exists. | No SQL migration, server endpoint, or API DTO change. Use existing repository and storage ownership boundary. |
| Delete/export | `PhotoRepositoryDeletionTest.kt` covers last-reference cascade, missing-file idempotency, and restoration on file-delete failure. `saveToPhotos` returns a real iOS write result; `shareImage` is an expect/actual platform action. | Extend focused tests for viewer outcome mapping and keep delete/export truthful. Android remains deferred because no Android target exists. |
| Prototype authority | README:117 and `gallery-detail-v2.html:236-407` specify viewer-first layout, date/time only, Share/Save/Trash, loading/missing/save-error/deleted states, retry, toast, delete sheet, 44px controls, reduced-motion behavior. | Remove title/tag/favorite chrome from detail; retain accessibility labels and recoverable action states. |

### Exact current Gradle/task evidence

The root task listing was verified with `./gradlew tasks --all --console=plain`:
the project exposes `:composeApp:allTests`, `:shared:allTests`,
`:composeApp:iosSimulatorArm64Test`, and `:shared:iosSimulatorArm64Test`.
There is no `:mobile:*` project prefix. Phase 4 uses these exact runnable task
paths.

## Contract conflicts / unresolved questions

1. **Premium gate (frozen in this slice):** current Compose gates Save and
   Share behind `PurchaseGateway`, while v2 prototype presents both as ordinary
   actions and does not model a paywall. Retain the existing approved FEAT-011
   entitlement gate. A non-premium tap opens the existing `PaywallScreen`; the
   v2 action remains visible/enabled, and no free-access change is made here.
   Making either action free is explicitly deferred to a separate authority
   decision, not an implementation choice in this plan.
2. **Missing-file recovery semantics (frozen):** “Try again” increments a
   loader nonce and re-invokes Coil with the same resolved path. If it remains
   unreadable, state stays `Missing`, Save/Share/Trash remain disabled, and Back
   remains available. The `Photo` row is retained; no metadata deletion or
   invented rehydrate API is allowed.
3. **Share failure contract (frozen):** `shareImage` currently returns `Unit`.
   Keep it fire-and-forget and show “Share sheet ready” only after invocation;
   failed-share reporting is a follow-up contract and out of scope.
4. **Platform acceptance:** existing specs say iOS-scoped gallery delivery and
   no Android KMP target. Physical iPhone/Mobile MCP evidence is unresolved in
   this workspace; simulator/unit checks are the minimum deterministic gate.

5. **Deleted presentation (frozen):** a successful delete maps to `true` and
   dismisses the detail route with exactly one pop; a failed delete maps to
   `false` and keeps the confirmation/detail recoverable. The prototype's
   transient `state=deleted` page is a fixture state, not a second production
   persistence or reducer state; production has no `Deleted` viewer state.

## Selected approach and simplest alternative

**Selected (only approach for this plan):** a small, pure viewer state/action
model plus a Compose viewer destination that reuses `Photo`,
`PhotoRepository`, existing platform seams, and matched-image transition
primitives. Tests are written before each implementation slice. This isolates
loading/action/recovery logic without introducing a second persistence model;
it is one data class/reducer, not a second ViewModel or persistence model.

The in-place `remember`-flags alternative was rejected: it has a smaller diff,
but makes state mapping and failure behavior hard to unit-test and leaves the
standalone delete path easy to regress.

## Ownership and non-goals

- Owner: mobile gallery detail flow in `mobile/composeApp` plus focused shared
  repository/platform tests needed to prove the flow.
- Non-goals: new gallery API, SQL schema changes, albums, camera/extraction
  changes, community/saved pose changes, Android target creation, prototype
  edits, or broad design-token rewrites.
- No Worker slice is opened: this turn is plan-only and the bounded work would
  share the same detail contract; delegation would add coordination cost without
  an isolated write-set. An independent Planning Reviewer is still mandatory.
- Delete ownership is frozen: `GalleryListScreen` passes the hoisted list
  ViewModel's callback with the exact chain
  `GalleryListScreen.onPhotoClick(Photo)` →
  `GalleryDetailVoyagerScreen(photo: Photo, onDeletePhoto: suspend (Long) -> Unit)` →
  `GalleryPhotoDetailScreen(photo: Photo, onBack: () -> Unit, onDelete: suspend
  (Long) -> Boolean, ...)`. The route adapter wraps `onDeletePhoto` as
  `suspend (Long) -> Boolean`: rethrow `CancellationException`, catch other
  `Exception` as `false`, and return `true` only after the callback returns.
  The detail screen no longer constructs a second `GalleryViewModel`.
  Delete is intentionally host/UI-only (no reducer delete events): the
  confirmation sheet calls `onDelete`, `true` calls `onBack()` exactly once,
  and `false` retains the row/detail while showing a viewer-local Snackbar with
  exact text `Delete failed` and action `Retry`; this UI-only message is not
  written to reducer `feedback` (which is save-owned). `GalleryPhotoViewerContractTest`
  is the exact integration proof for this boundary; `CancellationException` is
  never converted to UI feedback.
- Shared surface is frozen: `PhotoDetailDialog` remains the compatibility
  Composable used by both the Voyager route and `GalleryScreen`'s no-navigation
  inline fallback. Its signature change is applied to both callers in the same
  write-set; both use the same reducer/action contract. The production tab
  always supplies `onPhotoClick`, so the inline fallback is not a second UX.
- Save is injected as `suspend (Photo) -> Boolean`; its implementation resolves
  the path and returns `saveToPhotos(path, null)`. Reducer events are
  `SaveRequested`, `SaveResult(Boolean)`, and `RetrySave`; `false` enters
  `SaveStatus.Failed("Save failed")` and
  `FeedbackMessage.Error("Save failed", canRetry = true)`. `RetrySave`
  re-attempts save without state lock-out.
- The exact pure state contract is:
  `GalleryPhotoViewerState(photo: Photo, resolvedPath: String?,
  transitionKey: String, loadAttempt: Int, media: MediaStatus,
  save: SaveStatus, feedback: FeedbackMessage?)`, where
  `MediaStatus = Loading | Ready | Missing`, `SaveStatus = Idle | Saving |
  Saved | Failed(message: String)`, and `FeedbackMessage = Info(text: String)
  | Error(text: String, canRetry: Boolean)`. The reducer is
  `reduce(state: GalleryPhotoViewerState, event: GalleryPhotoViewerEvent)`;
  its exact transition table is in Phase 1. No `isSaving`, `isDeleting`,
  `DeleteRequested`, `DeleteResult`, or production `Deleted` state exists.
- Media loading is an injected/pure event seam, not an unmocked Coil test:
  `ImageLoading`, `ImageReady`, `ImageFailed`, and `RetryImage`. `RetryImage`
  increments `loadAttempt` while retaining the exact resolved path and stable
  transition key; repeated `ImageFailed` remains `Missing`, disables
  Save/Share/Trash, retains the row, and leaves Back enabled.
  `GalleryPhotoDetailScreen` exposes this exact injectable `imageContent` after
  `purchaseGateway` and forwards it unchanged to `PhotoDetailDialog`:
  `@Composable (model: String?, attempt: Int, contentDescription: String?,
  modifier: Modifier, onLoading: () -> Unit, onSuccess: () -> Unit,
  onError: () -> Unit) -> Unit = ::GalleryPhotoImageContent`.
  Its production default is the addressable symbol `PhotoDetailDialog.kt:GalleryPhotoImageContent`
  wrapping `key(attempt) { AsyncImage(...) }`; tests inject a fake
  lambda, so no unmocked Coil is required.
- The complete `PhotoDetailDialog` declaration is frozen as
  `PhotoDetailDialog(photo: Photo, onDismiss: () -> Unit,
  onDelete: suspend (Long) -> Boolean, onSave: suspend (Photo) -> Boolean,
  onShare: (Photo) -> Unit, purchaseGateway: PurchaseGateway =
  PurchaseGatewayProvider.current, imageContent: @Composable (String?, Int,
  String?, Modifier, () -> Unit, () -> Unit, () -> Unit) -> Unit =
  ::GalleryPhotoImageContent)`. `GalleryPhotoDetailScreen` and the
  `GalleryScreen` inline fallback forward all named arguments; the fallback's
  `onSave` returns `saveToPhotos(resolveImagePath(selected.imagePath) ?:
  selected.imagePath, null)`. `onToggleFavorite` is removed from this detail
  surface because v2 has no favorite chrome.
- `Photo.createdAt` is a decimal epoch-millisecond `String`; a pure formatter
  emits UTC `MMM dd, yyyy` and `h:mm a` and is covered by fixed-epoch tests.
- Delete and Share feedback are UI-only and use the viewer-local Snackbar:
  delete false is `Delete failed` + `Retry`, while a successful `shareImage`
  invocation is followed by `Share sheet ready`; neither is reducer state.
- Missing media is a hard action disable. When media is `Ready`, Save/Share are
  semantically enabled even for non-premium users, but existing FEAT-011 tap
  handling opens `PaywallScreen`; this is distinct from missing-media disable.

### Reducer transition table (frozen)

| Event | State result |
|---|---|
| Initial | `media = Loading`, `loadAttempt = 0`, `save = Idle`, `feedback = null` |
| `ImageLoading` (any media) | `Loading`; identity/save/feedback retained |
| `ImageReady` (Loading/Ready/Missing) | `Ready` |
| `ImageFailed` (Loading/Ready) | `Missing`; identity retained; actions unavailable |
| `ImageFailed` (already Missing) | `Missing`; exact identity/save/feedback retained (no-op) |
| `RetryImage` (`Missing` only) | `Loading`, attempt incremented; exact path/key retained |
| `RetryImage` (Loading/Ready) | State unchanged (no-op) |
| `SaveRequested` (`Ready` only) | `Saving`, feedback cleared; UI invokes `onSave(photo)` |
| `SaveRequested` (Loading/Missing/Saving) | State unchanged (no-op) |
| `SaveResult(true)` (`Saving` only) | `Saved`, `Info("Saved to Photos.")` |
| `SaveResult(true)` (outside `Saving`) | State unchanged (no-op) |
| `SaveResult(false)` (`Saving` only) | `Failed("Save failed")`, `Error("Save failed", true)` |
| `SaveResult(false)` (outside `Saving`) | State unchanged (no-op) |
| `RetrySave` (`Failed` only) | `Saving`, feedback cleared; UI invokes `onSave(photo)` again |
| `RetrySave` (Idle/Saving/Saved) | State unchanged (no-op) |

Delete is not in this reducer table: it is the explicitly frozen host/UI
boundary described above and tested by `GalleryPhotoViewerContractTest`.
- The v2 prototype's overflow “Photo options” control is out of scope because
  the approved v2 README contract names exactly Share, Save, and Trash. No
  overflow control is added.

## Phases (TDD order)

| # | Phase | Status | Depends on |
|---|---|---|---|
| 1 | [Contract and state model](./phase-01-start.md) | Pending | — |
| 2 | [Persistence/action contract](./phase-02-contract.md) | Pending | 1 |
| 3 | [Viewer UI and navigation](./phase-03-viewer-ui.md) | Pending | 1, 2 |
| 4 | [Recovery and verification](./phase-04-recovery-and-verification.md) | Pending | 2, 3 |

## Acceptance evidence

- Unit tests prove every reducer transition: loading → ready, image error →
  missing/retry, and save false → retryable error. The
  `GalleryPhotoViewerContractTest` proves delete false → retained detail and
  delete true → exactly-one pop/removed record at the host/UI boundary.
- Compose semantics/contract tests prove 44dp critical controls, date/time-only
  title, no favorite/title/tag controls, disabled actions while unavailable,
  meaningful content descriptions, and stable `photo:<id>` transition key.
- Addressable test symbols are `GalleryPhotoViewerStateTest.totalReducerGuards`
  and `GalleryPhotoViewerContractTest.missingImageRetryKeepsPathAndIncrementsAttempt`
  plus `GalleryPhotoViewerContractTest.deleteFailureShowsRetryAndRetainsDetail`;
  production image loading is anchored at `PhotoDetailDialog.kt:GalleryPhotoImageContent`.
- Existing matched-image and `PhotoRepositoryDeletionTest` suites remain green;
  focused iOS simulator tests prove file ownership/idempotency and real
  Save-to-Photos boolean mapping where platform seams permit.
- Verification report records iOS device/Mobile MCP status, and explicitly does
  not claim Android or physical-device parity when unavailable.
- Stop-ship checks are the compose common test compilation/execution,
  `:composeApp:iosSimulatorArm64Test`, `:shared:iosSimulatorArm64Test`, the
  matched-image transition tests,
  viewer semantics (44dp labels and no title/tag/favorite), and no blank framed
  image during loading/error/flight. Device/Android checks are evidence-only
  follow-ups, not blockers to the iOS simulator gate.

## Risks and mitigations

- Paywall conflict can change user-visible behavior: preserve current gate and
  carry the unresolved decision into authority review.
- AsyncImage may report an error after a transition: keep chrome readiness tied
  to `destinationChromeVisible`, never show a blank framed image, and test the
  error-after-flight path.
- Delete can remove a linked last-reference Pose: reuse repository’s existing
  compensation/ownership tests; never implement direct SQL deletion in UI.
- iOS-only platform actuals and unavailable physical device limit proof: label
  evidence by target and keep simulator/unit checks deterministic.

<!-- PLAN_FINAL: independent planning review returned REVISE_PLAN; five
     challenges resolved in PLAN_FINAL.md. No implementation authorized. -->
<!-- slug: gallery-photo-viewer-v2 -->
