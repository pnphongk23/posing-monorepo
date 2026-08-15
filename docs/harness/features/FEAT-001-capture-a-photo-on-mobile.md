---
schema_version: 1
title: Capture a Photo on Mobile
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
    - "[[FEAT-002-manage-a-local-photo-gallery|FEAT-002]]"
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
  source_paths:
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraContract.kt
    - mobile/composeApp/src/iosMain/kotlin/com/aipose/camera
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PhotoRepository.kt
    - docs/prototype/screens/camera-live.html
    - docs/prototype/screens/camera-settings.html
    - docs/prototype/scripts/app.js
    - docs/prototype/scripts/toggle.js
    - docs/prototype/scripts/modal.js
    - docs/prototype/scripts/button-press.js
type: feature
id: FEAT-001
status: approved
created: 2026-08-09
approved: 2026-08-13
approved_by: phongpn
---

# FEAT-001: Capture a Photo on Mobile

## Introduction

**Purpose:** Let a mobile user frame and capture a photo, then persist it into the local App Gallery.

**In scope:** Camera preview, camera flip, flash mode, zoom, frame ratio, capture feedback, duplicate capture protection, permission outcomes (Android/iOS parity), app interruption handling, image storage persistence, read verification, and local photo metadata. (Applies to both Android and iOS targets).

**Out of scope:** Video, cloud backup, pose-extraction processing (which is triggered separately through FEAT-004), and rendering a selected pose reference over the camera preview (covered by FEAT-003).

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Photographer | User | Capture a usable photo and store it locally | Grant permission and operate camera controls |
| Native Device Camera | External System | Supply raw camera frames and handle physical adjustments | Enforce permission gates, configure hardware states, and return captured bytes |

### User needs

- See a live preview before capture.
- Remain on the camera screen after a capture to allow taking multiple photos.
- Receive clear feedback when permission or persistence fails.
- Open the most recent capture via an in-surface thumbnail.

### Preconditions

- The app runs on a supported mobile device (iOS or Android).
- Camera permission is authorized before capture is enabled.

### Trigger

The Photographer activates the shutter button capture control.

### Main flow

1. **Actor:** The Photographer opens the camera screen. **System:** The app requests camera permission when the permission status is undetermined, and shows the live preview when authorized.
2. **Actor:** The Photographer adjusts optional controls (flash, facing, frame grid, frame-ratio, or zoom). **System:** The app updates the preview viewport to reflect the selected configuration.
3. **Actor:** The Photographer presses the shutter button. **System:** The app immediately disables the shutter button to prevent duplicate capture, flashes the screen as feedback, saves the captured image bytes to local app storage, writes a photo metadata record to the local database, verifies the saved file is readable, and updates the in-surface gallery thumbnail.
4. **Actor:** The Photographer continues framing or taps the thumbnail. **System:** The app keeps the Photographer on the camera screen for further captures. If the Photographer taps the thumbnail, the system navigates to the App Gallery.

### Alternative flows

- **A1 — Change camera settings.** Source step: 2. Condition: the user selects another option. Behavior: the system updates camera state without capturing. Resume at step: 2.
- **A2 — Open gallery.** Source step: 4. Condition: the user presses the thumbnail. Behavior: the system navigates to the App Gallery. Ends with: App Gallery displayed.

### Exception flows

- **E1 — Permission denied or restricted.** Source step: 1. Failure: the platform OS does not authorize camera access. 
  - *iOS handling:* The app displays a permission-required screen with a button that routes the user directly to the native System Settings.
  - *Android handling:* The app displays a runtime permission request dialog. If denied, it shows an inline permission-required explanation with a button to request permissions again. If permanently denied (where the OS prevents displaying the system dialog again), the app provides clear settings guidance and a redirection link/button to route the user to Android System Settings to manually enable camera permission.
  - *Prohibited:* Enabling the capture button.
- **E2 — Capture or save fails.** Source step: 3. Failure: physical capture fails or local storage write fails (e.g., storage full). Handling: the system rolls back any partial database transaction, cleans up orphaned image files, displays a failure notification, and re-enables the shutter button. Prohibited: inserting a photo record with a broken file path.
- **E3 — App lifecycle interruption.** Source step: 3. Failure: app is backgrounded, interrupted by a phone call, or terminated during capture. Handling: the system safely cancels the active capture operation, deletes any partial or corrupt files, releases camera hardware locks, and prevents saving corrupt database records.

### Postconditions

- **Success:** One valid image file is durably written to disk, one matching local photo metadata record exists in the database, the thumbnail is updated, and the shutter button is re-enabled.
- **Failure:** No new invalid capture artifacts (database records or orphaned files) are written, and the user receives clear feedback.

## Requirements

- **FR-001:** Capture shall be disabled unless camera permission is authorized.
- **FR-002:** The shutter button shall be disabled immediately upon tap and remain disabled until the photo is fully persisted and validated, preventing duplicate captures.
- **FR-003:** One successful shutter press shall persist exactly one image file to app storage and one photo metadata record to the local database.
- **FR-004:** The camera shall expose facing, zoom, flash, grid, and frame-ratio controls and apply the selected configuration.
- **FR-005:** The camera screen shall display a thumbnail of the most recent capture; tapping it shall navigate to the App Gallery.
- **FR-006:** The app shall verify that the written photo file is readable before updating the thumbnail and reporting success.
- **BR-001:** A photo record must not claim a path that failed to persist or is unreadable.
- **NFR-001:** Camera preview and capture must work completely offline.

