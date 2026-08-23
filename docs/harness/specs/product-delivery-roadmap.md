---
schema_version: 1
title: Product Delivery Roadmap
relationships:
  specs:
    - "[[product-feature-inventory]]"
  decisions:
    - "[[DEC-001-extraction-provider-selection-policy|DEC-001]]"
  plans:
    - "[[260809-2241-selected-pose-camera-handoff/plan|260809-2241]]"
    - "[[260809-1806-camera-source-of-truth-convergence/plan|260809-1806]]"
    - "[[260809-2240-pose-reference-library-convergence/plan|260809-2240]]"
    - "[[260816-2240-higgsfield-cli-parallel-extract-provider/plan|260816-2240]]"
  reports:
    - "[[REP-002-feature-gap-and-release-readiness-audit|REP-002]]"
    - "[[REP-003-pose-reference-library-convergence-delivery|REP-003]]"
  rules: []
  features:
    - "[[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]"
    - "[[FEAT-002-manage-a-local-photo-gallery|FEAT-002]]"
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
    - "[[FEAT-006-publish-a-pose|FEAT-006]]"
    - "[[FEAT-007-operate-pose-content-from-admin-web|FEAT-007]]"
    - "[[FEAT-008-use-published-poses|FEAT-008]]"
    - "[[FEAT-009-configure-extraction-provider|FEAT-009]]"
  source_paths: []
type: spec
status: active
---

# Product Delivery Roadmap

## Scope

This is the business roadmap for AI Pose. It sequences the product around one
North Star outcome:

> A new user can choose a pose, see it in Camera, take a photo, and view the
> result.

The roadmap covers the user journey from the first successful photo through
Community discovery, Saved Poses, Albums, personal pose creation, and a
controlled publishing operation.

The roadmap is intentionally business-facing. Individual Features remain the
authority for detailed behavior; Plans determine implementation sequencing and
delivery evidence.

### Product sequence

```text
Choose pose → Use in Camera → Take photo → Keep photo
     ↓
Discover Community poses → Save pose → Organize in Album → Reuse pose
     ↓
Create personal pose → Publish safe, reusable poses
```

### Current baseline

- **Observed:** local photo capture, gallery behavior, Community browsing, pose
  detail, search, and dual extraction providers already have repository evidence.
- **Partial:** Try Pose can prepare a verified pose reference, but the complete
  Camera overlay experience is not yet delivered.
- **Unresolved:** Saved Poses, Accounts, Albums, and the end-to-end personal
  extraction experience are not yet delivered.
- **Risk:** public Community content must be ready and safe before it becomes a
  dependency for the first-use experience.

## Contract

### Roadmap principles

- The first successful photo has priority over breadth of features.
- Each phase must produce a usable customer outcome, not only an internal
  capability.
- A later phase may depend on the previous phase's user outcome, but must not
  make the first-use journey depend on login, AI processing, or Community
  availability unless explicitly stated.
- Guest use is allowed through personal capture. Account access is introduced
  when the user needs cross-session Saved Poses and Albums.
- A pose used for taking a photo does not automatically become owned,
  published, or saved by the user.

### Phase 1 — First Pose Capture MVP

**Objective:** Let a new user take the first photo with a pose quickly.

**In scope:**

- A small set of pose samples available in the app.
- Select one pose and open Camera with that pose visible.
- Show, hide, adjust opacity, and flip the pose guide.
- Take a photo and keep it in the personal gallery.
- View the newly captured photo.

**Result required:** The complete first-use loop works:
`open app → choose pose → open Camera → take photo → view photo`.

**Output for Phase 2:** A stable pose-guided capture experience and evidence that
users can complete the first photo without signing in.

**Explicitly out of scope:** AI extraction, login, Save, Albums, and publishing.

### Phase 2 — Community Pose into Camera

**Objective:** Let users discover a published pose and use it for a photo.

**In scope:**

- Browse published Community poses.
- Search and inspect pose details.
- Choose `Try Pose`.
- Open Camera with the selected Community pose.
- Capture and keep the resulting photo locally.

**Result required:** Every usable published pose can become an input to the
photo-taking journey.

**Output for Phase 3:** A reliable `discover → try → capture` journey and enough
usage evidence to identify which poses users want to keep.

**Explicitly out of scope:** Save/Unsave, Albums, and user publishing.

### Phase 3 — Saved Poses

**Objective:** Let users keep favorite Community poses for later use.

**In scope:**

- Save a published pose.
- Unsave a previously saved pose.
- View Saved Poses.
- Reuse a saved pose in Camera.
- Put a saved pose without a selected album into `Unassigned`.

**Business rules:**

- A pose can be saved only once per user.
- Save and Unsave are separate user actions.
- Saving a pose does not transfer ownership or publication rights.
- Removing a saved state does not remove photos already taken with that pose.

**Result required:** The user has a persistent personal list of poses that can
be reused.

**Output for Phase 4:** Saved Poses and the `Unassigned` destination are stable,
so organization can be added without changing the Save behavior.

**Explicitly out of scope:** User-created albums and user publishing.

