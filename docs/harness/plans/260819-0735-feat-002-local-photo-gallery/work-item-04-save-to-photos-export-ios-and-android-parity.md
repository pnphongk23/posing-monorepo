---
work_item: 4
title: Save to Photos export (iOS)
status: completed
priority: P1
effort: L
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 4: Save to Photos export (iOS)

**Kind:** technical / iOS platform

## Tasks

- Keep Save to Photos **only** — no share sheet / generic file export.
- Fix the iOS false-success risk: `SaveToPhotos.ios.kt:9` sets `success = true`
  inside the `performChangesAndWait` change block rather than its completion
  handler; confirm success reflects the actual write (REP-002 line 46).
- Add a success confirmation in `GalleryScreen.kt` (currently only "Save
  failed" is shown on `false`); match prototype "Saved to Photos."
  (`gallery-detail.html`).
- **Android deferred (Maintainer 2026-08-19, iOS-first):** not in this WI.
  The KMP build declares only iOS targets (`composeApp/build.gradle.kts:10-12`,
  `shared/build.gradle.kts:9-11`); Android target + AGP + `androidMain` source
  sets + Android actuals are a **future** FEAT-002 slice (`E-ANDROID-TARGET`
  Excluded).
- Add iOS export tests and a Save-to-Photos manual check on iPhone.

## Scope and affected files

- `mobile/composeApp/src/iosMain/kotlin/com/aipose/platform/SaveToPhotos.ios.kt`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/platform/SaveToPhotos.kt`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/GalleryScreen.kt`
- `mobile/composeApp/src/commonTest/...` (export success/failure tests)

## Success criteria

- Evidence ID **E-GAL-EXPORT**: Save to Photos succeeds on **iOS** with a
  confirmed success message; failure shows a failure message (FR-002, BR-004).
- No share sheet or generic file export introduced.
- iOS write success reflects the real `PHPhotoLibrary` outcome (no false
  success).

## Risks

- **Android scope:** deferred (Maintainer 2026-08-19) — not in this WI; do not
  assume parity = one actual file (`E-ANDROID-TARGET` is Excluded here).
- iOS false-success: success flag set before the write completes.
- Missing success confirmation violates FR-002 ("confirmed before success shown").

## Required evidence

- **E-GAL-EXPORT**: iOS export tests green; manual save confirmation on iPhone.
- **E-ANDROID-TARGET**: Excluded — Android deferred to future plan (Maintainer
  2026-08-19); no Android evidence required in this WI.

## Evidence

### E-GAL-EXPORT — iOS export fixed + success confirmation (WI-04, Peer)

- **Files changed:**
  - `mobile/composeApp/src/iosMain/kotlin/com/aipose/platform/SaveToPhotos.ios.kt`
    — false-success fix: `success` is no longer set to `true` inside the
    `performChangesAndWait` change block. The actual now returns the real
    `PHPhotoLibrary` write outcome (the Boolean returned by
    `performChangesAndWait`), so success is only reported when the platform
    write actually completed.
  - `mobile/composeApp/src/commonMain/kotlin/com/aipose/platform/SaveToPhotos.kt`
    — added a testable seam `saveToPhotos(imagePath, context, perform = ::saveImageToPhotos)`
    (injectable platform perform) and `saveToPhotosConfirmation(saved)` which
    maps the real outcome to the prototype copy: success → `"Saved to Photos."`,
    failure → `"Save failed"`. No signature change to the existing `expect`.
  - `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/GalleryScreen.kt`
    — `onSave` now goes through the `saveToPhotos` seam and shows the
    success confirmation snackbar (previously only the failure snackbar was
    shown).
  - `mobile/composeApp/src/commonTest/kotlin/com/aipose/platform/SaveToPhotosTest.kt`
    — new unit tests (4) for export success/failure paths.
- **Gradle command + results (green):**
  - `./gradlew :composeApp:iosSimulatorArm64Test` → BUILD SUCCESSFUL (41s).
  - `SaveToPhotosTest`: tests=4, failures=0, errors=0, skipped=0.
    (covers success/failure confirmation copy + seam success/failure flow)
  - Full suite: 46 tests, 0 failures/errors — no regression to WI-02 search or
    WI-03 delete (SearchViewModelTest 10, GalleryViewModelTest 5, etc. all
    green).
- **Manual iPhone save confirmation:** deferred to **WI-06** (not part of
  WI-04 per the work item — manual check required there). No UI automation,
  Maestro, or E2E run for this WI.
- **No share sheet / generic file export introduced;** Save to Photos only.
- **Android:** untouched (deferred, `E-ANDROID-TARGET` Excluded).
- **TDD:** tests written first and observed failing (unresolved-reference RED)
  before the seam was implemented; GREEN after implementation.

### E-ANDROID-TARGET — Excluded

Android target deferred to a future FEAT-002 slice (Maintainer 2026-08-19). No
Android evidence required in this WI; no Android code changed.

## Evidence (WI-04, 2026-08-19)

### iOS false-success fix

- `SaveToPhotos.ios.kt`: return value of `performChangesAndWait` (real
  PHPhotoLibrary outcome) instead of setting `success = true` inside the change
  block.

### Success confirmation (FR-002 / prototype)

- `saveToPhotosConfirmation(saved)` → `"Saved to Photos."` or `"Save failed"`.
- `saveToPhotos(...)` testable seam with injectable `perform`.
- `GalleryScreen`: snackbar shows confirmation for both success and failure.

### Unit tests (no E2E — manual iPhone deferred to WI-06)

`mobile/composeApp/src/commonTest/kotlin/com/aipose/platform/SaveToPhotosTest.kt`

```
./gradlew :composeApp:iosSimulatorArm64Test --tests "com.aipose.platform.SaveToPhotosTest"
BUILD SUCCESSFUL — tests=4 failures=0 errors=0
```

### `ckh workflow check`

```
Harness validation passed
```
