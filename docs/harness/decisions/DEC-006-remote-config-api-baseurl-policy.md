---
schema_version: 1
type: decision
id: DEC-006
title: Remote Config api_baseurl fallback and refresh policy
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
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/data/AppConfig.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseServiceLocator.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PosesScreen.kt
---

# DEC-006: Remote Config `api_baseurl` fallback and refresh policy

## Context

The app has two endpoint holders: `AppConfig.SERVER_BASE_URL` currently contains
the source default `https://specked-unhelpful-dispatch.ngrok-free.dev`, and
`PoseServiceLocator.baseUrl` is mutable and is captured by the lazy
`PoseServiceLocator.apiService`. `PosesViewModel.init` currently assigns the
former to the latter. If Remote Config is applied after the lazy API service is
constructed, changing the mutable property alone cannot update the already
constructed `PoseApiService`.

The app must be able to change a dead endpoint without a binary release, but the
endpoint switch must not make the pose API a prerequisite for obtaining the
configuration that can repair that endpoint.

**Baseline endpoint is provisional.** The compiled `AppConfig.SERVER_BASE_URL`
default (`https://specked-unhelpful-dispatch.ngrok-free.dev`) is a
**PROVISIONAL / TEMPORARY baseline selected by the Product Authority (PO)** for
local/development recovery testing. The former baseline in git history was the
Railway URL (`pose-extract-server-production.up.railway.app`); Railway may be
restored, or the ngrok URL replaced later, via Remote Config `api_baseurl`
without a binary release. The endpoint is a routing control, not a secret store.
It must not be treated as an immemorial constant — it is the current fallback,
not a value that was simply preserved unchanged.

## Decision

**Approved policy (2026-08-26, Product Authority/PO):** use the exact Remote Config key `api_baseurl` with the
current source endpoint as the compiled default. Resolve configuration in a
startup gate before rendering/constructing the first API-backed screen. The gate
must precede eager `communitySearchRepository` initialization and the
`PosesViewModel` default `coordinator` argument; a screen-level `init` is too
late:

1. Apply the source default immediately.
2. Hold the API-backed root in a configuration state so no `coordinator`,
   `repository`, or `apiService` access occurs before resolution.
3. Read the Firebase Remote Config activated cache (last-known-good value).
4. Validate a non-blank value as an allowed absolute endpoint; ignore blank,
   whitespace-only, malformed, or disallowed values.
5. Attempt one bounded `fetchAndActivate` at app start. The fetch uses Firebase
   only, never `PoseApiService`, and failure/offline/timeout proceeds immediately
   with the already applied cached/default value.
6. Apply the final value once, before `PoseServiceLocator.apiService` can be
   lazy-initialized, to both `AppConfig.SERVER_BASE_URL` and
   `PoseServiceLocator.baseUrl` through one runtime-config application path.
7. Use Firebase's persisted activated cache across launches; production refresh
   is throttled by the SDK (recommended minimum interval: 12 hours), while a
   debug/test override may use a shorter interval without changing production
   policy. A successful activation replaces the cached last-known-good value.

The source default remains the final fallback. The app does not retry or resolve
Remote Config through the configured pose endpoint, so a dead pose server cannot
create a dependency cycle.

## Alternatives

- **A — Startup gate with cached/default fallback (recommended):** deterministic
  first API construction and safe endpoint repair; adds a small startup state and
  bounded launch wait. Reversible by removing the gate.
- **B — Fetch in parallel after the app renders:** fastest first frame, but the
  lazy API service may capture the wrong endpoint and a mid-session switch needs
  service invalidation/reconstruction. Rejected for inconsistent runtime state.
- **C — Remote Config only in backend or environment variables:** simpler mobile
  code, but it cannot change an already released app's endpoint without release.
  Rejected because it misses the stated recovery goal.

## Consequences

- Both endpoint holders become runtime state rather than immutable compile-time
  state; tests must assert they are identical after each resolution outcome.
- Startup must expose a bounded loading/degraded state and never block forever
  on Firebase.
- A Remote Config value is a routing control, not a secret store. It must not
  contain tokens or credentials.
- The current `PosesViewModel` assignment becomes redundant and must not be the
  source of truth after this policy is implemented.

## Evidence

- **Observed:** `AppConfig.SERVER_BASE_URL` is defined in
  `mobile/composeApp/src/commonMain/kotlin/com/aipose/data/AppConfig.kt:4`.
- **Observed:** `PoseServiceLocator.baseUrl` and lazy `apiService` are defined in
  `mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseServiceLocator.kt:13,31-33`.
- **Observed:** `PosesViewModel.init` assigns `PoseServiceLocator.baseUrl` from
  `AppConfig.SERVER_BASE_URL` at
  `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PosesScreen.kt:165-167`.
- **Inferred:** applying Remote Config after lazy initialization would not
  reliably update the private base URL captured by `PoseApiService`.
- **Impact:** srcwalk direct structural impact for Kotlin is **UNKNOWN**; direct
  usage search found one `AppConfig` production use in `PosesScreen.kt` and
  multiple `PoseServiceLocator` consumers including `PoseApiService`, poses
  screens, Navigation, and Camera. GitNexus was not re-indexed per task scope.

## Supersession

This decision supersedes no earlier decision.
