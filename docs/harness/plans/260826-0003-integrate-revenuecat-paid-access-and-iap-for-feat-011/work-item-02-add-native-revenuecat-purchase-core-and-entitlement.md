---
work_item: 2
title: Add native RevenueCat purchase core and entitlement
status: completed
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
- Configure one premium entitlement and the approved annual/monthly offering/products.
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

## Remediation evidence

- `mobile/iosApp/Podfile` uses `pod 'RevenueCat', '~> 5.87'`; `Podfile.lock`
  resolved `RevenueCat (5.87.1)` after bounded `pod install`.
- Swift `RevenueCatAdapter` owns RevenueCat/StoreKit and communicates through
  `com.aipose.revenuecat.request/response`; Kotlin
  `IosRevenueCatGateway` exposes one reactive `StateFlow<PurchaseSnapshot>`.
- Offering entry and retry request the `default` offering. Purchase maps the
  selected product ID to the matching RevenueCat `Package`; CustomerInfo is the
  only entitlement authority for `premium`.
- Bounded `./gradlew :composeApp:iosSimulatorArm64Test` passed with
  `BUILD SUCCESSFUL in 50s`; tests cover load/restore calls, exactly the annual
  and monthly IDs,
  unknown-product rejection, entitlement and terminal states.
- Follow-up `./gradlew :composeApp:allTests` completed with `BUILD SUCCESSFUL
  in 1m 10s` after the bridge and state corrections.
- `swiftc -parse mobile/iosApp/iosApp/RevenueCatAdapter.swift` passed. This is
  syntax validation only, not typecheck or native runtime evidence.
- Exact stronger check attempted: `swiftc -typecheck
  mobile/iosApp/iosApp/RevenueCatAdapter.swift` → failed with
  `error: no such module 'RevenueCat'` at the `import RevenueCat` line.
  `Tôi không thể xác minh điều này hoạt động vì môi trường không có module RevenueCat để swiftc type-check file iosApp.`
  This does not mark native/Xcode or Sandbox criteria complete.
- Sanitized native analytics emit fixed source/outcome metadata only. Secret,
  receipt/token, Android, and conflict-boundary audits passed.
- Sandbox and unsigned workspace build remain WI4 evidence and are not claimed
  here.
- CustomerInfo billing-issue mapping conservatively reports `BILLING_RETRY`;
  this adapter does not invent a provider-specific grace-period boundary.
  Common fake tests retain explicit grace-period coverage without claiming
  native RevenueCat proof.