### Phase 4 — Albums / Collections

**Objective:** Let users organize saved poses around real-life use cases.

**In scope:**

- Create, rename, and delete an album.
- Save a pose into a chosen album.
- Move a saved pose between albums.
- View saved poses in `Unassigned`.
- Reuse a pose from an album in Camera.

**Business rules:**

- When saving a pose, the user may choose one album.
- If no album is chosen, the pose goes to `Unassigned`.
- A saved pose belongs to at most one album in the first version.
- Deleting an album does not delete its poses; they return to `Unassigned`.
- Unsave is the action that removes a pose from the personal collection.

**Result required:** Users can organize saved poses into collections such as
“Outdoor”, “Travel”, or “Fashion” and reuse them.

**Output for Phase 5:** A complete `Save → Album → Try Pose` loop with stable
ownership and collection rules.

**Explicitly out of scope:** Shared albums, collaborative editing, and
many-albums-per-pose behavior.

### Phase 5 — Personal Pose Creation & AI Extraction

**Objective:** Let users create a reusable pose from their own source material.

**In scope:**

- Choose a source image.
- Request pose creation.
- See whether the request is processing, successful, or failed.
- Retry a failed request.
- View and reuse the resulting pose in Camera.
- Manage personal poses in `My Poses`.

**Result required:** Users can create and use personal poses without depending
on the public Community catalogue.

**Output for Phase 6:** Personal poses participate in the same camera journey as
the built-in and Community poses, with a clear path toward publication.

**Explicitly out of scope:** Public publishing, public discovery, and shared
creator workflows.

### Phase 6 — Publish & Admin Operations

**Objective:** Turn suitable poses into safe, reusable Community content.

**In scope:**

- Prepare a pose for publication.
- Publish and unpublish a pose.
- Control public visibility.
- Review and operate Community content.
- Monitor pose processing and recover failed operations.
- Select the approved extraction provider policy.

**Result required:** Community has a controlled supply of usable poses and can
remove content that should no longer be public.

**Product flywheel:**

`create pose → publish → discover → try → capture → save → reuse`.

**Explicitly out of scope:** Monetization, collaborative publishing, and social
feed behavior.

### Feature-to-phase ownership

| Phase | Primary Features |
| --- | --- |
| Phase 1 | [[FEAT-001-capture-a-photo-on-mobile\|FEAT-001]], [[FEAT-002-manage-a-local-photo-gallery\|FEAT-002]], first-use part of [[FEAT-008-use-published-poses\|FEAT-008]] |
| Phase 2 | [[FEAT-003-browse-and-search-published-poses\|FEAT-003]], Camera handoff part of [[FEAT-008-use-published-poses\|FEAT-008]] |
| Phase 3 | Saved Poses part of [[FEAT-008-use-published-poses\|FEAT-008]] |
| Phase 4 | Album extension of [[FEAT-008-use-published-poses\|FEAT-008]] |
| Phase 5 | [[FEAT-004-extract-reusable-pose-images\|FEAT-004]], [[FEAT-005-manage-a-pose-guide\|FEAT-005]], part of [[FEAT-009-configure-extraction-provider\|FEAT-009]] |
| Phase 6 | [[FEAT-006-publish-a-pose\|FEAT-006]], [[FEAT-007-operate-pose-content-from-admin-web\|FEAT-007]], remaining [[FEAT-009-configure-extraction-provider\|FEAT-009]] |

## Verification

The roadmap is considered on track only when each phase has both the stated
business outcome and the output needed by the next phase.

### Phase gates

| Gate | Evidence of completion |
| --- | --- |
| Phase 1 | A new user can complete the first pose-guided photo flow and view the result. |
| Phase 2 | A published Community pose can be found, tried in Camera, and used for a photo. |
| Phase 3 | A user can Save, view, reuse, and Unsave a pose; unsorted poses appear in Unassigned. |
| Phase 4 | A user can create and manage albums, assign saved poses, and recover poses to Unassigned when an album is deleted. |
| Phase 5 | A user can create a personal pose, understand its processing outcome, retry failure, and use the result in Camera. |
| Phase 6 | An operator can control publication visibility and the public catalogue contains only usable, permitted poses. |

### Success signals

- **First-use success:** percentage of new users who complete one pose-guided
  photo in their first session.
- **Capture value:** percentage of selected poses that lead to a captured photo.
- **Reuse value:** percentage of users who return to use a saved pose.
- **Collection value:** percentage of saved poses assigned to an intentional
  album rather than remaining in `Unassigned`.
- **Community value:** percentage of published poses that are successfully
  discovered and tried.
- **Creation value:** percentage of personal pose requests that produce a pose
  usable in Camera.

### Source of truth and review

- Business boundaries are maintained by the linked Feature documents.
- Delivery ordering is maintained by Harness Plans.
- Current gaps are grounded in [REP-002](../reports/REP-002-feature-gap-and-release-readiness-audit.md)
  and [REP-003](../reports/REP-003-pose-reference-library-convergence-delivery.md).
- This roadmap should be reviewed when a Feature boundary, publication policy,
  or Saved/Album rule changes.
