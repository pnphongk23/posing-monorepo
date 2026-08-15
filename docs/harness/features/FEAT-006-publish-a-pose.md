---
schema_version: 1
type: feature
id: FEAT-006
title: Publish a Pose
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
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
    - "[[FEAT-007-operate-pose-content-from-admin-web|FEAT-007]]"
    - "[[FEAT-008-use-published-poses|FEAT-008]]"
  source_paths: []
---

# FEAT-006: Publish a Pose

## Introduction

**Purpose:** Let the Pose Owner make one ready pose guide publicly discoverable and later remove it from public discovery.

**In scope:** Publication eligibility, owner authorization, the public-data warning and acknowledgement, publish and unpublish outcomes, public visibility, and the relationship between publication lifecycle and published-pose use.

**Out of scope:** Browsing or searching the public catalogue in FEAT-003, Save/Unsave and Try Pose in FEAT-008, extraction in FEAT-004, pose-guide management in FEAT-005, and the Admin Web control surface in FEAT-007.

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Pose Owner | Business role | Decide whether an owned pose is public | Request publication or unpublication and acknowledge the public-data warning |
| Signed-in user | User | Publish a pose created by that user | Act as Pose Owner for the user's extracted pose |
| Admin operator | Business role | Publish an Admin-created pose | Act as Pose Owner for the Admin-extracted pose through the Admin Web surface |

### User needs

- A Pose Owner needs to publish only a complete, ready pose guide that the owner is allowed to manage.
- The owner needs to understand that the source image and generated pose may become public before confirming publication.
- The owner needs a clear outcome that distinguishes a successful publication from a failed or pending request.
- The owner needs to unpublish an owned pose without transferring ownership.
- Users who saved a pose need publication lifecycle outcomes to remain consistent with FEAT-008: unpublishing removes discovery and the Saved entry.

### Preconditions

- The requester is the Pose Owner.
- The pose guide is complete and ready for publication.
- The owner has reviewed and explicitly acknowledged the public-data warning and disclaimer.
- A pose may be published only once its required public content is confirmed available.

### Trigger

The Pose Owner chooses Publish or Unpublish for an owned pose guide.

### Main flow

1. **Actor:** The Pose Owner chooses Publish. **System:** The system verifies ownership, guide readiness, and publication eligibility, then presents the public-data warning and disclaimer.
2. **Actor:** The Pose Owner acknowledges the warning. **System:** The system confirms publication and makes the pose discoverable through FEAT-003.
3. **Actor:** The Pose Owner chooses Unpublish. **System:** The system confirms unpublication and removes the pose from public discovery without transferring ownership.

### Alternative flows

- **A1 — Decline publication.** Source step: 1. Condition: the owner does not acknowledge the warning. Behavior: the system keeps the pose unpublished and does not claim public availability. Ends with: the owner retains the guide privately.
- **A2 — Unpublish an already saved pose.** Source step: 3. Condition: the pose has been saved by another user. Behavior: the pose leaves public discovery and its existing Saved entry is removed under FEAT-008. Ends with: no public or Saved entry remains.
- **A3 — Publish an Admin-owned pose.** Source step: 1. Condition: the Pose Owner is the Admin operator who created the pose. Behavior: the Admin Web surface invokes this same publication behavior. Ends with: the Admin-owned pose follows the same public lifecycle.

### Exception flows

- **E1 — Not the owner.** Source step: 1 or 3. Failure: the requester does not own the pose. Handling: reject the action and do not change visibility. Prohibited: publishing or unpublishing another owner's pose.
- **E2 — Guide not ready.** Source step: 1. Failure: required guide content is incomplete or unavailable. Handling: explain that publication cannot proceed and keep the pose unpublished. Prohibited: presenting an incomplete guide as public.
- **E3 — Warning not acknowledged.** Source step: 1. Failure: the owner declines or abandons the warning. Handling: keep the pose unpublished. Prohibited: treating intent as publication.
- **E4 — Publication fails.** Source step: 2. Failure: the public visibility change is not confirmed. Handling: report failure, preserve the last confirmed visibility, and offer a permitted retry. Prohibited: showing the pose as published without confirmation.
- **E5 — Unpublish fails.** Source step: 3. Failure: the visibility change is not confirmed. Handling: report failure and preserve the last confirmed public state. Prohibited: claiming the pose was removed from discovery.

### Postconditions

- **Success:** A confirmed publish makes the pose discoverable through FEAT-003, or a confirmed unpublish removes it from discovery; ownership remains unchanged.
- **Failure:** The last confirmed visibility remains authoritative and no unconfirmed public state is reported.

## Requirements

- **FR-001:** The system shall allow only the Pose Owner to request publication or unpublication of a pose guide.
- **FR-002:** The system shall require a complete, ready guide and confirmed public content before publication.
- **FR-003:** Before publication, the system shall show a warning and disclaimer that the guide's shared data may be public.
- **FR-004:** The system shall make a pose publicly discoverable only after the owner explicitly acknowledges the warning and publication succeeds.
- **FR-005:** The system shall keep an unpublished pose out of FEAT-003's public catalogue.
- **FR-006:** The system shall let the Pose Owner unpublish an owned pose and shall remove it from public discovery after the change is confirmed.
- **FR-007:** Publishing or unpublishing shall not transfer ownership or grant another user management rights.
- **FR-008:** An Admin operator who owns an Admin-created pose shall use this same publication behavior through FEAT-007; FEAT-007 shall not define a second publication policy.
- **BR-001:** User intent, warning acknowledgement, and confirmed public visibility are distinct outcomes.
- **BR-002:** A failed publication or unpublication shall not change the reported visibility state.
- **BR-003:** An unpublished pose must not remain discoverable as published.
- **NFR-001:** Publication outcomes shall be understandable enough for an owner to distinguish private, public, and failed states.

## Acceptance

- [ ] A Pose Owner can request publication only for a complete, ready guide.
- [ ] The owner sees the public-data warning and disclaimer before publication.
- [ ] Declining or abandoning the warning leaves the pose unpublished.
- [ ] Explicit acknowledgement followed by confirmed success makes the pose discoverable in FEAT-003.
- [ ] A non-owner cannot publish or unpublish the pose.
- [ ] An Admin operator can publish an Admin-owned pose through the same behavior as any other Pose Owner.
- [ ] Unpublishing removes the pose from public discovery without changing ownership.
- [ ] Unpublishing removes the pose's existing Saved entry under FEAT-008.
- [ ] Failed visibility changes preserve the last confirmed visibility and do not claim success.

**Scenario: publish a user-owned pose**  
Given a signed-in user owns a ready private pose guide  
When the user acknowledges the public-data warning and publication succeeds  
Then the pose is discoverable as published and remains owned by that user.

**Scenario: publish an Admin-owned pose**  
Given an Admin operator owns a ready pose guide  
When the Admin operator publishes it through Admin Web  
Then the same publication rule makes it discoverable without creating a separate Admin publication model.

**Scenario: unpublish a pose**  
Given an owned pose is published  
When the owner confirms unpublication  
Then the pose is removed from public discovery and ownership is unchanged.

## Relationships

- Specs: [[technical-architecture]], [[product-feature-inventory]], [[ui-ux-system]]
- Features: [[FEAT-005-manage-a-pose-guide|FEAT-005]], [[FEAT-007-operate-pose-content-from-admin-web|FEAT-007]], [[FEAT-008-use-published-poses|FEAT-008]]
