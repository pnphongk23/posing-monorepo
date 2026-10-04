---
schema_version: 1
title: Integrate Firebase observability and Firestore config recovery
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[product-feature-inventory]]"
  decisions:
    - "[[DEC-006-remote-config-api-baseurl-policy|DEC-006]]"
    - "[[DEC-007-ios-sdk-integration-architecture|DEC-007]]"
  plans:
    - "[[260826-0003-integrate-firebase-observability-and-remote-config-for-feat-010/plan|260826-0003]]"
  reports: []
  rules: []
  features: []
  source_paths:
    - mobile/iosApp/iosApp/Core/Network/AppConfig.swift
    - mobile/iosApp/iosApp/Core/Network/AppConfigService.swift
    - mobile/iosApp/iosApp/Core/Network/EndpointPolicy.swift
    - mobile/iosApp/iosApp/AppDelegate.swift
    - mobile/iosApp/project.yml
type: feature
id: FEAT-010
status: approved
created: 2026-08-25
approved: 2026-08-26
approved_by: Product Authority (PO)
---

# FEAT-010: Integrate Firebase observability and Firestore config recovery

## Introduction

**Purpose:** Give the iOS app production observability and a recoverable runtime
endpoint switch via Firestore `config/app` without making Firebase availability a prerequisite for app
startup or API recovery.

**Roadmap note:** This Feature covers technical observability/configuration only;
paid access and RevenueCat behavior are owned by FEAT-011.

**In scope:** Firebase Analytics, Crashlytics, Firestore `config/app` dynamic config,
the exact `api_baseurl`, `account_enabled`, and `extractPoseEnabled` keys, compile-time defaults and fetch fallback behavior, sanitized event
contracts, and release dSYM documentation.

**Out of scope:** RevenueCat products, subscriptions, paid-access behavior,
paywall UI, Android support, archive/TestFlight upload, backend changes, and
editing `PosesScreen.kt` or `Navigation.kt` while the active lane owns them.

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| App user | Customer | Use the app without being stranded by observability/configuration outages | Receive a launchable app and truthful operational errors |
| App operator | Operations role | Keep the API endpoint recoverable and diagnose failures | Supply Firebase configuration and manage `api_baseurl` |
| Firebase | External system | Collect diagnostics and return runtime configuration | Provide best-effort Analytics, Crashlytics, and Firestore config reads |

### User needs

- The user needs the app to start immediately with the last successfully fetched
  configuration; compile-time defaults apply until the first successful fetch.
- The operator needs Analytics and Crashlytics signals without raw pose/camera
  payloads or secrets.

### Preconditions

- A Firebase iOS project and externally supplied `GoogleService-Info.plist`
  exist for bundle `posing.camera.app` (project `camerapose-a0877`).
- **Baseline endpoint:** the iOS compiled default is
  `https://pose-extract-server-production.up.railway.app`. It is a routing
  control, not a secret; Firestore `config/app` can change it without a release.

### Trigger

The app launches, or the operator changes a field in Firestore document
`config/app`.

### Main flow

1. **Actor:** The App user launches the app. **System:** Firebase initializes
   when configuration is present, without blocking app launch indefinitely.
2. **Actor:** The App user waits for startup. **System:** The root appears immediately
   using a cached last-known payload, or compile-time defaults before the first successful
   fetch. A server-only Firestore read runs asynchronously with a 5-second endpoint update budget.
3. **Actor:** The App operator has published a valid configuration when needed.
   **System:** Valid `api_baseurl`, `account_enabled`, and
   `extractPoseEnabled` values are applied after first paint; the root is rebuilt
   only when an effective value changes.
4. **Actor:** The App user uses the app. **System:** Analytics emits sanitized
   lifecycle/configuration events and Crashlytics records bounded fatal/non-fatal
   diagnostics.

### Alternative flows

- **A1 — Firestore unavailable.** Source step: 2. Condition: fetch fails or the
  device is offline. Behavior: keep the current last-known payload; use compile-time
  defaults only if no fetch has succeeded before. Resume at step: 4.
