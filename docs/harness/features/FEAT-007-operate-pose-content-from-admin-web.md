---
schema_version: 1
type: feature
id: FEAT-007
title: Operate Pose Content from Admin Web
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
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
    - "[[FEAT-006-publish-a-pose|FEAT-006]]"
  source_paths: []
---

# FEAT-007: Operate Pose Content from Admin Web

## Introduction

**Purpose:** Let an authorized Admin operator manage pose-content intake and operational status from one Admin Web surface while using the canonical extraction and publication behavior.

**In scope:** Admin access, provider-key administration, pose-content submission and metadata, truthful extraction status, Admin ownership of Admin-created poses, confirmed content visibility, and the Admin Web actions that invoke FEAT-004, FEAT-005, and FEAT-006.

**Out of scope:** A second extraction contract, a second publication policy, public browsing in FEAT-003, Save/Unsave or Try Pose in FEAT-008, and implementation design or delivery status.

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Admin operator | Business role | Operate pose content safely | Manage provider access, submit or inspect pose content, and act as owner for poses the Admin creates |

### User needs

- An Admin operator needs separate, understandable entry points for provider access and pose-content operations.
- The operator needs safe provider-key information without exposing provider secrets.
- The operator needs to submit one pose source with the required content metadata and receive a truthful request status.
- The operator needs to know that an Admin-created pose is Admin-owned and can be published only through FEAT-006.
- The operator needs to revisit work later without losing confirmed metadata or mistaking acceptance for extraction success or public visibility.

### Preconditions

- The Admin operator is authenticated and authorized for the requested Admin action.
- Provider-key operations use valid key data; secrets are never presented as readable browser content.
- A pose submission contains one eligible source image and the required pose-content metadata.
- Extraction and publication follow FEAT-004 and FEAT-006 respectively.

### Trigger

The Admin operator opens Admin Web, manages provider access, submits pose content, refreshes an operation, or requests publication or unpublication for an Admin-owned pose.

### Main flow

1. **Actor:** The Admin operator opens Admin Web. **System:** The system presents the provider-access and pose-content areas.
2. **Actor:** The Admin operator manages provider access. **System:** The system validates the action, confirms the result, and presents safe key metadata without revealing secrets.
3. **Actor:** The Admin operator submits one source image and the required pose-content metadata. **System:** The system validates the submission and accepts one trackable extraction request.
4. **System:** The system presents the canonical FEAT-004 status and result. On success, the Admin operator is recorded as Pose Owner for the Admin-created pose.
5. **Actor:** The Admin operator revisits the content area or requests publication. **System:** The system presents the latest confirmed state and invokes FEAT-006 for the same publish or unpublish behavior.

### Alternative flows

- **A1 — Leave and return.** Source step: 3–5. Condition: the operator leaves while work is pending. Behavior: returning shows the latest confirmed request and preserves submitted metadata without creating a duplicate. Ends with: one unambiguous operation state.
- **A2 — Retry an eligible failure.** Source step: 3–4. Condition: FEAT-004 reports a retryable failure. Behavior: the operator retries under the same extraction rules and ownership context. Ends with: a truthful new request outcome.
- **A3 — Publish after extraction succeeds.** Source step: 4. Condition: the Admin-owned guide is complete and ready. Behavior: the Admin operator invokes FEAT-006 and follows its warning, acknowledgement, and visibility rules. Ends with: the same publication lifecycle as every other Pose Owner.

### Exception flows

- **E1 — Unauthorized Admin action.** Source step: 1–5. Failure: authorization is missing or invalid. Handling: reject the action, preserve the last confirmed state, and do not reveal protected data. Prohibited: claiming a successful Admin operation.
- **E2 — Invalid submission.** Source step: 3. Failure: the source image or required metadata is invalid. Handling: identify the correction and do not create a usable pose. Prohibited: queueing or publishing an invalid submission.
- **E3 — Extraction failure.** Source step: 4. Failure: FEAT-004 reports failed or unusable extraction. Handling: show the failed outcome and a permitted retry; keep the pose non-ready and non-public. Prohibited: reporting a usable or public pose.
- **E4 — Publication failure.** Source step: 5. Failure: FEAT-006 cannot confirm the visibility change. Handling: show the last confirmed visibility and the publication recovery outcome defined by FEAT-006. Prohibited: inventing an Admin-only publication result.
- **E5 — Secret exposure risk.** Source step: 2. Failure: a provider secret would be included in a visible result. Handling: show only safe key metadata and reject the unsafe response. Prohibited: presenting or echoing the secret.

