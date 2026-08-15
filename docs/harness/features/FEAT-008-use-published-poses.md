---
schema_version: 1
type: feature
id: FEAT-008
title: Use Published Poses
status: draft
created: 2026-08-15
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
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-006-publish-a-pose|FEAT-006]]"
  source_paths: []
---

# FEAT-008: Use Published Poses

## Introduction

**Purpose:** Let a signed-in user save, unsave, and try a published pose.

**In scope:** Account-linked Saved collection, Save and Unsave actions for published poses, login continuation for those actions, Try Pose from a published pose detail or Saved collection, camera overlay behavior, and lifecycle outcomes when a published pose is unpublished, deleted, or removed.

**Out of scope:** Browsing and title search in FEAT-003, extracting a pose in FEAT-004, managing a pose guide in FEAT-005, publishing or unpublishing in FEAT-006, Admin Web operations in FEAT-007, and using a private pose that has not been published.

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Visitor | User | Understand that an account is needed for use actions | View the public detail and receive a sign-in path when choosing Save or Try Pose |
| Signed-in user | User | Keep and use a published pose | Save, unsave, open Saved, and try a published pose in Camera |

### User needs

- A signed-in user needs to save a published pose to an account-linked Saved collection and remove it later with Unsave.
- A visitor needs a clear sign-in path when attempting a Save or Try Pose action.
- A signed-in user needs to try a published pose without gaining ownership or publication rights.
- The user needs the selected transparent pose image to appear as a camera guide and remain available across relaunch until replaced or cleared.
- The user needs clear recovery when the selected pose cannot be prepared or when the owner changes its public lifecycle.

### Preconditions

- The user has opened a published pose through FEAT-003 or has an existing Saved entry.
- Save and Unsave require a signed-in account.
- Try Pose requires a signed-in user and a published pose with a usable pose image.
- A Save or Try action never grants ownership or edit, delete, publish, or unpublish rights.

### Trigger

The user chooses Save, Unsave, Saved, or Try Pose for a published pose.

### Main flow

1. **Actor:** The user opens a published pose detail through FEAT-003. **System:** The system presents Save and Try Pose actions according to the user's sign-in state.
2. **Actor:** A signed-in user chooses Save. **System:** The system adds the published pose once to the user's Saved collection and shows the saved state.
3. **Actor:** The signed-in user opens Saved or chooses Unsave. **System:** The system presents the user's saved published poses or removes the selected pose from Saved and shows the unsaved state.
4. **Actor:** The signed-in user chooses Try Pose. **System:** The system prepares the published pose image and opens Camera only after the pose is ready to display.
5. **System:** Camera displays the selected pose as a semi-transparent guide at the default opacity and lets the user toggle or clear it. The active reference remains selected across relaunch until replaced or cleared.

### Alternative flows

- **A1 — Sign in before action.** Source step: 1. Condition: a visitor chooses Save, Unsave, or Try Pose. Behavior: the system asks the visitor to sign in and resumes the requested action only after successful sign-in. Ends with: no action is claimed before authentication.
- **A2 — Replace the active pose.** Source step: 4–5. Condition: another published pose is tried. Behavior: the new pose replaces the active reference after successful preparation. Ends with: only the newly selected pose is active.
- **A3 — Unpublish a saved pose.** Source step: 3. Condition: the owner unpublishes the pose under FEAT-006. Behavior: the pose leaves public discovery and the existing Saved entry is removed. Ends with: no public or Saved entry remains.
- **A4 — Delete a saved pose.** Source step: 3. Condition: the owner deletes the pose guide under FEAT-005. Behavior: the system removes it from Saved and informs the signed-in user when the entry is next viewed. Ends with: the deleted pose is not usable from Saved.
- **A5 — Clear active reference.** Source step: 5. Condition: the user clears the overlay. Behavior: the system removes the active reference; the source pose and Saved entry remain unchanged. Ends with: Camera has no active pose guide.

### Exception flows

