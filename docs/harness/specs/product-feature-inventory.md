---
schema_version: 1
type: spec
title: Product Feature Inventory
status: draft
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[ui-ux-system]]"
    - "[[model-entity-catalogue]]"
    - "[[erd]]"
    - "[[api-catalogue]]"
    - "[[product-delivery-roadmap]]"
  decisions: []
  plans: []
  reports: []
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
    - "[[FEAT-013-saved-poses-albums-account-backed|FEAT-013]]"
    - "[[FEAT-014-manage-account-and-session|FEAT-014]]"
    - "[[FEAT-015-manage-app-settings-and-preferences|FEAT-015]]"
    - "[[FEAT-016-user-onboarding-and-interest-personalization|FEAT-016]]"
  source_paths: []
---

# Product Feature Inventory

## Scope

This inventory is a business-feature map. It records each Feature's observable boundary and ownership; implementation delivery, code parity, Plans, and runtime gaps are intentionally outside this inventory.

The landing-level traceability map is in the [Harness README](../README.md).
Shared model/entity, ERD, and API definitions are maintained once in
[docs/spec](./data-contract.md)
([data](data-contract.md), [api](api-contract.md));
Feature pages link to those entries instead of duplicating them.
Harness stubs remain at [model catalogue](./model-entity-catalogue.md),
[global ERD](./erd.md), and [API catalogue](./api-catalogue.md) for wikilink compatibility.

## Current feature inventory

| Feature | Business capability | Primary actor or owner | Boundary |
| --- | --- | --- | --- |
| [[FEAT-001-capture-a-photo-on-mobile\|FEAT-001]] | Capture a photo on mobile | Photographer | Capture a source photo for later use; pose extraction is FEAT-004. |
| [[FEAT-002-manage-a-local-photo-gallery\|FEAT-002]] | Manage a local photo gallery | Photographer | Organize personal photos; pose management is FEAT-005. |
| [[FEAT-003-browse-and-search-published-poses\|FEAT-003]] | Browse and search published poses | Visitor or signed-in user | Browse, search, inspect, refresh, and recover the public catalogue; no Save, Try Pose, extraction, or publication. |
| [[FEAT-004-extract-reusable-pose-images\|FEAT-004]] | Extract one reusable pose image | Signed-in user or Admin operator | One common extraction contract and ownership assignment for both creator roles. |
| [[FEAT-005-manage-a-pose-guide\|FEAT-005]] | Manage a pose guide | Pose Owner | My Poses, pose metadata, re-extraction, retry, revert, and terminal deletion around a FEAT-004 result. |
| [[FEAT-006-publish-a-pose\|FEAT-006]] | Publish or unpublish a pose | Pose Owner | Public-data acknowledgement, publication eligibility, and confirmed public visibility lifecycle. |
| [[FEAT-007-operate-pose-content-from-admin-web\|FEAT-007]] | Operate pose content from Admin Web | Admin operator | Admin surface for intake, status, ownership, pose management in FEAT-005, and invoking FEAT-004 and FEAT-006; no alternate extraction or publication model. |
| [[FEAT-008-use-published-poses\|FEAT-008]] | Use published poses | Signed-in user | Save, Unsave, Saved collection, Try Pose, camera guide lifecycle, and consequences of publication removal. |
| [[FEAT-009-configure-extraction-provider\|FEAT-009]] | Configure extraction provider | Admin operator | Select and persist the global extraction engine (Gemini native or Higgsfield CLI) for extract jobs; timing, default, and credential policy in DEC-001. |
 | [[FEAT-013-saved-poses-albums-account-backed\|FEAT-013]] | Manage Saved Poses and future Albums boundary | Signed-in Account | Own Saved/Unsave/Saved list/Try Pose and SavedEntry semantics; consume FEAT-014’s valid Account/session; Albums remain future/out of scope. |
 | [[FEAT-014-manage-account-and-session\|FEAT-014]] | Manage Account and Session | Signed-in Account or Guest | Own Account entry/screen, identity/provider/session presentation, sign-out, expiry/invalid-session recovery, signed-out gating, and account isolation; no profile editing or new auth contract. |
 | [[FEAT-015-manage-app-settings-and-preferences\|FEAT-015]] | Manage App Settings and Preferences | Guest or signed-in user | Own the grouped Settings surface, app-level non-camera preference boundary, privacy/permission/help/about entry points, and cross-feature routing; does not own Camera settings, Account/session, Saved, or Premium behavior. |
| [[FEAT-016-user-onboarding-and-interest-personalization\|FEAT-016]] | User Onboarding and Interest Personalization | First-time Photographer or returning user | First-run experience, interest vibe selection, interactive pose alignment trial, and permission priming; hands off to FEAT-001/FEAT-003 and replayable from FEAT-015. |

## Supporting surfaces

- FEAT-003 consumes the public visibility established by FEAT-006.
- FEAT-008 consumes the published poses discovered through FEAT-003 and does not change ownership.
- FEAT-007 is an operating surface for Admin-owned pose content; Admin-created poses follow the same extraction, ownership, guide, and publication boundaries as other poses.
- FEAT-009 owns global extraction engine configuration; FEAT-007 invokes FEAT-009 through Admin Web without redefining extract or provider policy.
- FEAT-013 consumes FEAT-014’s valid Account/session and does not redefine Account UI or sign-out semantics.
 - FEAT-014 owns observable Account/session lifecycle; shared Account fields and session/API mechanics remain in their canonical specs.
 - FEAT-015 owns the Settings surface and only approved app-level non-camera preferences; it routes to FEAT-011, FEAT-013, and FEAT-014 and leaves all camera settings with FEAT-012.
- FEAT-016 owns the First-Time User Experience (FTUE) and interest vibe selection; it hands off to FEAT-001 Camera or FEAT-003 Pose Library, and is replayable via FEAT-015 Settings.

## Documentation rules

- Each observable behavior has one owning Feature.
- A Feature may invoke another Feature's behavior but must not redefine its contract.
- Feature documents describe business actors, flows, requirements, and acceptance; implementation design and delivery status belong elsewhere.
- When a business boundary changes, update the owning Features and this inventory together.

## Verification

- Validate the Feature documents with `ckh validate --kind feature --workspace .`.
- Check each Feature workflow state with `ckh workflow check TARGET --workspace .`.
- Check outgoing Feature and Spec relationships with `ckh graph check --workspace .` after rebuilding the index.
