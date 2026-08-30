---
title: Integrate Firebase observability and Remote Config for FEAT-010
description: iOS-only plan for Firebase Analytics, Crashlytics, and recoverable api_baseurl configuration.
status: completed
approval:
  status: approved
  required_by: Repository Maintainer
  decided: 2026-08-26
priority: P1
effort: M
branch: codex/integrate-firebase-observability-and-remote-config-for-feat-010
tags:
  - ios
  - firebase
  - remote-config
  - analytics
  - crashlytics
blockedBy: []
blocks: []
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[product-feature-inventory]]"
  decisions:
    - "[[DEC-006-remote-config-api-baseurl-policy|DEC-006]]"
    - "[[DEC-007-ios-sdk-integration-architecture|DEC-007]]"
  plans: []
  reports:
    - "[[REP-011-firebase-observability-remote-config-delivery|REP-011]]"
  rules: []
  features:
    - "[[FEAT-010-integrate-firebase-revenuecat|FEAT-010]]"
  source_paths:
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/App.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/data/AppConfig.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseServiceLocator.kt
    - mobile/iosApp/Podfile
    - mobile/iosApp/iosApp/AppDelegate.swift
    - mobile/iosApp/project.yml
created: 2026-08-26T00:03:00+07:00
createdBy: Harness CLI
---

# Integrate Firebase observability and Remote Config for FEAT-010

## Overview

Planning-only Firebase lane. FEAT-010 and DEC-006/DEC-007 remain proposed;
Repository Maintainer approval is required before Cook. This plan does not own
RevenueCat, paid access, or paywall behavior; those are in FEAT-011's separate
plan.

## Verification ledger

| Claim | Status | Evidence |
| --- | --- | --- |
| Existing integration lane is CocoaPods | Verified | mobile/composeApp/build.gradle.kts, mobile/iosApp/Podfile |
| Current endpoint has two runtime holders | Verified | AppConfig.kt, PoseServiceLocator.kt |
| API service can be initialized before nominal screen callbacks | Verified | eager repository/default coordinator evidence in prior scout |
| Exact Firebase SDK versions | Unresolved | select from current Xcode/CocoaPods toolchain during Cook |
| GitNexus freshness | Unresolved | stale by task constraint; use sourcewalk/direct scans |

## Work Items

- [Work Item 1: Close Firebase authority and SDK configuration](./work-item-01-close-firebase-authority-and-sdk-configuration.md)
- [Work Item 2: Add Firebase bootstrap, Remote Config, Analytics, and Crashlytics](./work-item-02-add-firebase-bootstrap-remote-config-analytics-and-crashlytics.md)
- [Work Item 3: Verify Firebase fallback, observability, and iOS build](./work-item-03-verify-firebase-fallback-observability-and-ios-build.md)

## Coverage

| FEAT-010 requirement | Work Items |
| --- | --- |
| FR-001 Firebase startup | 1, 2, 3 |
| FR-002 api_baseurl and consistent endpoint application | 1, 2, 3 |
| FR-003 fallback/cache/offline/invalid recovery | 2, 3 |
| FR-004 Analytics privacy/event contract | 2, 3 |
| FR-005 Crashlytics/dSYM | 1, 2, 3 |
| BR-001 no circular Firebase/API dependency | 1, 2, 3 |
| BR-002 conflict boundary | 1, 3 |

## Implementation boundaries

- Allowed: Firebase/config bridge, App.kt, AppConfig.kt,
  PoseServiceLocator.kt, approved dependency manifests, Podfile/resource
  wiring, AppDelegate.swift, and tests/runbook.
- Forbidden: RevenueCat/paywall work, Android, archive/TestFlight, and edits to
  mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PosesScreen.kt
  or mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt.
- Credentials use placeholders only; never commit GoogleService-Info.plist
  secrets or private keys.

## Verification

- Run ckh workflow status TARGET and ckh workflow check TARGET before approval.
- Run sourcewalk/direct impact checks before changing symbols; GitNexus is not
  re-indexed.
- Test default/cache/valid fetch/offline/failure/empty/malformed/dead-endpoint
  outcomes and prove configuration precedes first API service construction.
- Run KMP tests and the existing unsigned Xcode workspace build only after
  authority approval; do not archive, upload, repair keychain, or commit.
- Audit secrets, unrelated dependency churn, and conflict-lane files.
