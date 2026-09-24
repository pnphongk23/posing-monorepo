---
schema_version: 1
title: Integrate Firebase observability and Remote Config recovery
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
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/App.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/data/AppConfig.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseServiceLocator.kt
    - mobile/iosApp/Podfile
    - mobile/iosApp/iosApp/AppDelegate.swift
    - mobile/iosApp/project.yml
type: feature
id: FEAT-010
status: approved
created: 2026-08-25
approved: 2026-08-26
approved_by: Product Authority (PO)
---

# FEAT-010: Integrate Firebase observability and Remote Config recovery

## Introduction

**Purpose:** Give the iOS app production observability and a recoverable runtime
endpoint switch without making Firebase availability a prerequisite for app
startup or API recovery.

**Roadmap note:** This Feature covers technical observability/configuration only;
paid access and RevenueCat behavior are owned by FEAT-011.

**In scope:** Firebase Analytics, Crashlytics, Remote Config, the exact
`api_baseurl` key, default/cache/fetch fallback behavior, sanitized event
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
| Firebase | External system | Collect diagnostics and return runtime configuration | Provide best-effort Analytics, Crashlytics, and Remote Config services |

### User needs

- The user needs the app to start with a valid source default or last-known-good
  endpoint when Firebase is missing, offline, unavailable, or malformed.
- The operator needs Analytics and Crashlytics signals without raw pose/camera
  payloads or secrets.

### Preconditions

- A Firebase iOS project and externally supplied `GoogleService-Info.plist`
  exist for bundle `posing.camera.app` (project `camerapose-a0877`).
- The current source endpoint remains the fallback until an approved migration.
- **Baseline endpoint is provisional:** the compiled default
  (`https://specked-unhelpful-dispatch.ngrok-free.dev`) is a **TEMPORARY
  baseline selected by the PO** for recovery testing. The former baseline in git
  history was the Railway URL; ngrok may be replaced later (via Remote Config)
  without a release. It is a routing control, not a secret, and was not simply
  preserved unchanged.

### Trigger

The app launches, or the operator changes the Remote Config value for
`api_baseurl`.

### Main flow

1. **Actor:** The App user launches the app. **System:** Firebase initializes
   when configuration is present, without blocking app launch indefinitely.
2. **Actor:** The App user waits for startup. **System:** Remote Config applies
   the source default or activated cache, then performs a bounded fetch/activate.
3. **Actor:** The App operator has published a valid configuration when needed.
   **System:** A valid non-empty `api_baseurl` becomes the runtime endpoint for
   both endpoint holders before the first API service is constructed.
4. **Actor:** The App user uses the app. **System:** Analytics emits sanitized
   lifecycle/configuration events and Crashlytics records bounded fatal/non-fatal
   diagnostics.

### Alternative flows

- **A1 — Cached endpoint.** Source step: 2. Condition: fetch fails or the
  device is offline. Behavior: use the last activated valid endpoint, or the
  source default when no cache exists. Resume at step: 3.
- **A2 — Empty/invalid value.** Source step: 3. Condition: the fetched value is
  blank, malformed, or invalid. Behavior: ignore it and retain the valid
  fallback. Resume at step: 4.
- **A3 — Endpoint correction.** Source step: 3. Condition: the operator
  publishes a corrected value. Behavior: apply it on the next bounded refresh
  without requiring an app release. Resume at step: 3 on the next refresh.

### Exception flows

- **E1 — Firebase setup missing.** Source step: 1. Failure: configuration is
  absent or unusable. Handling: skip Firebase-dependent behavior, keep the app
  launchable, and use the source endpoint. Prohibited: claiming a remote value
  was applied. Failure postcondition: no remote configuration is claimed.
- **E2 — API endpoint unavailable.** Source step: 2 or 3. Failure: the active
  endpoint cannot serve the API. Handling: do not fetch Remote Config through
  the pose API and retain the fallback. Prohibited: creating a retry loop
  dependent on the dead endpoint. Failure postcondition: a valid fallback remains
  selected.
- **E3 — Crashlytics upload unavailable.** Source step: 4. Failure: diagnostic
  upload cannot complete. Handling: keep diagnostics best effort. Prohibited:
  blocking app launch or local verification. Failure postcondition: app remains
  usable without claiming upload success.

### Postconditions

- **Success:** Both runtime endpoint holders agree before first API use and
  observability events contain only approved sanitized data.
- **Failure:** The app remains launchable with a valid fallback and exposes no
  false success about remote configuration or diagnostics.

## Requirements

- **FR-001:** Firebase initializes when its configuration is present and does
  not indefinitely block first app use.
- **FR-002:** Remote Config defines exactly `api_baseurl` and applies a valid
  value consistently to `AppConfig.SERVER_BASE_URL` and
  `PoseServiceLocator.baseUrl` before first API use.
- **FR-003:** Fetch failure, offline state, empty value, invalid value, or
  missing Firebase configuration falls back to last valid cache, then source
  default.
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
- [ ] Default, cache, valid fetch, offline/failure, empty, malformed, and
  dead-endpoint recovery scenarios preserve a valid endpoint.
- [ ] Endpoint holders are equal before the first API service construction.
- [ ] Analytics and Crashlytics degrade without blocking app launch and exclude
  sensitive payloads.
- [ ] dSYM handling is documented without archive, upload, or keychain work.
- [ ] No RevenueCat/paywall behavior or conflict-lane file is added to this
  Feature.

**Scenario: Remote Config unavailable**  
Given the device is offline or Firebase fetch fails  
When the app starts  
Then the last valid cache or source default is used and the app remains launchable.

**Scenario: endpoint recovery**  
Given the current endpoint is unavailable and the operator publishes a valid
`api_baseurl`  
When the bounded refresh runs  
Then the new endpoint is applied consistently without an app release.

## Relationships

- Decisions: [DEC-006 Remote Config policy](../decisions/DEC-006-remote-config-api-baseurl-policy.md) and [DEC-007 iOS SDK architecture](../decisions/DEC-007-ios-sdk-integration-architecture.md).
- Plan: [260826-0003 Firebase](../plans/260826-0003-integrate-firebase-observability-and-remote-config-for-feat-010/plan.md).
- Conflict boundary: `PosesScreen.kt` and `Navigation.kt` remain owned by the active `remove-my-poses-tab` lane.
