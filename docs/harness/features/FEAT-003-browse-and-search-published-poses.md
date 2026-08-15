---
schema_version: 1
type: feature
id: FEAT-003
title: Browse and Search Published Poses
status: proposed
created: 2026-08-09
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
    - "[[FEAT-006-publish-a-pose|FEAT-006]]"
    - "[[FEAT-008-use-published-poses|FEAT-008]]"
  source_paths: []
---

# FEAT-003: Browse and Search Published Poses

## Introduction

**Purpose:** Let a visitor or signed-in user browse and search poses that have been published to the public pose catalogue.

**In scope:** The public catalogue, published-only results, pose cards, pose detail, title search, pagination, refresh, empty states, and recoverable catalogue failures.

**Out of scope:** Personal "My Poses" management, saving or unsaving, Saved collection management, Try Pose, camera overlay, pose extraction, editing, deletion, publishing, unpublishing, and unpublished or draft poses.

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Visitor | User | Discover publicly available poses | Browse published poses and open their details without an account |
| Signed-in user | User | Find a pose to inspect or use later | Browse, search, refresh results, and open published pose details |

### User needs

- A visitor needs to see only poses that are publicly available.
- A signed-in user needs to search published poses by title and inspect a result before choosing an action governed by FEAT-008.
- Users need stable result lists while loading more results or recovering from a catalogue failure.
- Users need clear empty states when no published poses or no search matches exist.

### Preconditions

- The Published Pose Catalogue is available to the browsing experience.
- A pose is eligible for this Feature only when its publication state is published.
- Searching does not require the user to sign in.

### Trigger

The user opens the public pose catalogue, refreshes it, requests more results, or enters a title search.

### Main flow

1. **Actor:** The user opens the pose catalogue. **System:** The system presents published pose cards.
2. **Actor:** The user requests more results or refreshes the catalogue. **System:** The system presents the latest published results without duplicate poses.
3. **Actor:** The user enters a title search. **System:** The system presents only published poses matching the search and an explicit empty state when there are no matches.
4. **Actor:** The user opens a pose card. **System:** The system presents the published pose detail and the metadata available for that pose. Actions such as Save or Try Pose remain governed by FEAT-008.

### Alternative flows

- **A1 — More results.** Source step: 2. Condition: additional published results exist. Behavior: the system appends the next results and keeps each pose only once. Ends with: an extended published list.
- **A2 — Search reset.** Source step: 3. Condition: the user clears the title query. Behavior: the system returns to the current published catalogue view. Ends with: the unfiltered published list.
- **A3 — Refresh.** Source step: 2. Condition: the user refreshes. Behavior: the system replaces stale results with the latest confirmed published results. Ends with: refreshed catalogue content.

### Exception flows

- **E1 — Catalogue unavailable.** Source step: 1–3. Failure: the catalogue cannot provide a confirmed result. Handling: the system keeps any already shown results, explains that the catalogue could not be refreshed, and offers retry. Prohibited: showing an unconfirmed pose as published.
- **E2 — Published pose no longer available.** Source step: 4. Failure: the selected pose is no longer published or cannot be retrieved. Handling: the system explains that the pose is unavailable and returns the user to the published catalogue. Prohibited: presenting stale content as currently published.

### Postconditions

- **Success:** The user sees a deduplicated list or title-filtered list of published poses and can inspect a published pose detail.
- **Failure:** No unpublished or unconfirmed pose is presented as public, and the user has a retry or return path.

## Requirements

- **FR-001:** The system shall present only poses whose visibility state is published in the public catalogue.
- **FR-002:** The system shall support browsing additional published results without presenting the same pose more than once in the active list.
- **FR-003:** The system shall support searching published poses by title and shall return only published matches.
- **FR-004:** The pose detail shall present the published pose's available title, images, and metadata without inventing values that are absent.
- **FR-005:** The system shall provide a clear empty state for an empty catalogue and for a search with no matching published pose.
- **FR-006:** Refresh and catalogue failures shall preserve already confirmed results and provide a recoverable retry path.
- **BR-001:** A draft, unpublished, deleted, or otherwise unconfirmed pose must not appear in the public catalogue.
- **BR-002:** Browsing or opening a detail must not grant ownership or management rights; Save and Try Pose behavior is owned by FEAT-008.
- **NFR-001:** Catalogue loading, refresh, and search outcomes shall be understandable without relying on hidden state.

## Acceptance

- [ ] A visitor can open the public catalogue and sees only published poses.
- [ ] Additional results can be loaded without duplicate pose cards.
- [ ] A title search returns only matching published poses and shows an explicit empty state when there are no matches.
- [ ] Opening a card shows the available published metadata and does not fabricate missing values.
- [ ] Refresh replaces the displayed catalogue with confirmed published results while retaining the existing list if refresh fails.
- [ ] A catalogue failure offers retry and never reports an unconfirmed pose as published.

**Scenario: browse published poses**  
Given the catalogue contains published and unpublished poses  
When a visitor opens the pose catalogue  
Then only the published poses are shown.

**Scenario: search published poses**  
Given published poses have different titles  
When a user enters a title query  
Then only published poses matching that query are shown.

**Scenario: inspect a published pose**  
Given a published pose appears in the catalogue  
When the user opens its card  
Then the published detail and its available metadata are shown without granting management rights.

## Relationships

- Specs: [[technical-architecture]], [[product-feature-inventory]], [[ui-ux-system]]
- Features: [[FEAT-005-manage-a-pose-guide|FEAT-005]], [[FEAT-006-publish-a-pose|FEAT-006]], [[FEAT-008-use-published-poses|FEAT-008]]
