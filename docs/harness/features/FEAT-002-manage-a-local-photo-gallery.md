---
schema_version: 1
title: Manage a Local Photo Gallery
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[product-feature-inventory]]"
    - "[[ui-ux-system]]"
  decisions: []
  plans: []
  reports: []
  rules: []
  features:
    - "[[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]"
  source_paths:
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PhotoRepository.kt
    - mobile/composeApp/src/iosMain/kotlin/com/aipose/platform/SaveToPhotos.ios.kt
    - docs/prototype/screens/gallery.html
    - docs/prototype/scripts/view-toggle.js
    - docs/prototype/scripts/button-press.js
type: feature
id: FEAT-002
status: draft
created: 2026-08-09
---

# FEAT-002: Manage a Local Photo Gallery

## Introduction

**Purpose:** Let a mobile user review and manage photos captured by the app.

**In scope:** Reactive local listing, local timezone date grouping, grid/list modes, photo detail view, favorite toggle, destructive deletion confirmation, complete deletion (metadata and file), native photo library export, and permission handling. (Applies to both Android and iOS targets).

**Out of scope:** Cloud sync, app-managed folders/albums, photo editing, search within gallery, and recovering a photo after permanent deletion is finalized. (Android target support is within scope but is currently an unresolved parity gap).

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Photographer | User | Browse, inspect, and manage captured photos | Set layout preferences, toggle favorites, confirm deletions, and export photos |
| Native Photos Library | External System | Save exported photos to native device storage | Manage native permissions and execute write blocks (Photo Library on iOS, MediaStore on Android) |

### User needs

- Scan recent captured images quickly in a grid or list form grouped by day.
- Inspect an image in detail and trigger favorite, export, or delete.
- Confirm deletion explicitly to prevent accidental data loss.
- Receive clear feedback for loading, empty, success, and partial failure states.

### Preconditions

- The local SQLDelight database can be successfully opened.
- Stored photo paths refer to files inside the app's private storage directory.

### Trigger

The Photographer opens the App Gallery from the camera screen or navigation.

### Main flow

1. **System:** The app loads local photo records from the database, groups them chronologically by local timezone date (Today, Yesterday, or specific dates) based on the device's clock, and displays them in a grid.
2. **Actor:** The Photographer toggles between grid and list layout modes. **System:** The app switches the visual presentation immediately without modifying any records.
3. **Actor:** The Photographer taps a photo thumbnail. **System:** The app displays the photo in detail view, exposing favorite status, delete button, and export action.
4. **Actor:** The Photographer triggers an action (favorite, delete, or export). **System:** The app executes the requested operation, displays success or failure feedback, and reactively refreshes the gallery list.

### Alternative flows

- **A1 — Empty App Gallery.** Source step: 1. Condition: no photos exist in the database. Behavior: the system displays an empty state screen with a call to action to open the Camera. Ends with: empty state displayed.
- **A2 — Export photo.** Source step: 4. Condition: user selects export. Behavior: the system checks permission to access the Native Photos Library. If authorized, it copies the image file to the Native Photos Library and shows a success banner. Ends with: photo exported.

### Exception flows

- **E1 — Export fails.** Source step: 4. Failure: the user denies native library permission, the source file is missing, or the write fails. Handling: the system displays an error banner and does not report success. Prohibited: reporting the photo as successfully exported.
- **E2 — Missing image file.** Source step: 3. Failure: metadata exists in database but the physical file is missing from local app storage. Handling: the system renders a placeholder image with a missing-file icon and allows the user to delete the broken record. Prohibited: crashing the application or mutating metadata without user action.
- **E3 — Delete is incomplete.** Source step: 4. Failure: either metadata or the app-owned image file cannot be removed. Handling: the system reports the partial failure and retains enough state for retry or reconciliation. Prohibited: claiming permanent deletion while an app-owned copy remains.

### Postconditions

- **Success Outcomes:**
  - *Favorite:* The database metadata is updated with the new favorite status and persisted.
  - *Delete:* Both the database metadata record and the local image file on disk are removed completely.
  - *Export:* A copy of the image file is successfully written to the native device photo library, leaving the local private app copy intact.
- **Failure/Incomplete Outcomes:**
  - *Favorite Failure:* The database is unchanged, favorite status reverts to its original value, and the user is notified.
  - *Delete Failure (Incomplete Delete):* If either the metadata delete or the disk file deletion fails, the remaining asset (orphaned file or database record) is preserved to prevent data loss. The user is notified of the partial failure to allow retry.
  - *Export Failure:* The native library remains unchanged (no duplicate or corrupt image is written), local private app files are preserved, and the user is notified.

## Requirements

