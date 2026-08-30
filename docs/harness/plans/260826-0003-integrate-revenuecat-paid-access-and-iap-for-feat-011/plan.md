---
title: Integrate RevenueCat paid access and IAP for FEAT-011
description: iOS-only plan for native RevenueCat paid access, purchase, restore, and paywall triggers.
status: pending
approval:
  status: pending
  required_by: Repository Maintainer
priority: P1
effort: M
branch: codex/integrate-revenuecat-paid-access-and-iap-for-feat-011
tags:
  - ios
  - revenuecat
  - iap
  - paid-access
  - paywall
blockedBy: []
blocks: []
relationships:
  specs:
    - "[[product-feature-inventory]]"
    - "[[ui-ux-system]]"
  decisions:
    - "[[DEC-007-ios-sdk-integration-architecture|DEC-007]]"
    - "[[DEC-008-revenuecat-pricing-and-offerings|DEC-008]]"
  plans: []
  reports: []
  rules: []
  features:
    - "[[FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases|FEAT-011]]"
  source_paths:
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/App.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PosesScreen.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PoseDetailScreen.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/GalleryScreen.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt
    - mobile/iosApp/Podfile
created: 2026-08-26T00:03:00+07:00
createdBy: Harness CLI
---

# Integrate RevenueCat paid access and IAP for FEAT-011

## Overview

Planning-only paid-access lane. FEAT-011 and DEC-007/DEC-008 remain proposed;
Repository Maintainer approval is required before Cook. AI Pose is paid access,
not a free core tier. This plan owns RevenueCat and paywall behavior only;
Firebase/Remote Config is FEAT-010's separate plan.

## Verification ledger

| Claim | Status | Evidence |
| --- | --- | --- |
| Product is iOS-only KMP with existing CocoaPods lane | Verified | composeApp Gradle config, Podfile, iosApp workspace |
| Current app surfaces include Poses, Gallery, Camera, pose detail, and camera guide | Verified | Navigation.kt, PosesScreen.kt, PoseDetailScreen.kt, GalleryScreen.kt, CameraScreen.kt |
| No current RevenueCat/purchase implementation | Verified | direct source search across mobile and manifests |
| Exact prototype Premium header location | Unresolved | future prototype not present |
| Non-purchaser preview/dismissal policy | Unresolved | Product Authority must define |
| RevenueCat SDK version | Unresolved | select from current supported native toolchain |

## Work Items

- [Work Item 1: Close RevenueCat authority, pricing, and product configuration](./work-item-01-close-revenuecat-authority-pricing-and-product-configuration.md)
- [Work Item 2: Add native RevenueCat purchase core and entitlement](./work-item-02-add-native-revenuecat-purchase-core-and-entitlement.md)
- [Work Item 3: Build paid-access paywall and triggers](./work-item-03-build-paid-access-paywall-and-triggers.md)
- [Work Item 4: Verify IAP states, Sandbox, and iOS build](./work-item-04-verify-iap-states-sandbox-and-ios-build.md)

## Coverage

| FEAT-011 requirement | Work Items |
| --- | --- |
| FR-001 paid-access triggers | 1, 3, 4 |
| FR-002 capability/copy scope | 1, 3, 4 |
| FR-003 offering and premium entitlement | 1, 2, 4 |
| FR-004 purchase/restore/truthful states | 2, 3, 4 |
| FR-005 paywall/legal/loading/error UI | 1, 3, 4 |
| BR-001 credential/privacy boundary | 1, 2, 4 |
| BR-002 entitlement gate/TBD preview | 1, 2, 3, 4 |
| BR-003 conflict boundary | 1, 3, 4 |

## Implementation boundaries

- Allowed: native RevenueCat bridge/adapter, common purchase state contract, new
  IAP screen package, App-root presentation seam only after authority closure,
  approved Podfile/resource wiring, and tests/runbook.
- Forbidden: edits to PosesScreen.kt or Navigation.kt in this lane; the precise
  Premium header affordance is prototype-owned and must be handed off if it
  requires the active lane.
- Paid scope: Community library/detail/Try Pose and Gallery/detail/save/share.
  Do not promise unlimited AI usage or add unapproved products/trials.
- Credentials use placeholders only; no RevenueCat secret key, receipt, token,
  or App Store credential is committed.
- No archive, TestFlight, keychain repair, commit, push, or new workspace.

## Verification

- Run ckh workflow status TARGET and ckh workflow check TARGET before approval.
- Before changing existing symbols, run sourcewalk/direct impact checks; do not
  re-index stale GitNexus.
- Verify native RevenueCat offering/product mapping, one premium entitlement,
  localized store metadata, and environment-specific public SDK injection.
- Test after Splash, Capture-without-entitlement, and prototype Premium
  affordance trigger the same paywall; test confirmed access to all listed
  Community/Gallery capabilities.
- Use fake adapter plus local product/type fixture, then RevenueCat Sandbox for
  authoritative purchase/restore/revocation verification. Do not add a second
  StoreKit transaction listener when RevenueCat owns StoreKit.
- Run KMP tests and existing unsigned Xcode workspace build only after approval;
  no archive/upload. Audit secrets and conflict files.
