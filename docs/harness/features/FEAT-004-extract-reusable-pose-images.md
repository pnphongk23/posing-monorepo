---
schema_version: 1
type: feature
id: FEAT-004
title: Extract Reusable Pose Images
status: draft
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
    - "[[FEAT-007-operate-pose-content-from-admin-web|FEAT-007]]"
  source_paths: []
---

# FEAT-004: Extract Reusable Pose Images

## Introduction

**Purpose:** Let an authorized pose creator turn one readable source image into one reusable pose image.

**In scope:** Source-image validation, one extraction request, the extraction outcome, the common pose-image quality contract, the common request status, retryable failure, and ownership assignment to the actor who created the pose.

**Out of scope:** Pose-guide metadata and owner-guide management in FEAT-005, public publication in FEAT-006, the Admin Web control surface in FEAT-007, saving or trying a published pose in FEAT-008, and implementation or provider choices.

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Signed-in user | User | Create a reusable pose from a source image | Submit one eligible source image and receive the resulting pose as its owner |
| Admin operator | Business role | Create an Admin-owned pose from a source image | Submit one eligible source image and receive the resulting pose as its owner |

### User needs

- A signed-in user and an Admin operator need the same extraction outcome from the same kind of source image.
- The creator needs to know whether the request is queued, processing, succeeded, or failed.
- The creator needs a usable pose result that contains one complete human pose on a transparent background without eyes, nose, or mouth.
- A creator needs retryable failures to preserve ownership and avoid duplicate pose results.
- The creator needs the successful result to be associated with the creator as Pose Owner.

### Preconditions

- The requester is authenticated and authorized to create a pose.
- Exactly one readable source image is supplied and it satisfies the accepted image constraints.
- The requester has an available pose-creation context: a personal context for a signed-in user or an Admin context for an Admin operator.

### Trigger

The signed-in user or Admin operator submits one source image for pose extraction.

### Main flow

1. **Actor:** The requester submits one source image. **System:** The system validates the submission and acknowledges one extraction request.
2. **System:** The system reports the request as queued or processing while the pose is being generated.
3. **System:** The system completes the extraction and evaluates one reusable pose result against the common pose-image contract.
4. **System:** When the result is valid, the system reports success and assigns the resulting pose to the requester as Pose Owner. FEAT-005 governs the guide and owner storage around that result.

### Alternative flows

- **A1 — Retry a failed request.** Source step: 2–3. Condition: the failure is retryable. Behavior: the requester retries the same creation intent; the system preserves one owner and does not create competing pose results. Ends with: a new truthful request outcome.

### Exception flows

- **E1 — Invalid source image.** Source step: 1. Failure: the image is unreadable or outside the accepted constraints. Handling: reject the request with a correction message. Prohibited: starting extraction or claiming ownership of a successful result.
- **E2 — No usable pose.** Source step: 3. Failure: the result does not contain one complete pose matching the common visual contract. Handling: report a corrective or retryable failure. Prohibited: reporting a successful pose.
- **E3 — Extraction failure.** Source step: 2–3. Failure: the service cannot complete the request. Handling: expose a truthful failed outcome and preserve a retry path when permitted. Prohibited: creating a duplicate or claiming success.

### Postconditions

- **Success:** Exactly one valid pose result exists for the request, and the actor who created it is its Pose Owner.
- **Failure:** No invalid or unconfirmed result is reported as a successful pose, and a permitted retry remains understandable.

## Requirements

- **FR-001:** The system shall allow an authenticated signed-in user or Admin operator to submit exactly one eligible source image for extraction.
- **FR-002:** The system shall distinguish queued, processing, succeeded, and failed outcomes for an extraction request.
- **FR-003:** A successful extraction shall produce exactly one reusable pose image showing one complete human pose on a transparent background without eyes, nose, or mouth.
- **FR-004:** A successful extraction shall assign the resulting pose to the actor who created it: a signed-in user owns that user's extracted pose, and an Admin operator owns that Admin-created pose.
- **FR-005:** A failed, invalid, or incomplete extraction shall not be reported as a successful pose and shall not create a competing result.
- **FR-006:** A permitted retry shall preserve the creation context and shall not transfer ownership or create duplicate pose results.
- **BR-001:** The extraction behavior and success contract are the same for signed-in users and Admin operators; the caller's surface does not create a second extraction model.
- **NFR-001:** User-visible extraction outcomes shall clearly distinguish an accepted request, successful result, and failure.

## Acceptance

- [ ] A signed-in user can submit one eligible image and receives queued, processing, succeeded, or failed outcomes.
- [ ] An Admin operator can submit one eligible image and receives the same extraction outcome and pose-image contract.
- [ ] A successful result contains one complete human pose on a transparent background without eyes, nose, or mouth.
- [ ] The signed-in user who created a pose is recorded as its Pose Owner.
- [ ] The Admin operator who created a pose is recorded as its Pose Owner.
- [ ] Invalid input, no-pose results, and service failures never appear as successful poses.
- [ ] A permitted retry does not create duplicate pose results or change the original owner.

**Scenario: signed-in user extracts a pose**  
Given a signed-in user supplies one valid source image  
When extraction succeeds  
Then one valid reusable pose is produced and the user owns it.

**Scenario: Admin extracts a pose**  
Given an Admin operator supplies one valid source image  
When extraction succeeds  
Then one valid reusable pose is produced and the Admin operator owns it.

**Scenario: extraction fails**  
Given a request cannot produce a valid pose  
When extraction finishes  
Then the system reports failure, creates no successful pose, and offers a permitted recovery path.

## Relationships

- Specs: [[technical-architecture]], [[product-feature-inventory]], [[ui-ux-system]]
- Features: [[FEAT-005-manage-a-pose-guide|FEAT-005]], [[FEAT-007-operate-pose-content-from-admin-web|FEAT-007]]
