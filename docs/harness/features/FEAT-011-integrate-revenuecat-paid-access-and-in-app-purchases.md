---
schema_version: 1
type: feature
id: FEAT-011
title: Integrate RevenueCat paid access and in-app purchases
status: proposed
created: 2026-08-26
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
---

# FEAT-011: Integrate RevenueCat paid access and in-app purchases

## Introduction

**Purpose:** Make AI Pose a paid-access app with a clear purchase surface and
confirmed entitlement gating for the core Community and Gallery experience.

**In scope:** RevenueCat offerings, one `premium` entitlement, paid-access
triggers after Splash/from Capture/from a Premium affordance, purchase/restore,
and access to Community pose library/detail/Try Pose plus Gallery/detail and
approved save/share actions.

**Out of scope:** Firebase/Remote Config behavior (FEAT-010), backend
entitlement enforcement or account migration, Android, archive/TestFlight, and
editing `PosesScreen.kt` or `Navigation.kt` in this lane.

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| App user | Customer | Understand the app and purchase access to its core experience | View paid-access information, purchase, restore, and understand outcomes |
| Product Authority | Business role | Set the commercial promise and copy | Approve paid scope, pricing, trial/lifetime policy, and preview behavior |
| RevenueCat / App Store | External system | Sell and restore products | Return offerings, localized prices, transactions, entitlements, and errors |

### User needs

- The user needs to see what the app provides before purchase and understand the
  paid capability list, price, renewal terms, and restore path.
- The user needs access only after RevenueCat confirms the `premium` entitlement.
- The product team needs one explicit paid capability boundary without silently
  implying a free core tier or unlimited AI usage.

### Preconditions

- RevenueCat iOS project, public SDK key, products, offering, and `premium`
  entitlement are configured out of band.
- App Store Connect products/prices and legal URLs are supplied before real
  purchase verification.
- The future prototype defines the exact Premium header affordance and the
  pre-purchase preview/dismissal behavior.

### Trigger

The paid-access surface appears:

1. After Splash on normal launch.
2. When an unentitled user taps Capture.
3. When the user taps the Premium header/entry affordance defined by the
   prototype.

### Main flow

1. **Actor:** The App user reaches the end of Splash. **System:** Load the
   RevenueCat offering and show the paid-access surface with the PO-selected
   scope, localized prices, purchase, restore, and legal actions.
2. **Actor:** The App user purchases or restores. **System:** RevenueCat confirms
   the transaction and entitlement.
3. **Actor:** The entitled App user selects a paid capability. **System:** Allow
   Community library/detail/Try Pose and Gallery/detail/save/share actions as
   approved by Product Authority.

### Alternative flows

- **A1 — Capture gate.** Source step: 1 or 3. Condition: Capture is tapped
  without entitlement. Behavior: route to the same paid-access surface and do
  not enter Camera. Resume at step: 1.
- **A2 — Premium affordance.** Source step: 1 or 3. Condition: the
  prototype-defined Premium control is tapped. Behavior: open the same purchase
  surface or active entitlement state. Resume at step: 1 or 3.
- **A3 — No offering.** Source step: 1. Condition: RevenueCat returns no
  offering. Behavior: show a retryable unavailable state and never fabricate
  paid access. Resume at step: 1 after retry; preview dismissal remains TBD.
- **A4 — Restore succeeds.** Source step: 2. Condition: restore confirms
  entitlement. Behavior: apply it without a duplicate purchase. Ends with:
   paid access restored.
- **A5 — No purchase.** Source step: 1. Condition: the user does not purchase
  or restore. Behavior: remain in the proposed preview/paywall behavior. Ends
  with: no paid capability granted; preview contents and dismissal policy remain
  Unresolved (TBD).

### Exception flows

- **E1 — Purchase cancelled or failed.** Source step: 2. Failure: StoreKit or
  RevenueCat returns cancellation/error. Handling: keep entitlement unchanged
  and show a truthful retryable result. Prohibited: reporting success. Failure
  postcondition: no paid capability is granted.
- **E2 — Entitlement expired, revoked, or billing retry/grace.** Source step: 2
  or 3. Failure: entitlement is inactive or limited. Handling: reflect the
  actual state. Prohibited: granting paid access optimistically. Failure
  postcondition: access remains limited to the approved state.
- **E3 — RevenueCat unavailable.** Source step: 1 or 2. Failure: offering or
  entitlement cannot be loaded. Handling: keep the app in a truthful
  paid-access, preview, or retry state. Prohibited: implying a free core tier.
  Failure postcondition: no unconfirmed entitlement exists.

### Postconditions

- **Success:** Confirmed `premium` entitlement gates the PO-selected Community
  and Gallery capabilities.
- **Failure:** No entitlement is granted; the user sees a truthful retry,
  preview, or unavailable state.

## Requirements

- **FR-001:** The paid-access surface appears after Splash, from Capture when
  unentitled, and from the prototype-defined Premium affordance.
- **FR-002:** The surface explains the PO-selected paid scope: Community pose
  library/detail/Try Pose and Gallery/detail/save/share.
- **FR-003:** RevenueCat exposes one launch `premium` entitlement and the
  configured offering with localized store metadata.
- **FR-004:** Purchase and restore grant access only after confirmed entitlement;
  cancellation, pending, failure, expiry, revocation, and no-offering states are
  truthful.
- **FR-005:** The paywall includes purchase, restore, legal links, loading,
  success, retryable failure, and entitlement state feedback.
- **BR-001:** No RevenueCat secret, receipt, token, or production credential is
  embedded in source or documentation.
- **BR-002:** No core paid capability is granted to a user without confirmed
  entitlement; preview/dismissal behavior remains explicit TBD until approved.
- **BR-003:** `PosesScreen.kt` and `Navigation.kt` remain outside this lane.

## Acceptance

- [ ] After Splash, the paid-access surface shows the PO-selected scope and
  localized offering packages.
- [ ] Capture without entitlement and the prototype-defined Premium affordance
  open the same paid-access flow.
- [ ] A confirmed entitlement enables Community/detail/Try Pose and
  Gallery/detail/save/share as approved; no purchase grants none of those paid
  capabilities.
- [ ] Purchase, restore, cancellation, pending/failure, expiry/revocation, and
  no-offering states are truthful.
- [ ] The exact preview/dismissal behavior is approved before Feature approval;
  no free core tier is inferred.
- [ ] The conflict-safe presentation seam is documented without editing the
  active lane's files.

**Scenario: paid-access trigger**  
Given the user has no confirmed `premium` entitlement  
When the app finishes Splash, the user taps Capture, or the user taps the
prototype-defined Premium affordance  
Then the paid-access surface is shown and no paid capability is granted.

**Scenario: confirmed purchase**  
Given RevenueCat returns a configured offering  
When the user purchases and RevenueCat confirms `premium`  
Then Community/detail/Try Pose and Gallery/detail/save/share become available.

## Relationships

- Decisions: [DEC-007 iOS SDK architecture](../decisions/DEC-007-ios-sdk-integration-architecture.md) and [DEC-008 pricing and offerings](../decisions/DEC-008-revenuecat-pricing-and-offerings.md).
- Plan: [260826-0003 RevenueCat](../plans/260826-0003-integrate-revenuecat-paid-access-and-iap-for-feat-011/plan.md).
- Conflict boundary: the active `remove-my-poses-tab` lane owns `PosesScreen.kt` and `Navigation.kt`.