## Acceptance

- [ ] Authorized capture creates one local record, writes the file, and updates the thumbnail.
- [ ] Denied camera permission keeps capture disabled and explains how to grant access.
- [ ] On iOS, the permission-denied screen includes a button that successfully routes to iOS Settings.
- [ ] On Android, the permission-denied screen allows requesting permissions again via a dialog, or redirects to settings if permanently denied.
- [ ] Pressing the shutter button once disables it until the write finishes, preventing duplicate photos.
- [ ] App backgrounding or call interruptions during capture result in no file leaks or database corruptions.
- [ ] Storage failure is reported visually, rolls back database changes, and leaves no orphaned metadata.
- [ ] The app verifies the stored file is readable before rendering it in the thumbnail.

**Scenario: successful capture**  
Given camera permission is authorized and device is offline  
When the Photographer presses capture and storage succeeds  
Then the shutter button is temporarily disabled, one image file and one database record are written, the file is confirmed readable, the shutter button is re-enabled, and the latest thumbnail updates.

**Scenario: denied permission**  
Given camera permission is denied  
When the camera screen is shown  
Then capture is disabled, and the screen displays permission guidance with a settings redirection link.

## Relationships

- Specs: [[technical-architecture]], [[product-feature-inventory]], [[ui-ux-system]]
- Features: [[FEAT-002-manage-a-local-photo-gallery|FEAT-002]], [[FEAT-003-browse-and-search-published-poses|FEAT-003]], [[FEAT-004-extract-reusable-pose-images|FEAT-004]]
- Prototype Mappings:

| Prototype Path | Observed Interaction | Status | FR/Acceptance Coverage |
| --- | --- | --- | --- |
| [camera-live.html](../../prototype/screens/camera-live.html) | Main camera UI with shutter, settings popover, flash/grid controls, zoom chip, gallery thumbnail, and a control labelled “Switch camera.” | Observed | FR-001, FR-003, FR-004, FR-005 |
| [camera-settings.html](../../prototype/screens/camera-settings.html) | Performs a redirect with `?settings=open` back to the live camera screen, which consumes the parameter to automatically display the settings dropdown. | Observed | FR-004 |
| [toggle.js](../../prototype/scripts/toggle.js) | UI toggles for grid overlay and flash mode rotation. | Observed | FR-004 |
| [modal.js](../../prototype/scripts/modal.js) | Handles opening/closing settings popover modal. | Observed | FR-004 |
| [app.js](../../prototype/scripts/app.js) (lines 124-165) | Shutter click triggers a mock flash, sound, and redirects immediately to extraction. | Reference-only (Prototype Limitation) | The mock shutter navigation is a prototype-only shortcut. Production behavior stays on the Camera screen to allow multiple captures, saving to the App Gallery. |
| [button-press.js](../../prototype/scripts/button-press.js) | Adds keyboard pressed-state styling and console logging. | Reference-only | None; does not enforce duplicate-capture protection |

- Implementation Evidence:

| Path | Symbol | Status | Role / Detail |
| --- | --- | --- | --- |
| [CameraScreen.kt](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt) | `CameraScreen` capture callback | Observed | Disables the shutter while capture is in flight, writes returned bytes, inserts photo metadata, and refreshes the latest thumbnail. |
| [CameraScreen.kt](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt) | `selectFrameRatio` | Failed | Updates Compose UI state only; no frame-ratio command is sent to the native camera bridge. |
| [CameraContract.kt](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraContract.kt) | `CameraController` | Observed | Expect declaration for native camera operations. |
| [CameraContract.ios.kt](../../../mobile/composeApp/src/iosMain/kotlin/com/aipose/camera/CameraContract.ios.kt) | `CameraController` | Observed | Actual implementation of CameraController for iOS. |
| [IOSCameraController.kt](../../../mobile/composeApp/src/iosMain/kotlin/com/aipose/camera/IOSCameraController.kt) | `IOSCameraController` | Observed | Native iOS camera subsystem wrapper managing capture session and outputs. |
| [IOSCameraPreview.kt](../../../mobile/composeApp/src/iosMain/kotlin/com/aipose/camera/IOSCameraPreview.kt) | `IOSCameraPreview` | Observed | iOS-specific camera preview rendering native UIView. |
| [PhotoRepository.kt](../../../mobile/shared/src/commonMain/kotlin/com/aipose/data/PhotoRepository.kt) | `PhotoRepository` | Observed | Manages photo database metadata operations. |
| [ImageStorage.kt](../../../mobile/shared/src/iosMain/kotlin/com/aipose/data/ImageStorage.kt) | `ImageStorage` | Observed | Native file writer for iOS photo storage. |
| `mobile/composeApp/src/androidMain/` | None | Unresolved (TBD) | No Android camera preview or capture implementation exists (parity gap). |
