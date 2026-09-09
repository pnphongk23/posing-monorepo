# PLAN_DRAFT — Gallery photo viewer v2

Status: revised after independent reviewer challenges; candidate remains
planning-only and requires fresh readiness review before implementation.

## Goal

Apply the approved viewer-first gallery detail prototype to the current
iOS-first Compose/KMP route while retaining the local `Photo` contract and
existing matched-image navigation.

## Evidence snapshot

- List/detail path: `GalleryScreen.kt:59-225` → `Navigation.kt:243-285` →
  `PhotoDetailDialog.kt:56-293`.
- Local persistence: `Photo.sq:2-47`, `PhotoRepository.kt:30-66`; no gallery
  HTTP/API contract.
- Existing transition: `PhotoCard.kt:166-221`, `MatchedImageTransition.kt:309-353`;
  `photo:<id>` key and readiness-gated chrome are already tested.
- Approved v2 reference: `docs/prototype/screens/gallery-detail-v2.html:236-407`
  and `docs/prototype/README.md:115-117`.
- Existing tests: `GalleryViewModelTest`, `GalleryGridDefaultsTest`,
  `MatchedImageTransitionTest`, `PhotoRepositoryDeletionTest`.

## Frozen plan choice and signatures

Use one small pure `GalleryPhotoViewerState`/reducer plus the existing detail
Composable; the in-place-flags fallback is rejected. The reducer signature is
`fun reduce(state: GalleryPhotoViewerState, event: GalleryPhotoViewerEvent):
GalleryPhotoViewerState`, with events `ImageLoading`, `ImageReady`,
`ImageFailed`, `RetryImage`, `SaveRequested`, `SaveResult(Boolean)`, and
`RetrySave`. Exact fields are `photo: Photo`, `resolvedPath: String?`,
`transitionKey: String`, `loadAttempt: Int`, `media: MediaStatus`,
`save: SaveStatus`, and `feedback: FeedbackMessage?`; `MediaStatus` is exactly
`Loading | Ready | Missing`, `SaveStatus` is exactly `Idle | Saving | Saved |
Failed(message: String)`, and `FeedbackMessage` is exactly
`Info(text: String) | Error(text: String, canRetry: Boolean)`. There are no
computed `isSaving`/`isDeleting` fields and no delete events in the reducer.
`RetryImage` increments `loadAttempt` while retaining the exact resolved path and
`photo:<id>` transition key.

The exact delete callback chain is:

`GalleryListScreen.onPhotoClick(Photo)` →
`GalleryDetailVoyagerScreen(photo: Photo, onDeletePhoto: suspend (Long) -> Unit)` →
`GalleryPhotoDetailScreen(photo: Photo, onBack: () -> Unit, onDelete: suspend
(Long) -> Boolean, onSave: suspend (Photo) -> Boolean, onShare: ((Photo) -> Unit)? = null,
purchaseGateway: PurchaseGateway = PurchaseGatewayProvider.current,
imageContent: @Composable (String?, Int, String?, Modifier, () -> Unit, () -> Unit,
() -> Unit) -> Unit = ::GalleryPhotoImageContent)` →
`PhotoDetailDialog(photo: Photo, onDismiss: () -> Unit, onDelete: suspend (Long) -> Boolean,
onSave: suspend (Photo) -> Boolean, onShare: (Photo) -> Unit,
purchaseGateway: PurchaseGateway = PurchaseGatewayProvider.current,
imageContent: @Composable (String?, Int, String?, Modifier, () -> Unit, () -> Unit,
() -> Unit) -> Unit = ::GalleryPhotoImageContent)`.

The detail host catches non-cancellation exceptions and maps them to `false`;
`CancellationException` is rethrown; other `Exception` becomes `false`; `true`
is returned only after normal completion. The list's hoisted `GalleryViewModel`
owns the callback; detail does not construct a second ViewModel. Delete is
host/UI-only: `GalleryPhotoViewerContractTest` fakes `onDelete = false` and
asserts retained row/detail plus viewer-local
Snackbar text `Delete failed` with Retry; a true result asserts exactly one
`onBack()`/pop. Delete feedback is not reducer feedback. No delete event or production
`Deleted` state is added.

