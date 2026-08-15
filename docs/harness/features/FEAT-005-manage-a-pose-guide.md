---
schema_version: 1
title: Manage a Pose Guide
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
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-006-publish-a-pose|FEAT-006]]"
  source_paths: []
type: feature
id: FEAT-005
status: draft
created: 2026-08-09
---

# FEAT-005: Manage a Pose Guide

## Introduction

**Purpose:** Let the Pose Owner turn one successful extraction into a personal pose guide and manage that guide over time.

**In scope:** The owner's My Poses collection, attaching a source image and a successful pose result to one guide, name/description/ordered notes, viewing and searching owned guides, editing metadata, re-extraction through FEAT-004, retry, revert, and terminal deletion.

**Out of scope:** The extraction contract in FEAT-004, browsing published poses in FEAT-003, saving or trying a published pose in FEAT-008, and publishing or unpublishing in FEAT-006. Public publication is a separate owner action governed only by FEAT-006.

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Signed-in user | User | Keep and manage the user's own pose guides | Create a guide from the user's successful extraction, view it in My Poses, and manage it as owner |
| Admin operator | Business role | Keep and manage an Admin-created pose guide | Create or operate the Admin-owned guide resulting from an Admin extraction |
| Pose Guide Owner | Business role | Keep one useful pose guide accurate | Edit metadata, request regeneration, revert, delete, and request publication through FEAT-006 |

### User needs

- The creator needs to associate one successful extraction with a source image, a name, a description, and ordered notes.
- The creator needs to find owned guides in My Poses and search them by title.
- The Pose Guide Owner needs to edit guide metadata without losing the source or current pose.
- The Pose Guide Owner needs to request a new extraction from the retained source while the current pose remains available until replacement succeeds.
- The Pose Guide Owner needs to retry a failed generation, revert a successful replacement, and delete a guide permanently.
- The Pose Guide Owner needs clear ownership boundaries: the actor who created the pose owns it, including an Admin operator for an Admin-created pose.

### Preconditions

- A successful pose result exists under FEAT-004.
- The requester is authenticated and is the Pose Guide Owner for management actions.
- A guide name is present; the description and ordered notes may be empty.
- For re-extraction, the guide retains a readable source image.

### Trigger

The Pose Owner creates or opens a personal pose guide, searches My Poses, edits its metadata, requests re-extraction, reverts a replacement, or confirms deletion.

### Main flow

1. **Actor:** The creator selects one successful pose result and supplies a name, description, and ordered notes. **System:** The system creates one owned guide and associates the source image, result, metadata, and creator ownership.
2. **Actor:** The Pose Guide Owner opens My Poses or searches by title. **System:** The system presents the owner's guides and the selected guide's source image, current pose, metadata, and notes.
3. **Actor:** The Pose Guide Owner saves a metadata edit. **System:** The system presents the new name, description, and ordered notes while preserving the source image and current pose.
4. **Actor:** The Pose Guide Owner requests re-extraction. **System:** The system invokes FEAT-004, reports the request status, and keeps the current pose until a new valid result is complete.
5. **Actor:** The Pose Guide Owner chooses revert after a successful replacement. **System:** The system presents the previous pose as current while retaining the guide metadata and source image.
6. **Actor:** The Pose Guide Owner confirms deletion. **System:** The system makes the guide unavailable and prevents a late extraction result from restoring it.

### Alternative flows

- **A1 — Retry initial creation.** Source step: 1. Condition: the extraction result is retryable. Behavior: the system retains the submitted guide metadata and allows one retry without creating a second guide. Ends with: one guide creation outcome.
- **A2 — Retry re-extraction.** Source step: 4. Condition: re-extraction fails in a retryable way. Behavior: the system preserves the current pose and accepts a retry through FEAT-004. Ends with: the same current pose until replacement succeeds.
- **A3 — Cancel metadata edit.** Source step: 3. Condition: the owner leaves without saving. Behavior: the system keeps the previously saved metadata. Ends with: unchanged guide.
- **A4 — Request publication.** Source step: 2 or 3. Condition: the owner wants the guide public. Behavior: the system transfers the owner to the publication behavior in FEAT-006; this Feature does not define publication.

### Exception flows

