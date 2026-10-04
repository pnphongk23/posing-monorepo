---
schema_version: 1
type: decision
id: DEC-007
title: Choose the iOS SDK integration architecture
status: approved
created: 2026-08-25
approved: 2026-08-26
approved_by: Product Authority (PO) — Firebase scope only
relationships:
  specs:
    - "[[technical-architecture]]"
  decisions: []
  plans:
    - "[[260826-0003-integrate-firebase-observability-and-remote-config-for-feat-010/plan|Firebase plan]]"
    - "[[260826-0003-integrate-revenuecat-paid-access-and-iap-for-feat-011/plan|RevenueCat plan]]"
  reports: []
  rules: []
  features:
    - "[[FEAT-010-integrate-firebase-revenuecat|FEAT-010]]"
    - "[[FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases|FEAT-011]]"
  source_paths:
    - mobile/iosApp/Podfile
    - mobile/iosApp/Podfile.lock
    - mobile/iosApp/iosApp.xcworkspace
    - mobile/iosApp/iosApp/AppDelegate.swift
    - mobile/composeApp/build.gradle.kts
    - mobile/iosApp/project.yml
---

# DEC-007: Choose the iOS SDK integration architecture

## Context

The product is iOS-only KMP. `mobile/composeApp/build.gradle.kts` already uses
the Kotlin CocoaPods plugin and points at `mobile/iosApp/Podfile`. The Podfile
and the current working-tree `Pods` directory contains `composeApp` and
`MijickCamera`; the Pods directory is not tracked by Git. The workspace is
`iosApp.xcworkspace` and the scheme is `iosApp`. There is no
Firebase or RevenueCat pod today. Native startup is in `AppDelegate.swift`.

The integration must support Firebase Analytics, Crashlytics, Firestore config,
Crashlytics dSYM handling, and RevenueCat purchases while keeping the Compose
surface testable and keeping credentials out of source.

## Decision

**Approved architecture for FEAT-010 (2026-08-26, Product Authority/PO):** use native iOS Firebase SDKs through the existing CocoaPods
integration, with a thin platform bridge into Compose:

**Approval scope:** This approval covers only the Firebase Core, Analytics,
Crashlytics, and Firestore integration for FEAT-010. The RevenueCat
architecture below remains **proposed** and is not authorized by this approval;
it remains gated by FEAT-011 and DEC-008 approval.

**PO direction (2026-08-25):** select the native iOS RevenueCat SDK for the
launch slice. This records product direction; the Decision remains `proposed`
until the Repository Maintainer completes the Harness approval step.

- Add the Firebase iOS SDK packages/pods required for Core, Analytics, Crashlytics, and
  Firestore; do not introduce an unmanaged third dependency lane. Firestore `config/app`
  is public-readable and its last successfully fetched payload is cached in UserDefaults
  for synchronous first paint; compile-time defaults apply before the first successful fetch.
- Call `FirebaseApp.configure()` from the native iOS app delegate after a
  resource/configuration presence check. Add `GoogleService-Info.plist` only as
  a placeholder-managed project resource; the real file is supplied out of band
  and is not committed.
- Configure Crashlytics release symbolication/dSYM upload as an Xcode build
  step/runbook, and treat upload failure as a diagnostic failure rather than an
  app-launch failure.
- Expose a small common-facing observability/config **contract** whose production
  implementation is the **native Swift Firebase bridge in `AppDelegate.swift`**;
  the Kotlin side is a **pure contract/test seam only** (`EndpointPolicy.validate`,
  `AppStartupConfig.resolveEndpointValue`, `AppStartupConfig.applyEndpoint`). Use
  stable event names and sanitized parameters.
- **Proposed only — not approved by this record:** use RevenueCat's native `purchases-ios` SDK via the same CocoaPods lane and a
  thin Swift bridge/adapter for configure, offerings, purchase, restore, and
  entitlement state. Do not use `purchases-kmp` for the launch slice.
- Keep RevenueCat public mobile SDK keys environment-specific and placeholder
  based; never embed a secret RevenueCat key.

## Alternatives

- **A — Existing CocoaPods + native iOS SDKs + thin bridge (recommended):** fits
  the current KMP/CocoaPods/workspace shape, minimizes new build plumbing, and
  keeps iOS-only purchase behavior in the native SDK. Cost: Podfile.lock and
  Xcode resource/build-step maintenance.
- **B — Swift Package Manager for all new SDKs:** modern native dependency
  mechanism, but creates a second package-management path beside CocoaPods and
  KMP framework integration. Higher integration risk for this repository.
- **C — `purchases-kmp` plus shared abstractions:** more common Kotlin API, but
  adds a KMP-specific SDK compatibility surface when the product has no Android
  target and the native iOS SDK is the primary supported runtime. Revisit if an
  Android target or shared billing requirement is approved.

## Consequences

- The Podfile and Podfile.lock become implementation touchpoints; `pod install`
  and the workspace build are required verification gates.
- Firebase initialization and dSYM upload belong to native iOS build/runtime
  ownership; Compose consumes sanitized, testable interfaces.
- RevenueCat product identifiers and entitlement names live in configuration,
  while product prices remain App Store Connect/RevenueCat source of truth.
- Native bridge code needs cancellation/error mapping tests and must not expose
  StoreKit receipt or SDK secrets to common UI code.

## Evidence

- **Observed:** `mobile/iosApp/Podfile` has `composeApp` and `MijickCamera`; its
  `Podfile.lock` lists those pods and CocoaPods 1.16.2 only.
- **Observed:** `mobile/composeApp/build.gradle.kts` applies
  `org.jetbrains.kotlin.native.cocoapods` and points to the Podfile.
- **Observed:** `mobile/iosApp/iosApp/AppDelegate.swift` is the native launch
  hook and currently installs the camera bridge before creating the root view.
- **Observed:** `mobile/iosApp/iosApp.xcworkspace` and scheme `iosApp` are the
  existing Xcode build path; `project.yml` declares bundle `camerapose.app`.
- **Unresolved:** exact SDK versions and the final dSYM script mechanism must be
  selected during implementation from the repository's supported Xcode/CocoaPods
  toolchain; this Decision does not authorize uncontrolled dependency upgrades.

## Supersession

This decision supersedes no earlier decision.