### Postconditions

- **Success:** The operator sees a confirmed provider-access result, one canonical extraction outcome, or one FEAT-006 publication outcome; Admin-created poses remain Admin-owned.
- **Failure:** No invalid, failed, unready, or unconfirmed pose is reported as successful or public, and the last confirmed state remains recoverable.

## Requirements

- **FR-001:** Admin Web shall present separate entry points for provider-key administration and pose-content operations to an authorized Admin operator.
- **FR-002:** Provider-key operations shall show only safe key metadata and shall not expose provider secrets.
- **FR-003:** A valid provider-key create, status, delete, or reset action shall present a confirmed outcome; an invalid action shall present a recoverable failure without claiming success.
- **FR-004:** The Admin operator shall be able to submit one eligible source image with the required pose-content metadata as one trackable extraction request.
- **FR-005:** Admin Web shall present the queued, processing, succeeded, or failed outcome defined by FEAT-004 and shall not replace it with an Admin-specific status model.
- **FR-006:** When extraction succeeds, the Admin operator who submitted the pose shall be recorded as Pose Owner under FEAT-004's ownership rule.
- **FR-007:** Admin Web shall allow the operator to revisit a pending or completed operation and see the latest confirmed state without creating a duplicate request or losing confirmed metadata.
- **FR-008:** Admin Web shall invoke FEAT-006 for an Admin-owned pose's publication or unpublication and shall not define a separate publication policy.
- **FR-009:** A pose shall not be presented as publicly discoverable until FEAT-006 confirms publication.
- **FR-010:** Invalid, unauthorized, failed, or unconfirmed operations shall preserve the last confirmed state and shall not be presented as successful.
- **BR-001:** Admin Web is a control surface and operating context; it does not create a second extraction, ownership, or publication model.
- **BR-002:** Admin ownership applies to the pose an Admin operator creates, while Admin operation of another owner's pose does not silently transfer ownership.
- **NFR-001:** Admin outcomes shall distinguish accepted, processing, succeeded, failed, ready, and public states in language an operator can act on.

## Acceptance

- [ ] An authorized Admin operator can open provider-key and pose-content areas separately.
- [ ] Key operations show safe metadata and never show provider secrets.
- [ ] The operator can submit one valid pose source and required metadata and receives one trackable extraction request.
- [ ] Admin Web shows the same queued, processing, succeeded, and failed extraction outcomes defined by FEAT-004.
- [ ] A successful Admin extraction records the submitting Admin operator as Pose Owner.
- [ ] Invalid input, unauthorized actions, and extraction failures do not appear as usable or public poses.
- [ ] Returning to Admin Web shows the latest confirmed state without duplicate requests or lost metadata.
- [ ] Publishing or unpublishing an Admin-owned pose invokes the FEAT-006 behavior, including its owner check and warning/acknowledgement rules.
- [ ] Admin Web never presents a pose as publicly discoverable before FEAT-006 confirms publication.

**Scenario: Admin creates a pose**  
Given an authorized Admin operator submits one valid source image and metadata  
When canonical extraction succeeds  
Then the operator sees the successful result and is recorded as Pose Owner.

**Scenario: Admin publishes a pose**  
Given the Admin operator owns a complete ready pose  
When the operator requests publication through Admin Web  
Then FEAT-006's publication behavior is used and no Admin-specific publication rule is created.

**Scenario: Admin revisits pending work**  
Given an extraction request is still pending  
When the Admin operator leaves and returns to Admin Web  
Then the latest confirmed status and submitted metadata are shown without a duplicate request.

## Relationships

- Specs: [[technical-architecture]], [[product-feature-inventory]], [[ui-ux-system]]
- Features: [[FEAT-004-extract-reusable-pose-images|FEAT-004]], [[FEAT-005-manage-a-pose-guide|FEAT-005]], [[FEAT-006-publish-a-pose|FEAT-006]]
