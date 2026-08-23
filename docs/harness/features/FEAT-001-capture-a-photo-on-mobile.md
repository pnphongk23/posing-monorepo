---
schema_version: 1
type: feature
id: FEAT-001
title: Capture a Photo on Mobile
status: approved
created: 2026-08-09
approved: 2026-08-13
approved_by: phongpn
relationships:
  specs:
    - "[[product-feature-inventory]]"
    - "[[technical-architecture]]"
    - "[[ui-ux-system]]"
    - "[[model-entity-catalogue]]"
    - "[[erd]]"
    - "[[api-catalogue]]"
  decisions: []
  plans: []
  reports:
    - "[[REP-002-feature-gap-and-release-readiness-audit|REP-002]]"
  rules: []
  features:
    - "[[FEAT-002-manage-a-local-photo-gallery|FEAT-002]]"
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
  source_paths:
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraContract.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PhotoRepository.kt
    - mobile/shared/src/commonMain/sqldelight/com/aipose/Photo.sq
    - docs/prototype/screens/camera-live.html
---

# FEAT-001: Capture a Photo on Mobile

## Introduction

The Photographer captures a still image through the mobile Camera surface and
stores one local [`Photo`](../../spec/data/entities/photo.md)
record. Camera controls, permission outcomes, capture feedback, and the handoff
to Gallery belong here. Pose extraction is [FEAT-004](FEAT-004-extract-reusable-pose-images.md);
gallery management is [FEAT-002](FEAT-002-manage-a-local-photo-gallery.md).
CameraScreen does not own extraction intake; mobile extraction reuses the
camera/library image source entry points via [FEAT-004](FEAT-004-extract-reusable-pose-images.md)/[FEAT-005](FEAT-005-manage-a-pose-guide.md).

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Photographer | User | Capture one usable local photo | Grant permission and operate Camera |
| Native device camera | External system | Supply frames and captured bytes | Enforce platform camera behavior |

### Preconditions

- Camera permission is authorized or can be requested on a supported device.

### Trigger

The Photographer presses the shutter.

### Main flow

1. **Actor:** The Photographer opens Camera. **System:** The app presents the preview after permission is authorized.
2. **Actor:** The Photographer adjusts controls. **System:** The app reflects the selected facing, flash, grid, zoom, or ratio state.
3. **Actor:** The Photographer presses the shutter. **System:** The app captures bytes, writes local state, and updates the latest thumbnail.

### Alternative flows

- **A1 — Open Gallery.** Source step: 3. Condition: the Photographer taps the latest thumbnail. Behavior: navigate to FEAT-002. Ends with: Gallery displayed.

### Exception flows

- **E1 — Permission denied.** Source step: 1. Failure: the platform does not authorize camera access. Handling: keep capture disabled and show platform settings/request guidance. Prohibited: claiming capture success.
- **E2 — Persistence fails.** Source step: 3. Failure: the file or metadata write is incomplete. Handling: report failure and preserve a recoverable state. Prohibited: claiming one valid photo exists.

### Postconditions

- **Success:** One local `Photo` record and a readable image are expected; current atomic compensation is partial.
- **Failure:** Capture is not reported as successful.

### Current evidence

- **Observed:** `CameraScreen`, the camera contract/native iOS implementation,
  `PhotoRepository`, and the `Photo` SQLDelight table exist.
- **Partial:** The repository contains iOS camera evidence and shared UI; Android
  actual camera support remains unresolved.
- **Known gaps:** [REP-002 GAP-004/GAP-005/GAP-011](../reports/REP-002-feature-gap-and-release-readiness-audit.md#prioritized-backlog)
  record incomplete file/database compensation, collision-resistant capture
  naming, native frame-ratio behavior, and callback/lifecycle gaps.

### Traceability

| Concern | Canonical reference | Evidence |
| --- | --- | --- |
| Entity | [`Photo`](../../spec/data/entities/photo.md) | [`Photo.sq`](../../../mobile/shared/src/commonMain/sqldelight/com/aipose/Photo.sq), [`PhotoRepository.kt`](../../../mobile/shared/src/commonMain/kotlin/com/aipose/data/PhotoRepository.kt) |
| ERD | [Mobile local physical graph](../../spec/data/erd/mobile.md) | [`Photo.sq`](../../../mobile/shared/src/commonMain/sqldelight/com/aipose/Photo.sq) optional `poseId` FK |
| API | None; capture is local/offline | No mobile capture HTTP route found |
| Supporting UI | Camera contract and prototype | [`CameraScreen.kt`](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt), [`camera-live.html`](../../prototype/screens/camera-live.html), [`technical-architecture`](../specs/technical-architecture.md#mobile-capture-and-local-gallery) |

## Requirements

- **FR-001:** Capture is disabled until camera permission is authorized.
- **FR-002:** One accepted capture produces one local photo outcome.
- **BR-001:** A failed or unreadable write must not be represented as a valid capture.

## Acceptance

- [ ] Authorized iOS capture produces one local record and thumbnail.
- [ ] Denied permission leaves capture disabled with recovery guidance.
- [ ] Persistence failure does not claim success.

## Relationships

- Shared references: [Photo](../../spec/data/entities/photo.md), [ERD mobile](../../spec/data/erd/mobile.md), [API](../../spec/api/README.md).
- Related features: [FEAT-002](FEAT-002-manage-a-local-photo-gallery.md), [FEAT-004](FEAT-004-extract-reusable-pose-images.md).
### Supporting evidence

- [`CameraContract.kt`](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraContract.kt)
- [`CameraScreen.kt`](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt)
- [`IOSCameraController.kt`](../../../mobile/composeApp/src/iosMain/kotlin/com/aipose/camera/IOSCameraController.kt)
- [`Photo.sq`](../../../mobile/shared/src/commonMain/sqldelight/com/aipose/Photo.sq)
- [`camera-live.html`](../../prototype/screens/camera-live.html)
- [`REP-002`](../reports/REP-002-feature-gap-and-release-readiness-audit.md)
