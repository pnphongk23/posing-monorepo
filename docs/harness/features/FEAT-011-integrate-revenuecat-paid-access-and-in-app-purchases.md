---
schema_version: 1
title: Integrate RevenueCat paid access and in-app purchases
relationships:
  specs:
    - "[[product-feature-inventory]]"
    - "[[ui-ux-system]]"
  decisions:
    - "[[DEC-007-ios-sdk-integration-architecture|DEC-007]]"
    - "[[DEC-008-revenuecat-pricing-and-offerings|DEC-008]]"
  plans:
    - "[[260826-0003-integrate-revenuecat-paid-access-and-iap-for-feat-011/plan|260826-0003]]"
  reports: []
  rules: []
  features: []
  source_paths:
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/App.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PosesScreen.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PoseDetailScreen.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/GalleryScreen.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt
    - mobile/iosApp/Podfile
type: feature
id: FEAT-011
status: approved
created: 2026-08-26
approved: 2026-08-31
approved_by: Pham Nhu Phong
---

# FEAT-011: Integrate RevenueCat paid access and in-app purchases

## Introduction

**Purpose:** Add a clear RevenueCat purchase surface and confirmed entitlement
gating for Capture/Camera, Try Pose, and PO-selected Gallery save/share actions.

**In scope:** One `premium` entitlement, one `default` offering with the two
DEC-008 packages, triggered purchase/restore flow, and truthful entitlement
states.

**Out of scope:** Firebase/Remote Config (FEAT-010), backend enforcement,
  Android, archive/TestFlight, and unrelated edits to `PosesScreen.kt` or
  `Navigation.kt`. The previous Navigation boundary is open only for the
  approved App-root/presentation seam required by this feature.
Home, Community browsing/detail, and Gallery browsing/detail remain free.

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| App user | Customer | Understand and purchase paid capabilities | Trigger access, purchase, restore, or dismiss |
| Product Authority | Business role | Set the commercial promise | Approve scope, price, and trial policy |
| RevenueCat / App Store | External system | Sell and restore products | Return offerings, localized prices, entitlements, and errors |

### User needs

- The user needs clear paid scope, localized price, renewal terms, and restore.
- The user needs access only after confirmed `premium` entitlement.

### Preconditions

- RevenueCat products, `default` offering, `premium` entitlement, legal URLs,
  sandbox users, and public SDK key are supplied externally.
- StoreKit localized metadata is available for real purchase verification.

### Trigger

Paid access appears only when an unentitled Home user taps Try Pose or Camera
(Capture), or attempts a gated Gallery save/share action. It never appears after
Splash and has no Premium header affordance trigger. Camera dismissal returns
through the approved seam to the true prior context; Gallery share remains a
distinct share action.

### Main flow

1. **Actor:** An unentitled user taps a gated action. **System:** Show the same
   paid-access surface using the `default` offering and localized metadata.
2. **Actor:** The user purchases or restores. **System:** RevenueCat confirms the
   transaction and `premium` entitlement.
3. **Actor:** An entitled user uses a paid action. **System:** Allow only
   Capture/Camera, Try Pose, and Gallery save/share.

### Alternative flows

- **A1 — Capture/Try Pose gate.** Source step: 1. Condition: user is not
  entitled. Behavior: show the common surface and do not complete the action.
  Resume at step: 1.
- **A2 — Gallery save/share gate.** Source step: 1. Condition: user is not
  entitled. Behavior: show the common surface and do not complete save/share.
  Resume at step: 1.
- **A3 — No offering.** Source step: 1. Condition: offering is unavailable.
  Behavior: show a retryable unavailable state; never fabricate access. Resume at
  step: 1 after retry.
- **A4 — Restore succeeds.** Source step: 2. Condition: restore confirms
  entitlement. Behavior: apply confirmed entitlement without a duplicate
  purchase. Ends with: paid access restored.
- **A5 — Dismissal.** Source step: 1. Condition: user dismisses the triggered
  paywall. Behavior: return to prior context; grant no access and complete no
  gated action. Ends with: no paid action completed.