- **E1 — Sign-in fails or is abandoned.** Source step: A1. Failure: authentication does not complete. Handling: return the visitor to the published detail without claiming Save, Unsave, or Try Pose success.
- **E2 — Save or Unsave fails.** Source step: 2–3. Failure: the account-linked state is not confirmed. Handling: preserve the last confirmed saved state and offer retry. Prohibited: showing a false saved or unsaved result.
- **E3 — Pose image cannot be prepared.** Source step: 4. Failure: the published pose image is unavailable or unusable. Handling: keep the user on detail or Saved, explain the failure, and offer a recoverable retry. Prohibited: opening Camera with a missing or wrong guide.
- **E4 — Active reference is missing or corrupt after relaunch.** Source step: 5. Failure: the selected guide cannot be restored. Handling: clear the invalid active reference, keep Camera usable, and offer re-selection. Prohibited: showing another pose as the selected guide.
- **E5 — Published pose is deleted.** Source step: 1–4. Failure: the owner deletes the pose guide under FEAT-005. Handling: stop presenting the pose as usable, remove its Saved entry, and explain the outcome. Prohibited: claiming continued public availability.

### Postconditions

- **Success:** The signed-in user has an accurate Saved state or Camera shows the selected published pose as the active guide; no ownership or publication rights change.
- **Failure:** The last confirmed Saved state and active reference remain truthful, and the user has a retry or re-selection path.

## Requirements

- **FR-001:** A signed-in user shall be able to Save a published pose to an account-linked Saved collection exactly once.
- **FR-002:** A signed-in user shall be able to Unsave a saved published pose and see the confirmed unsaved state.
- **FR-003:** A visitor who chooses Save, Unsave, or Try Pose shall receive a sign-in path, and no action shall be claimed before sign-in succeeds.
- **FR-004:** The Saved collection shall show the signed-in user's saved published poses and shall not transfer ownership or management rights.
- **FR-005:** A signed-in user shall be able to Try Pose for a published pose from its detail or Saved entry.
- **FR-006:** Try Pose shall open Camera only after the selected published pose image is ready to display.
- **FR-007:** Camera shall display the selected published pose as a semi-transparent guide at the default opacity and shall allow the user to toggle visibility or clear the active reference.
- **FR-008:** The selected active reference shall survive relaunch until replaced or cleared; clearing it shall not delete or mutate the source pose or Saved entry.
- **FR-009:** A failed Save, Unsave, or Try Pose action shall preserve the last confirmed state and provide a recoverable outcome.
- **FR-010:** When the owner deletes a pose guide under FEAT-005, FEAT-008 shall remove that pose from Saved and shall not allow it to remain usable from Saved.
- **FR-011:** When the owner unpublishes a pose under FEAT-006, FEAT-008 shall remove it from public discovery and remove its existing Saved entry.
- **BR-001:** Saving or trying a pose never grants ownership, editing, deletion, publication, or unpublication rights.
- **BR-002:** The system must not open Camera with a missing, stale, or wrong pose image.
- **NFR-001:** Save, Unsave, Try Pose, and lifecycle changes shall present clear confirmed or failed outcomes.

## Acceptance

- [ ] A signed-in user can Save a published pose once and sees it in Saved.
- [ ] A signed-in user can Unsave a saved pose and sees the confirmed unsaved state.
- [ ] A visitor is asked to sign in before Save, Unsave, or Try Pose succeeds.
- [ ] Saved entries do not grant ownership or management rights.
- [ ] Try Pose from a published detail or Saved entry opens Camera only after the pose image is ready.
- [ ] Camera displays the selected pose at the default semi-transparent opacity and supports toggle and clear.
- [ ] The active reference is restored after relaunch until replaced or cleared, without requiring the original public URL.
- [ ] A failed preparation keeps the user out of Camera and offers recovery.
- [ ] Deleting a pose guide removes the pose from Saved and prevents further use from that entry.
- [ ] Unpublishing removes the pose from public discovery and removes its existing Saved entry.

**Scenario: save and unsave a published pose**  
Given a signed-in user is viewing a published pose  
When the user chooses Save and later Unsave  
Then the pose appears once in Saved and later shows the confirmed unsaved state.

**Scenario: try a published pose**  
Given a signed-in user is viewing a published pose with a usable pose image  
When the user chooses Try Pose  
Then Camera opens with that pose as the active semi-transparent guide.

**Scenario: recover from a deleted pose**  
Given a saved pose has been deleted by its owner  
When the user opens Saved  
Then the pose is no longer usable from Saved and the user receives a clear availability outcome.

## Relationships

- Specs: [[technical-architecture]], [[product-feature-inventory]], [[ui-ux-system]]
- Features: [[FEAT-003-browse-and-search-published-poses|FEAT-003]], [[FEAT-006-publish-a-pose|FEAT-006]]
