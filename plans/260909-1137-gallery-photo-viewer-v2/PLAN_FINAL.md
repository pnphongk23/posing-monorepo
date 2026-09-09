# PLAN_FINAL — Gallery photo viewer v2

## Gate result

`PLAN_DRAFT` was independently reviewed by **Nguyễn Trãi** (Planning Reviewer,
agent `933df1b2-d484-4adc-83a5-5b0982b0ccc6`) against the frozen candidate
identity `f246bf5f8c2bffa6c3842da1ee3300db5ce92e564074b3d83a8db6828a5ea674`.
Verdict: **REVISE_PLAN**. The reviewer returned five focused challenges; no
source files were edited and no formal approval was given.

## Resolutions applied (Revision 5 — Final Candidate Freeze)

1. **State fields, variants, and transition table frozen:**
   `GalleryPhotoViewerState` explicitly declares only `photo: Photo`,
   `resolvedPath: String?`, `transitionKey: String`, `loadAttempt: Int`,
   `media: MediaStatus`, `save: SaveStatus`, and `feedback: FeedbackMessage?`.
   Variants are exactly `MediaStatus` (`Loading`, `Ready`, `Missing`),
   `SaveStatus` (`Idle`, `Saving`, `Saved`, `Failed(message: String)`), and
   `FeedbackMessage` (`Info(text: String)`, `Error(text: String,
   canRetry: Boolean)`). The complete transition table is frozen in
   `phase-01-start.md`; no undeclared `isSaving`/`isDeleting` fields exist.

   | Event | Required result |
   |---|---|
   | Initial | `media = Loading`, `loadAttempt = 0`, `save = Idle`, `feedback = null` |
   | `ImageLoading` | `Loading`; identity/save/feedback retained |
   | `ImageReady` (Loading/Ready/Missing) | `Ready` |
   | `ImageFailed` (Loading/Ready) | `Missing`; actions unavailable; identity retained |
   | `ImageFailed` (already Missing) | `Missing`; exact identity/save/feedback retained (no-op) |
   | `RetryImage` (Missing only) | `Loading`, attempt incremented; exact path/key retained |
   | `RetryImage` (Loading/Ready) | State unchanged (no-op) |
   | `SaveRequested` (Ready only) | `Saving`, feedback cleared; invoke `onSave(photo)` |
   | `SaveRequested` (Loading/Missing/Saving) | State unchanged (no-op) |
   | `SaveResult(true)` (Saving only) | `Saved`, `Info("Saved to Photos.")` |
   | `SaveResult(true)` (outside Saving) | State unchanged (no-op) |
   | `SaveResult(false)` (Saving only) | `Failed("Save failed")`, `Error("Save failed", true)` |
   | `SaveResult(false)` (outside Saving) | State unchanged (no-op) |
   | `RetrySave` (Failed only) | `Saving`, feedback cleared; invoke `onSave(photo)` again |
   | `RetrySave` (Idle/Saving/Saved) | State unchanged (no-op) |
2. **Delete host/UI boundary frozen:**
   Delete is not a reducer event: the confirmation sheet invokes
   `onDelete: suspend (Long) -> Boolean`, a normal `true` calls `onBack()` once,
   and `false` retains the row/detail while showing viewer-local Snackbar text
   `Delete failed` with action Retry. The
   exact Compose integration proof is `GalleryPhotoViewerContractTest`; it
   asserts false retention, retry callback, true one-pop, and cancellation
   propagation. No `DeleteRequested`, `DeleteResult`, `isDeleting`, or
   production `Deleted` state is introduced.
3. **imageContent parameter placement and forwarding anchor frozen:**
   `GalleryPhotoDetailScreen` exposes `imageContent` after `purchaseGateway`:
   `@Composable (String?, Int, String?, Modifier, () -> Unit, () -> Unit,
   () -> Unit) -> Unit = ::GalleryPhotoImageContent`; the complete
   `PhotoDetailDialog` declaration is
   `(Photo, () -> Unit, suspend (Long) -> Boolean, suspend (Photo) -> Boolean,
   (Photo) -> Unit, PurchaseGateway, imageContent)` with defaults only on
   `purchaseGateway` and `imageContent`, exactly as frozen in Phase 2. The
   production `GalleryPhotoImageContent` uses
   `key(attempt) { AsyncImage(model, contentDescription, modifier, callbacks) }`
   and forwarding is unchanged through both Voyager and the GalleryScreen
   inline fallback.
   The complete shared declaration has no ellipses:

   ```kotlin
   @Composable
   fun PhotoDetailDialog(
       photo: Photo,
       onDismiss: () -> Unit,
       onDelete: suspend (Long) -> Boolean,
       onSave: suspend (Photo) -> Boolean,
       onShare: (Photo) -> Unit,
       purchaseGateway: PurchaseGateway = PurchaseGatewayProvider.current,
       imageContent: @Composable (
           model: String?, attempt: Int, contentDescription: String?, modifier: Modifier,
           onLoading: () -> Unit, onSuccess: () -> Unit, onError: () -> Unit,
       ) -> Unit = ::GalleryPhotoImageContent,
   )
   ```
   `GalleryPhotoDetailScreen` forwards all seven named arguments unchanged;
   the `GalleryScreen` inline fallback forwards the same seven named arguments,
   with `onSave = { selected -> saveToPhotos(resolveImagePath(selected.imagePath)
   ?: selected.imagePath, null) }` and no favorite callback.
   `MatchedImageDestination` invokes it with `resolvedPath`, `loadAttempt`,
   `photo.poseName`, and event dispatches; tests inject a fake lambda without
   unmocked Coil.
4. **Observable acceptance & symbol anchors frozen:**
   Verified root Gradle tasks are `./gradlew :composeApp:allTests`,
   `./gradlew :shared:allTests`, `./gradlew :composeApp:iosSimulatorArm64Test`,
   and `./gradlew :shared:iosSimulatorArm64Test`.
   Symbol anchors are frozen across `GalleryListScreen`, `GalleryDetailVoyagerScreen`, `GalleryPhotoDetailScreen`,
   `PhotoDetailDialog`, `GalleryPhotoImageContent`, `saveToPhotos`, and
   `PhotoRepository.deletePhoto`.
   Test symbols are `GalleryPhotoViewerStateTest.totalReducerGuards`,
   `GalleryPhotoViewerContractTest.missingImageRetryKeepsPathAndIncrementsAttempt`,
   and `GalleryPhotoViewerContractTest.deleteFailureShowsRetryAndRetainsDetail`.
   Physical iPhone / Mobile MCP and Android parity remain strictly unresolved follow-ups.

## Readiness

This revised package is ready for a fresh independent Planning Reviewer. The
task remains planning-only and no source implementation is authorized until a
reviewer returns `READY_FOR_WORK`; the previous reviewer verdict was
`REVISE_PLAN`.

## Remaining unresolved questions

- Physical iPhone/Mobile MCP availability in this workspace.
- Android KMP target/parity (deferred by FEAT-002 and current build files).
- Whether Product Authority ever wants Save/Share to become free; this plan
  deliberately retains the approved FEAT-011 gate.

<!-- PLAN_FINAL: revisions answer the independent review challenges; no code was implemented. -->