### Exception flows

- **E1 — Purchase cancelled or failed.** Source step: 2, purchase attempt.
  Handling:
  keep entitlement unchanged and show a truthful retryable result. Prohibited:
  reporting success or granting access.
- **E2 — Expired, revoked, billing retry, or grace.** Source step: 2,
  entitlement update. Handling: reflect actual entitlement. Prohibited: granting
  optimistically.
- **E3 — RevenueCat unavailable.** Source step: 1, offering or entitlement
  request. Handling: show truthful unavailable/retry state. Prohibited: creating an
  unconfirmed entitlement.

### Postconditions

- **Success:** Confirmed `premium` unlocks only Capture/Camera, Try Pose, and
  Gallery save/share.
- **Failure:** No entitlement or gated action is granted/completed.

## Requirements

- **FR-001:** Show paid access only for an unentitled Home user tapping Try Pose
  or Camera (Capture), or attempting gated Gallery save/share; never after Splash
  and never from a Premium header.
- **FR-002:** Explain the paid scope and two DEC-008 packages: annual $39.99 /
  ₫999k highlighted and monthly $5.99 / ₫149k as the comparison anchor; no
  trial/introductory offer.
- **FR-003:** Expose one `premium` entitlement and one `default` offering.
- **FR-004:** Purchase/restore grants access only after confirmed entitlement;
  cancellation, pending, failure, expiry, revocation, and no-offering states are truthful.
- **FR-005:** Include purchase, restore, legal links, loading, success, retryable
  failure, dismissal, and entitlement-state feedback.
- **BR-001:** No RevenueCat secret, receipt, token, or production credential is
  embedded in source or documentation.
- **BR-002:** No paid capability or gated save/share action is granted/completed
  without confirmed `premium`; dismissal returns to prior context without access.
- **BR-003:** `PosesScreen.kt` remains outside this lane. The previous
  Navigation boundary is an approved open seam for minimal App-root/presentation
  wiring needed by Camera dismissal and Gallery share, because commit `0ca00b0`
  (`feat(poses): remove My Poses tab`) is merged on `main` and there is no
  active owner. Unrelated navigation rewrites remain forbidden.

## Acceptance

- [ ] Try Pose, Camera (Capture), and gated Gallery save/share without entitlement
  open one paid-access flow; Splash and Premium header do not.
- [ ] The flow shows annual and monthly localized packages, annual highlighted,
  with no trial.
- [ ] Confirmed `premium` enables only Capture/Camera, Try Pose, and Gallery
  save/share; Home and browsing/detail remain free.
- [ ] Purchase, restore, cancel, pending/failure, expiry/revocation, and
  no-offering outcomes are truthful.
- [ ] Dismissal returns to prior context and grants no access.
- [ ] No secret/receipt/token is committed; `PosesScreen.kt` is untouched; and
  Navigation changes, if any, are limited to the approved seam with Camera
  prior-context dismissal and distinct Gallery share evidence.

**Scenario: gated trigger**
Given the user has no confirmed `premium` entitlement  
When the user taps Try Pose, Camera (Capture), or Gallery save/share from Home
Then the paid-access surface is shown and the gated action does not complete.

**Scenario: confirmed purchase**  
Given RevenueCat returns the configured `default` offering
When the user purchases and RevenueCat confirms `premium`  
Then Capture/Camera, Try Pose, and Gallery save/share become available.

## Relationships

- Decisions: [DEC-007](../decisions/DEC-007-ios-sdk-integration-architecture.md) and [DEC-008](../decisions/DEC-008-revenuecat-pricing-and-offerings.md).
- Plan: [260826-0003 RevenueCat](../plans/260826-0003-integrate-revenuecat-paid-access-and-iap-for-feat-011/plan.md).
- Boundary decision: `PosesScreen.kt` remains conflict-owned; `Navigation.kt` is
  an approved open seam only for minimal Camera prior-context dismissal and
  distinct Gallery share wiring. Evidence: merged commit `0ca00b0` on `main`
  and no active owner.