- **A2 — Empty/invalid value.** Source step: 3. Condition: the fetched value is
  blank, malformed, or invalid. Behavior: use the compile-time endpoint default
  and the field-specific Boolean default. Resume at step: 4.
- **A3 — Endpoint correction.** Source step: 3. Condition: the operator
  publishes a corrected value. Behavior: apply it on the next app launch without
  requiring an app release. Resume at step: 3 on the next launch.

### Exception flows

- **E1 — Firebase setup missing.** Source step: 1. Failure: configuration is
  absent or unusable. Handling: skip Firebase-dependent behavior, keep the app
  launchable, and use the source endpoint. Prohibited: claiming a remote value
  was applied. Failure postcondition: no remote configuration is claimed.
- **E2 — API endpoint unavailable.** Source step: 2 or 3. Failure: the active
  endpoint cannot serve the API. Handling: the configuration read remains an
  independent Firestore request. Prohibited: creating a retry loop dependent on
  the dead endpoint. Failure postcondition: a valid endpoint remains selected.
- **E3 — Crashlytics upload unavailable.** Source step: 4. Failure: diagnostic
  upload cannot complete. Handling: keep diagnostics best effort. Prohibited:
  blocking app launch or local verification. Failure postcondition: app remains
  usable without claiming upload success.

### Postconditions

- **Success:** A valid runtime endpoint is selected before subsequent API calls
  and observability events contain only approved sanitized data.
- **Failure:** The app remains launchable with a valid fallback and exposes no
  false success about remote configuration or diagnostics.

## Requirements

- **FR-001:** Firebase initializes when its configuration is present and does
  not indefinitely block first app use.
- **FR-002:** Firestore `config/app` defines `api_baseurl`, `account_enabled`,
  and `extractPoseEnabled`; valid values update iOS runtime configuration after
  first paint.
- **FR-003:** Fetch failure or offline state preserves the last successfully fetched
  payload (or compile-time defaults before any successful fetch). Missing/invalid fields
  in a successful document use defaults (`api_baseurl`: production URL;
  `account_enabled`: `false`; `extractPoseEnabled`: `true`).
- **FR-004:** Analytics covers app start, endpoint source, and bounded app
  lifecycle events without raw pose images, camera frames, secrets, or payment
  data.
- **FR-005:** Crashlytics has a documented release dSYM path and remains best
  effort when upload/configuration is unavailable.
- **BR-001:** Firebase configuration and diagnostics never become a circular
  dependency on the pose API or expose credentials.
- **BR-002:** `PosesScreen.kt` and `Navigation.kt` remain outside this lane.

## Acceptance

- [ ] `api_baseurl` is defined once with the current endpoint as fallback.
- [ ] First paint does not wait for Firestore and resolves from last-known cache,
  falling back to compile-time defaults only before any successful fetch. Fetch failure
  preserves cache; missing or malformed fields in a successful response use field defaults.
- [ ] Late fetched values rebuild the root only when effective config changes.
- [ ] Analytics and Crashlytics degrade without blocking app launch and exclude
  sensitive payloads.
- [ ] dSYM handling is documented without archive, upload, or keychain work.
- [ ] No RevenueCat/paywall behavior or conflict-lane file is added to this
  Feature.

**Scenario: Firestore unavailable**
Given the device is offline or Firebase fetch fails  
When the app starts  
Then the last-known payload remains active; compile-time defaults are used only if no fetch
has ever succeeded, and the app remains launchable.

**Scenario: endpoint recovery**  
Given the current endpoint is unavailable and the operator publishes a valid
`api_baseurl`  
When the app next fetches the document
Then the new endpoint is applied without an app release.

## Relationships

- Decisions: [DEC-006 Firestore config policy](../decisions/DEC-006-remote-config-api-baseurl-policy.md) and [DEC-007 iOS SDK architecture](../decisions/DEC-007-ios-sdk-integration-architecture.md).
- Plan: [260826-0003 Firebase](../plans/260826-0003-integrate-firebase-observability-and-remote-config-for-feat-010/plan.md).
- Conflict boundary: `PosesScreen.kt` and `Navigation.kt` remain owned by the active `remove-my-poses-tab` lane.