`PhotoDetailDialog` is shared by the Voyager route and the `GalleryScreen`
inline fallback; both callers are in the same write-set and use the same
reducer/action contract. Successful delete dismisses/pops once; there is no
production `Deleted` reducer state.

Save is injected as `suspend (Photo) -> Boolean` and returns the actual
`saveToPhotos(resolveImagePath(photo.imagePath) ?: photo.imagePath, null)`
result. `SaveResult(false)` enters retryable `SaveStatus.Failed("Save failed")`
with “Save failed”;
`RetrySave` invokes the callback again. Existing FEAT-011 premium taps open
`PaywallScreen`; the prototype overflow button is excluded, leaving Share,
Save, and Trash as the complete action surface.

Missing retry is deterministic: tests use reducer events/fake loader, not
unmocked Coil. Retry increments nonce/attempt and reuses the same path; a
repeated image failure remains `Missing`, disables Save/Share/Trash, retains
the Photo row, leaves Back enabled, and never reveals a blank framed image.
`GalleryPhotoDetailScreen` owns the exact `imageContent` parameter after
`purchaseGateway`:
`@Composable (String?, Int, String?, Modifier, () -> Unit, () -> Unit, () -> Unit) -> Unit = ::GalleryPhotoImageContent`.
Its production default delegates to the addressable symbol `PhotoDetailDialog.kt:GalleryPhotoImageContent`
(which wraps `key(attempt) { AsyncImage(...) }`), forwarded unchanged to `PhotoDetailDialog`;
tests inject a fake lambda without live Coil.

Transition table: initial → `Loading`; `ImageLoading` → `Loading`;
`ImageReady` → `Ready`; `ImageFailed` → `Missing`; `RetryImage` → `Loading`
with `loadAttempt + 1`; `SaveRequested` → `Saving` and clears feedback;
`SaveResult(true)` → `Saved` + `Info("Saved to Photos.")`;
`SaveResult(false)` → `Failed("Save failed")` + `Error("Save failed", true)`;
`RetrySave` → `Saving` and invokes the same save callback again. Unsupported
pairs are total no-ops: repeated `ImageFailed` remains `Missing`, `RetryImage`
outside `Missing`, `SaveRequested` in Loading/Missing/Saving, `SaveResult` outside
Saving, and `RetrySave` outside Failed leave the entire state unchanged. These
guards are asserted by `GalleryPhotoViewerStateTest`.

## Acceptance

State transitions, semantics, transition continuity, local delete/file safety,
and truthful save/export outcomes are all tested. iOS physical-device and
Android parity remain explicitly target-scoped/unresolved.

Stop-ship commands are the verified root tasks (there is no `:mobile:*`
prefix): `./gradlew :composeApp:allTests`, `./gradlew :shared:allTests`,
`./gradlew :composeApp:iosSimulatorArm64Test`, and
`./gradlew :shared:iosSimulatorArm64Test`. Symbol anchors are the gallery
functions in `GalleryScreen.kt:57-227`, `Navigation.kt:243-285`,
`PhotoDetailDialog.kt:56-293` plus `PhotoDetailDialog.kt:GalleryPhotoImageContent`,
`MatchedImageTransition.kt:309-353`, plus
`GalleryPhotoViewerStateTest.totalReducerGuards`,
`GalleryPhotoViewerContractTest.missingImageRetryKeepsPathAndIncrementsAttempt`,
and `GalleryPhotoViewerContractTest.deleteFailureShowsRetryAndRetainsDetail`.

Physical iPhone/Mobile MCP and Android evidence remain unresolved follow-ups;
no parity is claimed without target evidence.

## Required reviewer challenges

1. Does the proposed state seam solve real testability gaps without adding
   unnecessary architecture?
2. Is retaining FEAT-011 Save/Share entitlement gating the correct safe default?
3. Are missing-file retry and delete failure semantics implementable with current
   resolver/repository contracts?
4. Does the plan preserve matched-image navigation and gallery state ownership?
5. Is the evidence/verification surface sufficient for iOS-only delivery?
