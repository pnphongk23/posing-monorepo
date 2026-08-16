---
schema_version: 1
type: feature
id: FEAT-008
title: Use Published Poses
status: draft
created: 2026-08-15
relationships:
  specs:
    - "[[product-feature-inventory]]"
    - "[[technical-architecture]]"
    - "[[ui-ux-system]]"
    - "[[model-entity-catalogue]]"
    - "[[erd]]"
    - "[[api-catalogue]]"
  decisions: []
  plans:
    - "[[260809-2241-selected-pose-camera-handoff/plan|260809-2241]]"
  reports:
    - "[[REP-003-pose-reference-library-convergence-delivery|REP-003]]"
  rules: []
  features:
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-006-publish-a-pose|FEAT-006]]"
  source_paths:
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseReferenceKey.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PreparedPoseReference.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PoseDetailScreen.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraState.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt
---

# FEAT-008: Use Published Poses

## Introduction

The signed-in user can save/unsave a published pose and prepare it for Try Pose
in Camera. Browsing is [FEAT-003](FEAT-003-browse-and-search-published-poses.md);
publication lifecycle is [FEAT-006](FEAT-006-publish-a-pose.md). Use never grants
ownership or management rights.

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Signed-in user | User | Save and try a published pose | Choose a pose and manage personal use state |
| Visitor | User | Understand access requirements | Follow sign-in guidance |

### Preconditions

- A published pose detail is available and its render can be prepared; account/session support is not implemented in this repository.

### Trigger

The user chooses Save, Unsave, Saved, or Try Pose.

### Main flow

1. **Actor:** The user opens published detail. **System:** The app presents the source-qualified pose reference.
2. **Actor:** The user chooses Try Pose. **System:** The app downloads/verifies the render before handing it to Camera.
3. **System:** Camera receives `PreparedPoseReference`. **System:** Final persistence/overlay behavior remains a separate unresolved contract.

### Alternative flows

- **A1 — Replace selection.** Source step: 2. Condition: another pose is prepared. Behavior: replace the in-memory prepared reference. Ends with: latest verified selection.
- **A2 — Sign in.** Source step: 1. Condition: a visitor chooses an account action. Behavior: request sign-in. Ends with: action remains unconfirmed until auth exists.

### Exception flows

- **E1 — Render unavailable.** Source step: 2. Failure: download or image verification fails. Handling: remain on detail and offer retry. Prohibited: opening Camera with an invalid guide.
- **E2 — Saved/account state unavailable.** Source step: 1. Failure: no implementation can confirm account state. Handling: label Save/Unsave as unresolved. Prohibited: claiming a persisted Saved result.

### Postconditions

- **Success:** A verified prepared reference is held for handoff.
- **Failure:** No incorrect active reference or Saved state is claimed.

### Current evidence

- **Observed:** Mobile has `PoseReferenceKey.Personal|Community`, community
  detail/download, verified image preparation, `PreparedPoseReference`, and
  navigation handoff state.
- **Partial:** Camera state contains overlay fields and UI paths, but the
  dependent plan states that final overlay/relaunch persistence is not complete.
- **Unresolved:** No Account, SavedEntry, authentication/session, save/unsave,
  or lifecycle-removal API/model was found. No HTTP API is owned by this feature.
- **Delivery evidence:** [REP-003](../reports/REP-003-pose-reference-library-convergence-delivery.md)
  explicitly records typed Try Pose preparation without claiming Camera overlay.

### Traceability

| Concern | Canonical reference | Evidence |
| --- | --- | --- |
| Entities/contracts | [`PoseReferenceKey`](../../data/entities/pose-reference-key.md), [`PreparedPoseReference`](../../data/entities/prepared-pose-reference.md), [Account/SavedEntry TBD](../../data/domain-model.md) | [`PoseReferenceKey.kt`](../../../mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseReferenceKey.kt), [`PreparedPoseReference.kt`](../../../mobile/shared/src/commonMain/kotlin/com/aipose/data/PreparedPoseReference.kt) |
| ERD | [Conceptual overlay](../../data/erd/conceptual.md) | No account/saved schema found |
| APIs | [Community detail](../../api/modules/community.md); no Save/Try API discovered | [`PoseApiService.kt`](../../../mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt#L140), [conventions](../../api/conventions.md) |
| Supporting mobile flow | Detail, download/verify, navigation, camera state | [`PoseDetailScreen.kt`](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PoseDetailScreen.kt), [`Navigation.kt`](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt), [`CameraState.kt`](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraState.kt) |

## Requirements

- **FR-001:** Try Pose preparation verifies the selected render before handoff.
- **FR-002:** Account/Saved and relaunch/overlay persistence remain explicitly TBD.
- **BR-001:** Use never grants ownership or publication rights.

## Acceptance

- [ ] Community detail can prepare and verify image bytes before Camera handoff.
- [ ] Failed preparation stays out of Camera and offers recovery.
- [ ] No Save/Unsave success is claimed without an implemented account contract.

## Relationships

- Shared references: [PoseReferenceKey](../../data/entities/pose-reference-key.md), [ERD conceptual](../../data/erd/conceptual.md), [Community API](../../api/modules/community.md).
- Related features: [FEAT-003](FEAT-003-browse-and-search-published-poses.md), [FEAT-006](FEAT-006-publish-a-pose.md).
### Supporting evidence

- [`PoseDetailScreen.kt`](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PoseDetailScreen.kt)
- [`PreparedPoseReference.kt`](../../../mobile/shared/src/commonMain/kotlin/com/aipose/data/PreparedPoseReference.kt)
- [`PoseServiceLocator.kt`](../../../mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseServiceLocator.kt)
- [`Navigation.kt`](../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt)
- [`REP-003`](../reports/REP-003-pose-reference-library-convergence-delivery.md)