- **FR-001:** The gallery shall support rendering loading, empty, grid, and list layout states.
- **FR-002:** Photos shall be grouped chronologically (newest first) by the user's local timezone date.
- **FR-003:** Deleting a photo shall require the user to confirm the action in a destructive confirmation dialog.
- **FR-004:** A confirmed deletion shall remove the metadata record from the database AND delete the image file from app storage (complete deletion).
- **FR-005:** The delete control shall be disabled while deletion is in progress to prevent double submissions.
- **FR-006:** The app shall handle partial deletion failures by notifying the user and allowing retry.
- **FR-007:** Exporting a photo shall request native library permissions and copy the file, showing clear success/error statuses.
- **FR-008:** The app shall allow the Photographer to toggle the favorite status of any photo. Toggling favorite status shall immediately persist the updated status to the local database, and updates must be reactively reflected on the gallery view.
- **BR-001:** Gallery presentation toggles must not mutate database records.
- **BR-002:** A confirmed permanent delete shall remove both the local metadata and the app-owned image file, or report that deletion is incomplete.
- **NFR-001:** The App Gallery list must reactively update to database changes without a manual refresh.

## Acceptance

- [ ] Grid and list layout modes render the same set of captured photos.
- [ ] Photos are grouped by local day (using local timezone) with newest dates at the top.
- [ ] Tapping delete opens a confirmation dialog. Cancelling preserves metadata and the image file.
- [ ] Confirming delete deletes BOTH the SQLDelight metadata and the physical file from disk, leaving no orphaned files.
- [ ] If file deletion fails, the app alerts the user of a partial failure and does not report success.
- [ ] Exporting to Native Photos Library displays a success banner on completion and a clear error on failure/denial.
- [ ] Tapping favorite toggles the favorite status of the photo, updates the database, and is reflected on the gallery list.
- [ ] If toggling favorite fails, the status remains unchanged and an error is displayed.

**Scenario: toggle favorite status**  
Given a photo detail is open and the photo has a false favorite status  
When the Photographer taps the favorite button  
Then the favorite status becomes true, the database record is updated, and the detail view displays the active favorite state.

**Scenario: confirmed photo deletion**  
Given a photo detail is open and the image file exists on disk  
When the Photographer taps delete and confirms  
Then the delete button is disabled, the database record is removed, the physical file is deleted, and the gallery reactively updates.

**Scenario: export photo permission denied**  
Given a photo detail is open  
When the Photographer taps export and denies library permission  
Then the system cancels the export, shows a permission error banner, and does not copy the file.

## Relationships

- Specs: [[technical-architecture]], [[product-feature-inventory]], [[ui-ux-system]]
- Features: [[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]
- Prototype Mappings:

| Prototype Path | Observed Interaction | Status | FR/Acceptance Coverage |
| --- | --- | --- | --- |
| [gallery.html](../../prototype/screens/gallery.html) | Displays a grid populated from photo fixtures, including a missing-photo placeholder. | Observed | FR-001 content and missing-file rendering reference only |
| [view-toggle.js](../../prototype/scripts/view-toggle.js) | Attempts to bind view-switching handlers to `.nb-view-toggle__btn`. | Failed (Prototype Limitation) | FR-001 layout switcher is inert in the prototype because the target toggle buttons are missing from the page. |

- Implementation Evidence:

| Path | Symbol | Status | Role / Detail |
| --- | --- | --- | --- |
| [GalleryScreen.kt](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/GalleryScreen.kt) | `GalleryScreen` | Observed | Production screen displaying captured photos reactively. |
| [GalleryViewModel.kt](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/GalleryViewModel.kt) | `GalleryViewModel` | Observed | Collects the photo flow, derives loading/empty/date-grouped state, and delegates favorite and metadata deletion operations. |
| [PhotoCard.kt](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/PhotoCard.kt) | `PhotoCard` | Observed | Component rendering individual photo thumbnails in grid or list view. |
| [PhotoDetailDialog.kt](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/PhotoDetailDialog.kt) | `PhotoDetailDialog` | Observed | Dialog modal displaying selected photo, favorite status, and delete/save actions. |
| [SaveToPhotos.kt](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/platform/SaveToPhotos.kt) | `saveImageToPhotos` | Observed | Expect function definition for exporting photos to the platform gallery. |
| [SaveToPhotos.ios.kt](../../../mobile/composeApp/src/iosMain/kotlin/com/aipose/platform/SaveToPhotos.ios.kt) | `saveImageToPhotos` | Failed | Calls the iOS Photos change block but sets success inside that block and does not inspect the operation result/error, so failure can be reported as success. (Delivery Gap). |
| [PhotoRepository.kt](../../../mobile/shared/src/commonMain/kotlin/com/aipose/data/PhotoRepository.kt) | `PhotoRepository.deletePhoto` | Failed | Only deletes photo metadata from the database; leaves the local image file on disk. (Delivery Gap). |
| [PhotoRepository.kt](../../../mobile/shared/src/commonMain/kotlin/com/aipose/data/PhotoRepository.kt) | `PhotoRepository` | Observed | Manages SQLDelight database operations for photos. |
| `mobile/composeApp/src/androidMain/` | None | Unresolved (TBD) | Android media store export implementation is not yet written (parity gap). |
