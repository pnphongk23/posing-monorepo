---
schema_version: 1
title: Manage a Local Photo Gallery
relationships:
  specs:
    - "[[product-feature-inventory]]"
    - "[[technical-architecture]]"
    - "[[ui-ux-system]]"
    - "[[model-entity-catalogue]]"
    - "[[erd]]"
    - "[[api-catalogue]]"
  decisions:
    - "[[DEC-004-feat-002-gallery-parity-matrix|DEC-004]]"
  plans:
    - "[[260819-0735-feat-002-local-photo-gallery/plan|260819-0735]]"
  reports:
    - "[[REP-002-feature-gap-and-release-readiness-audit|REP-002]]"
  rules: []
  features:
    - "[[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]"
  source_paths:
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PhotoRepository.kt
    - mobile/shared/src/commonMain/sqldelight/com/aipose/Photo.sq
    - mobile/shared/src/commonMain/sqldelight/com/aipose/Pose.sq
    - mobile/composeApp/src/iosMain/kotlin/com/aipose/platform/SaveToPhotos.ios.kt
type: feature
id: FEAT-002
status: approved
created: 2026-08-09
approved: 2026-08-19
approved_by: phongpn
---

# FEAT-002: Manage a Local Photo Gallery

## Introduction

The Photographer reviews and manages locally captured photos: reactive list,
grid/list presentation, detail, favorite, deletion, and native Photos export.
The canonical local records are [`Photo`](../specs/data-contract.md#photo)
and, for pose references, the canonical [`Pose`](../specs/data-contract.md#pose) in `local` state (formerly `PersonalPose`).
Capture is [FEAT-001](./FEAT-001-capture-a-photo-on-mobile.md); no server API is
owned by this feature.

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Photographer | User | Review and manage local photos | Browse, favorite, delete, and export |
| Native Photos library | External system | Store an exported copy | Enforce platform permission/write behavior |

### Preconditions

- The local SQLDelight database can be opened and records point to app-local assets.

### Trigger

The Photographer opens Gallery or selects a photo action.

### Main flow

1. **Actor:** The Photographer opens Gallery. **System:** The app presents reactive local `Photo` records.
2. **Actor:** The Photographer selects a layout or photo. **System:** The app presents the same records in grid/list or detail.
3. **Actor:** The Photographer chooses favorite, delete, or export. **System:** The app performs the action and reports its confirmed outcome.

### Alternative flows

- **A1 — Empty gallery.** Source step: 1. Condition: no local records exist. Behavior: show an empty state and Camera call to action. Ends with: empty Gallery.
- **A2 — Export.** Source step: 3. Condition: Photos permission is granted. Behavior: copy the local image and report the result. Ends with: local copy retained.

### Exception flows

- **E1 — Missing file.** Source step: 2. Failure: metadata points to no readable file. Handling: show a placeholder and a recoverable action. Prohibited: crashing or claiming a valid skeleton.
- **E2 — Delete/export fails.** Source step: 3. Failure: a file or native write fails. Handling: preserve enough state for retry and report failure. Prohibited: claiming complete success.

### Postconditions

- **Success:** The confirmed local metadata/presentation/action state is reflected in the UI.
- **Failure:** The last confirmed state and local copy remain recoverable.

### Current evidence

- **Observed:** Gallery UI/ViewModel, reactive SQLDelight queries, favorite
  mutation, and mobile local pose storage exist.
- **Partial:** `PhotoRepository.deletePhoto` removes only the database row;
  complete file-plus-metadata deletion and Android parity are not proven.
- **Known gaps:** [REP-002 GAP-004](../reports/REP-002-feature-gap-and-release-readiness-audit.md#gap-004--gallery-deletion-leaves-private-image-files-behind)
  and the gallery findings document file cleanup/export uncertainty.

### Traceability

| Concern | Canonical reference | Evidence |
| --- | --- | --- |
| Entities | [`Photo`](../specs/data-contract.md#photo), [`Pose`](../specs/data-contract.md#pose) (local; formerly `PersonalPose`) | [`Photo.sq`](../../../mobile/shared/src/commonMain/sqldelight/com/aipose/Photo.sq), [`Pose.sq`](../../../mobile/shared/src/commonMain/sqldelight/com/aipose/Pose.sq) |
| ERD | [Mobile local physical graph](../specs/data-contract.md#mobile-local) | `Photo.poseId` is an optional FK to `Pose.poseId` |
| API | None; local database/storage only | No gallery HTTP endpoint found |
| Supporting UI | Gallery ViewModel/detail and platform export | [`GalleryViewModel.kt`](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/GalleryViewModel.kt), [`PhotoDetailDialog.kt`](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/PhotoDetailDialog.kt), [`SaveToPhotos.ios.kt`](../../../mobile/composeApp/src/iosMain/kotlin/com/aipose/platform/SaveToPhotos.ios.kt) |

## Requirements

- **FR-001:** Gallery presentation reads local `Photo` records reactively.
- **FR-002:** Favorite, delete, and export outcomes must be confirmed before success is shown.
- **FR-003:** Gallery search filters photos by case-insensitive substring on
  `Photo.poseName` and linked `Pose.name` when `poseId` is set (prototype
  title/tag semantics map to pose-name text; Plan `260819-0735` Option A).
- **BR-001:** Deleting a photo removes the Photo row and owned `imagePath` file;
  deletion is not complete while owned photo files remain.
- **BR-002:** When `Photo.poseId` references a `Pose` (in `local` state, formerly `PersonalPose`), cascade delete of
  the Pose and owned assets occurs only when no other `Photo` rows still
  reference that `poseId` after the delete (last-reference rule; explicit
  orchestration — FK `ON DELETE SET NULL` is not relied upon).
- **BR-003:** Export to the native Photos library is Save to Photos only (no
  share sheet or generic file export). iOS delivery is in scope for Plan
  `260819-0735`; Android parity is deferred to a future slice.

## Acceptance

- [ ] Gallery presents local records in grid/list and detail states.
- [ ] Favorite updates the local row and the visible state.
- [ ] Missing-file and deletion/export failures remain recoverable.

## Relationships

- Shared references: [Photo](../specs/data-contract.md#photo), [Pose](../specs/data-contract.md#pose) (local; formerly `PersonalPose`), [ERD mobile](../specs/data-contract.md#mobile-local), [API](../specs/api-contract.md).
- Related feature: [FEAT-001](./FEAT-001-capture-a-photo-on-mobile.md).
### Supporting evidence

- [`GalleryScreen.kt`](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/GalleryScreen.kt)
- [`GalleryViewModel.kt`](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/GalleryViewModel.kt)
- [`PhotoRepository.kt`](../../../mobile/shared/src/commonMain/kotlin/com/aipose/data/PhotoRepository.kt)
- [`REP-002`](../reports/REP-002-feature-gap-and-release-readiness-audit.md)
