---
schema_version: 1
type: decision
id: DEC-006
title: Firestore config/app api_baseurl fallback and refresh policy
status: approved
created: 2026-08-25
approved: 2026-08-26
approved_by: Product Authority (PO)
relationships:
  specs:
    - "[[technical-architecture]]"
  decisions: []
  plans:
    - "[[260826-0003-integrate-firebase-observability-and-remote-config-for-feat-010/plan|260826-0003]]"
  reports: []
  rules: []
  features:
    - "[[FEAT-010-integrate-firebase-revenuecat|FEAT-010]]"
  source_paths:
    - mobile/iosApp/iosApp/Core/Network/AppConfig.swift
    - mobile/iosApp/iosApp/Core/Network/AppConfigService.swift
    - mobile/iosApp/iosApp/Core/Network/EndpointPolicy.swift
    - mobile/iosApp/iosApp/AppDelegate.swift
---

# DEC-006: Firestore `config/app` `api_baseurl` fallback and refresh policy

## Context

The iOS app maintains `AppConfig.shared.SERVER_BASE_URL` with a compile-time default
`https://pose-extract-server-production.up.railway.app`.

The app must be able to update a dead or relocated backend endpoint without requiring a binary
App Store release, while ensuring that network fetching never blocks first frame rendering.

The configuration source is Firestore document `config/app` (public read, without requiring
Firebase Auth sign-in).

## Decision

**Approved policy:** use Firestore document collection `config`, document `app` (`config/app`) with the
key `api_baseurl` and compile-time default `https://pose-extract-server-production.up.railway.app`.

1. **Immediate First Paint:** The root view is built immediately on launch from the last
   successfully fetched payload in UserDefaults. Before any successful fetch, compile-time
   defaults are used. First paint never awaits network or Firestore I/O.
2. **Asynchronous Resolution:** An asynchronous background task queries Firestore `config/app`
   within a bounded 5-second window (`StartupLatch`).
3. **Validation & Fallback:** Fetched and cached `api_baseurl` must be a valid non-empty
   HTTP/HTTPS URL. A successful fetch is cached as a whole payload. On fetch failure or offline,
   the app keeps the last successfully applied payload; compile-time defaults are used only before
   the first successful fetch. Missing or invalid fields in a successful payload use field defaults.
4. **Non-destructive Update:** If the fetched endpoint, account flag, or pose extraction flag differs
   from current values, the root is updated without showing empty frames.
5. **Additional Configuration Keys:**
   - `account_enabled`: Boolean/String, controls account surfaces (default `false`).
   - `extractPoseEnabled`: Boolean, controls pose extraction UI entry points (default `true`).

## Consequences

- The endpoint is resolved through `AppConfigService.resolvePayload`; the Firestore read is
  server-only and a local last-known successful payload provides synchronous startup values.
- First paint is guaranteed unblocked; late endpoint changes respect a 5s budget.
- Remote Config SDK is completely replaced by Firestore `config/app`.
