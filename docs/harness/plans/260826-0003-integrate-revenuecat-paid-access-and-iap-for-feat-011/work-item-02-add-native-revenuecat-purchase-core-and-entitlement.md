---
work_item: 2
title: Add native RevenueCat purchase core and entitlement
status: pending
priority: P2
effort: TBD
dependencies:
  - 1
decision_dependencies:
  - "[[DEC-007-ios-sdk-integration-architecture|DEC-007]]"
  - "[[DEC-008-revenuecat-pricing-and-offerings|DEC-008]]"
---

# Work Item 2: Add native RevenueCat purchase core and entitlement

## Tasks

- Add the native RevenueCat adapter selected by DEC-007 through the existing
  CocoaPods lane with environment-specific public SDK key injection.
- Configure one premium entitlement and the approved current offering/products.
- Map CustomerInfo/entitlement state to a testable common state model; never use
  an optimistic local premium flag.
- Implement purchase, restore, cancellation, pending/error, expiry, billing
  retry/grace, revocation, no-offering, and idempotent state transitions.
- Keep RevenueCat as the sole StoreKit owner; do not add a second transaction
  listener or finish path.
- Emit sanitized purchase/restore Analytics events through the Firebase contract
  without depending on FEAT-010 runtime availability.

## Scope and affected files

Native RevenueCat bridge/adapter, common purchase state contract, Podfile/lock,
approved configuration inputs, fake adapter tests, and local product/type fixture.
No PosesScreen.kt or Navigation.kt edits.

## Success criteria

- Purchase/restore grants access only after confirmed premium entitlement.
- All terminal/error/expired/revoked/no-offering states remain truthful.
- Product IDs/types and public key handling are environment-safe and documented.

## Risks

- RevenueCat offering metadata can diverge from App Store product setup.
- Leaking raw SDK errors, receipts, or tokens can violate privacy/security.

## Required evidence

Fake adapter tests, product/type fixture, Sandbox matrix, entitlement mapping,
sanitized logs, dependency diff, and no-secret audit.
