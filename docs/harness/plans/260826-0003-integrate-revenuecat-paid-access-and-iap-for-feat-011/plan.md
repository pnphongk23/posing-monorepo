---
title: Integrate RevenueCat paid access and IAP for FEAT-011
description: iOS-only plan for native RevenueCat paid access, purchase, restore, and paywall triggers.
status: in_progress
approval:
  status: approved
  required_by: Repository Maintainer
  decided: 2026-08-31
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

Planning-only paid-access lane. FEAT-011 and DEC-007/DEC-008 are approved;
Repository Maintainer approval is recorded before Cook. AI Pose is paid access,
not a free core tier. This plan owns RevenueCat and paywall behavior only;
Firebase/Remote Config is FEAT-010's separate plan.

## Verification ledger

| Claim | Status | Evidence |
| --- | --- | --- |
| Product is iOS-only KMP with existing CocoaPods lane | Verified | composeApp Gradle config, Podfile, iosApp workspace |
| Product authority now contains exactly annual and monthly packages | Verified | DEC-008 approved 2026-08-31; prototype paywall renders annual and monthly |
| Current app surfaces include Poses, Gallery, Camera, pose detail, and camera guide | Verified | Navigation.kt, PosesScreen.kt, PoseDetailScreen.kt, GalleryScreen.kt, CameraScreen.kt |
| RevenueCat 5.87 implementation exists via CocoaPods, including purchase core, paywall, and tests | Verified | implementation and tests are present; Sandbox/real-billing verification is pending external configuration |
| Premium header affordance as trigger | Verified | DEC-008 D-TRIGGER excludes it; static prototype may retain a conflict note |
| Trigger set | Verified | DEC-008 D-TRIGGER: Home Try Pose, Home Camera/Capture, gated Gallery save/share; no post-Splash auto-paywall; Camera dismissal and Gallery share use the approved minimal seam |
| Non-purchaser preview/dismissal policy | Verified | Binding sandbox design: triggered paywall dismissal returns to true prior context through the approved seam; no access is granted |
| RevenueCat SDK version and lane | Verified | Official release latest resolved 2026-08-31 to 5.87.1: https://github.com/RevenueCat/purchases-ios/releases/latest; installation docs confirm CocoaPods support: https://www.revenuecat.com/docs/getting-started/installation/ios; paywall docs require purchases-ios >=5.16.0 and iOS 15+ |
| Pod version choice | Verified | Cook should pin `pod 'RevenueCat', '~> 5.87'`; no Podfile/Podfile.lock update is claimed here |

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
| BR-002 entitlement gate and dismissal policy | 1, 2, 3, 4 |
| BR-003 approved open seam and conflict boundary | 1, 3, 4 |

## Implementation boundaries

- Allowed: native RevenueCat bridge/adapter, common purchase state contract, new
  IAP screen package, the approved minimal App-root/Navigation presentation seam
  for true Camera prior-context dismissal and distinct Gallery share, approved
  Podfile/resource wiring, and tests/runbook.
- Forbidden: edits to PosesScreen.kt, unrelated navigation rewrites, and any
  Premium header affordance trigger; the latter remains prototype-owned.
- Paid scope: Capture/Camera, Try Pose, and Gallery save/share only. Home,
  Community browsing/detail, and Gallery browsing/detail are free. Do not
  promise unlimited AI usage or add products/trials.
- Credentials use placeholders only; no RevenueCat secret key, receipt, token,
  or App Store credential is committed.
- No archive, TestFlight, keychain repair, commit, push, or new workspace.

## Verification

- Run ckh workflow status TARGET and ckh workflow check TARGET before approval.
- Before changing existing symbols, run sourcewalk/direct impact checks; do not
  re-index stale GitNexus.
- Verify native RevenueCat offering/product mapping, one premium entitlement,
  localized store metadata, and environment-specific public SDK injection.
- Test Home Try Pose, Home Capture/Camera, and gated Gallery save/share converge
  on one paywall; verify no post-Splash or Premium-header trigger and confirmed
  access only to the three approved capabilities.
- Use fake adapter plus local product/type fixture, then RevenueCat Sandbox for
  authoritative purchase/restore/revocation verification for annual and monthly. Do not add a second
  StoreKit transaction listener when RevenueCat owns StoreKit.
- Run KMP tests and existing unsigned Xcode workspace build only after approval;
  no archive/upload. Audit secrets and conflict files.
