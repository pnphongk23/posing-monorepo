---
phase: 4
title: "Recovery and verification"
status: pending
priority: P1
effort: "4h"
dependencies: [2, 3]
---

# Phase 4: Recovery and verification

## Overview

Exercise the v2 state matrix and produce target-scoped evidence. Keep the
prototype read-only and distinguish deterministic simulator/unit proof from
unavailable physical-device or Android proof.

## TDD/verification steps

1. **RED:** add regression cases for image error after transition, repeated
   retry, save-error retry with a fake Boolean callback, the host/UI-only delete
   false/true contract, missing-file idempotency, UTC date/time formatting,
   viewer-local failure feedback, and rapid Back/delete input. The fake loader must assert
   `RetryImage` increments the attempt while the resolved path and
   `photo:<id>` key remain equal; no test may depend on unmocked Coil.
2. **GREEN:** run focused common tests, matched-transition tests, shared iOS
   simulator repository tests, and the iOS build/test lane documented by the
   repo; capture output paths.
3. **REFACTOR/REPORT:** inspect semantics/accessibility and reduced-motion
   behavior; record physical iPhone/Mobile MCP status; run `ak plan validate`
   and `ak plan reindex --apply` only after files are final.

## Related checks

- `./gradlew :composeApp:allTests` (verified root task for Compose common and target tests)
- `./gradlew :shared:allTests` (verified root task for all shared targets)
- `./gradlew :composeApp:iosSimulatorArm64Test` (verified root task for Compose iOS simulator tests)
- `./gradlew :shared:iosSimulatorArm64Test` (verified root task for shared SQLite/repository tests)
- `ak plan validate plans/260909-1137-gallery-photo-viewer-v2 --json`
- `srcwalk review --staged` before handoff if implementation is later staged

## Frozen symbol-level verification anchors

- `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/GalleryScreen.kt:GalleryScreen`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt:GalleryListScreen`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt:GalleryDetailVoyagerScreen`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/PhotoDetailDialog.kt:GalleryPhotoDetailScreen`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/PhotoDetailDialog.kt:PhotoDetailDialog`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/PhotoDetailDialog.kt:GalleryPhotoImageContent`
- `mobile/composeApp/src/commonTest/kotlin/com/aipose/ui/screens/gallery/GalleryPhotoViewerContractTest.kt:missingImageRetryKeepsPathAndIncrementsAttempt`
- `mobile/composeApp/src/commonTest/kotlin/com/aipose/ui/screens/gallery/GalleryPhotoViewerContractTest.kt:deleteFailureShowsRetryAndRetainsDetail`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/MatchedImageTransition.kt:MatchedImageDestination`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/MatchedImageTransition.kt:destinationChromeVisible`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/GalleryViewModel.kt:GalleryViewModel.deletePhoto`
- `mobile/shared/src/commonMain/kotlin/com/aipose/data/PhotoRepository.kt:PhotoRepository.deletePhoto`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/platform/SaveToPhotos.kt:saveToPhotos`
- `com.aipose.data.PhotoRepositoryDeletionTest` (`mobile/shared/src/iosSimulatorArm64Test/...`)
- `com.aipose.navigation.MatchedImageTransitionTest` (`mobile/composeApp/src/commonTest/...`)
- `com.aipose.ui.screens.gallery.GalleryPhotoViewerStateTest` (`mobile/composeApp/src/commonTest/...`)
- `com.aipose.ui.screens.gallery.GalleryPhotoViewerContractTest` (`mobile/composeApp/src/commonTest/...`)

## Success criteria

- [ ] All v2 states are covered by deterministic tests and acceptance evidence.
- [ ] Delete has no reducer event: `GalleryPhotoViewerContractTest` covers
      false → `Delete failed` + Retry + retained row/detail, and true → exactly
      one `onBack()`/pop; cancellation remains propagated.
- [ ] Existing gallery deletion/transition regressions remain green.
- [ ] No claim of Android or physical-iPhone parity is made without evidence.
- [ ] Independent review has no BLOCKER/REQUIRED findings before handoff.
- [ ] Stop-ship: Compose common tests compile/pass (`:composeApp:allTests`), shared iOS simulator tests
      pass (`:shared:iosSimulatorArm64Test`), transition contracts pass, viewer semantics pass, and no blank
      framed image appears in loading/error/flight states.
- [ ] Physical iPhone/Mobile MCP and Android remain explicitly unresolved
      follow-up evidence, not silently claimed parity.
- [ ] Verification records exact root task output; no invalid `:mobile:*`
      project path is used.