- **E1 — Not the owner.** Source step: 2–6. Failure: the requester lacks ownership. Handling: reject edit, regeneration, revert, and deletion; do not reveal protected personal content. Prohibited: changing the guide or transferring ownership.
- **E2 — Invalid guide data.** Source step: 1 or 3. Failure: the name, source, or metadata is invalid. Handling: explain the correction and keep the last confirmed guide state. Prohibited: reporting a malformed guide as ready.
- **E3 — Re-extraction fails.** Source step: 4. Failure: FEAT-004 reports a failed or unusable result. Handling: keep the current pose and report failure or retry. Prohibited: replacing the current pose with an invalid result.
- **E4 — Retention fails.** Source step: 1, 3, or 4. Failure: required guide content cannot be retained. Handling: report failure and keep the last confirmed guide state. Prohibited: claiming a complete guide or replacement.
- **E5 — Deletion fails.** Source step: 6. Failure: the guide remains available. Handling: report failure and do not claim terminal deletion.
- **E6 — Late result after deletion.** Source step: 4 or 6. Failure: an old extraction completes after deletion. Handling: discard the late result and keep the guide unavailable.

### Postconditions

- **Success:** The owner has one owned guide with its source image, current pose, metadata, and ownership intact; or a confirmed edit, replacement, revert, or terminal deletion has been presented.
- **Failure:** The last confirmed guide remains intact, no invalid pose becomes current, and no deleted guide is restored.

## Requirements

- **FR-001:** The system shall let a Pose Guide Owner create one owned guide from one successful FEAT-004 result with a non-empty name, an optional description, and ordered notes.
- **FR-002:** The system shall associate the source image, current pose, name, description, notes, and creator ownership with the same guide.
- **FR-003:** My Poses shall show the owner's guides and support title search without exposing another owner's private guides.
- **FR-004:** The system shall let the Pose Guide Owner edit the name, description, and ordered notes and shall preserve the last confirmed values when an edit fails.
- **FR-005:** The system shall let the Pose Guide Owner request re-extraction through FEAT-004 and shall replace the current pose only after a new valid result is successful.
- **FR-006:** The system shall let the Pose Guide Owner retry a permitted failed creation or re-extraction without creating duplicate guides or competing current poses.
- **FR-007:** The system shall let the Pose Guide Owner revert to the previous pose after a successful replacement.
- **FR-008:** The system shall let the Pose Guide Owner delete a guide and shall report success only when the guide is no longer retrievable through the owner's guide experience.
- **FR-009:** After deletion succeeds, a late or in-flight extraction result shall not restore the guide, its source, its pose, or its metadata.
- **FR-010:** The system shall assign ownership to the actor who created the pose; a signed-in user owns that user's extracted pose and an Admin operator owns that Admin-created pose.
- **BR-001:** Personal guide management must not redefine the extraction, publication, or published-pose-use contracts owned by FEAT-004, FEAT-006, and FEAT-008.
- **BR-002:** A failed edit, re-extraction, revert, or deletion shall not be reported as successful and shall preserve the last confirmed state where applicable.
- **NFR-001:** Ownership and management outcomes shall be clear enough for the requester to understand whether the guide changed, remains unchanged, or was deleted.

## Acceptance

- [ ] A signed-in user can create one owned guide from a successful extraction with a name, description, and ordered notes.
- [ ] An Admin-created extraction can be associated with an Admin-owned guide under the same ownership rule.
- [ ] My Poses shows only the owner's guides and supports title search.
- [ ] The owner can edit metadata and sees the saved values without losing the source image or current pose.
- [ ] A failed metadata edit preserves the previous metadata.
- [ ] A successful re-extraction replaces the current pose while preserving source, metadata, and ownership.
- [ ] A failed re-extraction leaves the previous pose current and offers a permitted retry.
- [ ] The owner can revert a successful replacement to the previous pose.
- [ ] Successful deletion makes the guide unavailable and a late result cannot restore it.
- [ ] A non-owner cannot manage or take ownership of the guide.

**Scenario: create an owned guide**  
Given an authenticated creator has one successful pose result  
When the creator supplies guide metadata  
Then one owned guide is created with the source, pose, and ordered notes associated.

**Scenario: replace and revert a pose**  
Given a Pose Guide Owner has a guide with a current pose  
When re-extraction succeeds and the owner chooses revert  
Then the previous pose is presented as current and the guide metadata is unchanged.

**Scenario: terminal deletion**  
Given a Pose Guide Owner confirms deletion  
When deletion succeeds and a late extraction result arrives  
Then the guide remains unavailable and is not restored.

## Relationships

- Specs: [[technical-architecture]], [[product-feature-inventory]], [[ui-ux-system]]
- Features: [[FEAT-004-extract-reusable-pose-images|FEAT-004]], [[FEAT-006-publish-a-pose|FEAT-006]]
