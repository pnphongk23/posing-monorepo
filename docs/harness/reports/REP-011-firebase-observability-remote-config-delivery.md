---
schema_version: 1
type: report
id: REP-011
title: FEAT-010 Firebase observability + Remote Config delivery (iOS)
status: completed
delivered: 2026-08-26
relationships:
  specs: []
  decisions:
    - "[[DEC-006-remote-config-api-baseurl-policy|DEC-006]]"
    - "[[DEC-007-ios-sdk-integration-architecture|DEC-007]]"
  plans:
    - "[[260826-0003-integrate-firebase-observability-and-remote-config-for-feat-010/plan|260826-0003]]"
  reports: []
  rules: []
  features:
    - "[[FEAT-010-integrate-firebase-revenuecat|FEAT-010]]"
  source_paths:
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/data/AppConfig.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseServiceLocator.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/config/
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/observability/
    - mobile/iosApp/iosApp/AppDelegate.swift
    - mobile/iosApp/Podfile
    - mobile/composeApp/build.gradle.kts
---

# REP-011: FEAT-010 Firebase observability + Remote Config delivery (iOS)

## Delivered outcome

FEAT-010 (iOS-only) Firebase lane implemented and verified:

- **WI-01** — Authority/SDK configuration closed. Firebase iOS SDKs added to the
  existing CocoaPods lane; exact versions resolved by the toolchain and pinned in
  `Podfile.lock`. No new dependency manager, no Kotlin/toolchain upgrade.
- **WI-02** — Firebase bootstrap, Remote Config (`api_baseurl`), Analytics, and
  Crashlytics integrated. DEC-006 policy applied: source default → activated
  cache → bounded `fetchAndActivate` → validation → fallback, written once to
  both `AppConfig.SERVER_BASE_URL` and `PoseServiceLocator.baseUrl` before any
  API-backed state is constructed.
- **WI-03** — Fallback matrix, sanitized observability, and the unsigned iOS
  workspace build verified via the exact required gates.

**Baseline endpoint is provisional.** The compiled default
(`https://specked-unhelpful-dispatch.ngrok-free.dev`) is a **TEMPORARY baseline
selected by the PO** for recovery testing. The former baseline in git history
was the Railway URL (`pose-extract-server-production.up.railway.app`); Railway
may be restored or the ngrok URL replaced later via Remote Config `api_baseurl`
without a binary release. It is a routing control, not a secret, and was **not
simply preserved unchanged**.

## Scope decisions / architecture

**Current architecture (post-correction):** Firebase runs entirely in a
**native Swift Firebase bridge in `AppDelegate.swift`**. The Kotlin side
(`composeApp`) is a **pure contract/test seam only**: `EndpointPolicy.validate`,
`AppStartupConfig.resolveEndpointValue` (the single fetch→cache→default decision,
reused by Swift), and `AppStartupConfig.applyEndpoint` (the single write path for
both holders). `RemoteConfigFetcher`, `RuntimeConfigResolver`,
`AppStartupConfig.resolveAndApply`, `Observability`/`NoopObservability`, and their
tests are **pure Kotlin contract/test-only abstractions** — they do **not** run in
the production iOS path.

The plan originally assumed a Kotlin cinterop (`pod()`) bridge into Firebase. On
this toolchain (Kotlin **2.0.0** + **Xcode 26.1.1**, CocoaPods 1.16.2) the Kotlin
cocoa-pods cinterop cannot parse the Xcode 26.1 SDK modulemap
(`module '_c_standard_library_obsolete' requires feature 'found_incompatible_headers__check_search_paths'`).
This is a pre-existing Kotlin/Native vs SDK incompatibility, **not** a code error,
and is outside the approved scope (DEC-007 forbids uncontrolled dependency
upgrades; the Kotlin version was not changed). The production path was therefore
implemented in native Swift, which compiles with Xcode/clang and reuses the
pure-Kotlin validator + application path (verified against the generated
`ComposeApp` framework header). The DEC-006 endpoint contract remains
single-sourced and tested.

## Changed files

**Kotlin (composeApp / shared — Firebase scope only):**
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/data/AppConfig.kt` — `SERVER_BASE_URL` is now `var` (runtime state per DEC-006); source default preserved.
- `mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseServiceLocator.kt` — `communitySearchRepository` changed from eager to `by lazy` so touching the locator does **not** force `apiService` with the compiled default; the gate can apply the resolved endpoint first.
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/config/EndpointPolicy.kt` — `api_baseurl` key + URL validation (http/https, host allowlist, no creds/whitespace/control chars).
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/config/RemoteConfigFetcher.kt` — `FetchResult` sealed interface + `RemoteConfigFetcher` contract + `UnavailableRemoteConfigFetcher` no-op.
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/config/RuntimeConfigResolver.kt` — pure decision: `valid(fetch) ?: valid(cache) ?: default`.
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/config/AppStartupConfig.kt` — `applyEndpoint(url)` single path writing both holders; `resolveAndApply` orchestration retained for tests/future native fetchers.
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/observability/Observability.kt` — `Observability` interface, `NoopObservability`, `EventSanitizer` allowlist (keys `source/outcome/reason/duration_ms`, 100-char values, no URLs/spaces/secrets).
- `mobile/composeApp/src/commonTest/kotlin/com/aipose/config/` — `EndpointPolicyTest`, `RuntimeConfigResolverTest`, `StartupConfigApplyTest` (both holders equal after every outcome), `ResolveEndpointValueTest` (fetch→cache→default precedence; the exact decision the native Swift bridge delegates to).
- `mobile/composeApp/src/commonTest/kotlin/com/aipose/observability/EventSanitizerTest.kt`.

**Pure Kotlin contract/test-only abstractions (do not run in the production iOS
path):** `RemoteConfigFetcher` (+ `UnavailableRemoteConfigFetcher`),
`RuntimeConfigResolver`, `AppStartupConfig.resolveAndApply`, and
`Observability`/`NoopObservability` (plus their tests). The production iOS path is
the native Swift bridge in `AppDelegate.swift`, which reuses the shared
`EndpointPolicy.validate`, `AppStartupConfig.resolveEndpointValue`, and
`AppStartupConfig.applyEndpoint`.

**iOS native / manifests:**
- `mobile/iosApp/iosApp/AppDelegate.swift` — guarded `FirebaseApp.configure()` (plist presence + shape validation, rejects placeholder values); DEC-006 resolution that **captures the pre-fetch valid cache before `fetchAndActivate`**, **inspects `RemoteConfigFetchAndActivateStatus`** (treats the post-fetch value as fetched only on a success status AND when it validates), and delegates the fetch→cache→default decision to `AppStartupConfig.resolveEndpointValue`; a `didResolve` guard prevents double apply/show; sanitized `app_start` / `endpoint_resolved` Analytics events + Crashlytics breadcrumb; bounded (5s) startup timeout. All before the Compose root is created.
- `mobile/iosApp/Podfile` — Firebase `Core/Analytics/Crashlytics/RemoteConfig` pods (unpinned → resolved + pinned in `Podfile.lock`).
- `mobile/iosApp/Podfile.lock` — Firebase 12.10.0 (and transitive) pinned.
- `mobile/composeApp/build.gradle.kts` — Kotlin cinterop (`pod()`) is
  intentionally **not** used; Firebase resolution runs in native Swift
  (`AppDelegate.swift`). The Kotlin side is a pure contract/test seam (see
  architecture note above).
- `mobile/iosApp/iosApp.xcodeproj/project.pbxproj` — updated by `pod install` (CocoaPods maintenance, expected).
- Repository-root `.gitignore` — `GoogleService-Info.plist` ignored.
- `mobile/iosApp/iosApp/GoogleService-Info.plist.example` — template with obviously fake values (not bundled, not committed).
- `mobile/iosApp/FIREBASE_SETUP.md` — runbook: out-of-band config, dSYM, verification gates.

## Verification evidence

Exact gates (all PASS):

1. `./gradlew :composeApp:allTests --console=plain` → **BUILD SUCCESSFUL**.
   Executed on the booted iOS simulator (iPhone 16, iOS 26.0). **177 tests,
   0 failures, 0 errors** across all classes. FEAT-010 contract/test-seam tests:
   - `EndpointPolicyTest` — 10/10 pass
   - `RuntimeConfigResolverTest` — 8/8 pass (fetch/cache/default/unavailable/timeout/error/empty/malformed)
   - `EventSanitizerTest` — 6/6 pass (allowlist, truncation, no URL/space/secrets)
   - `StartupConfigApplyTest` — 3/3 pass (both holders identical after every outcome)
   - `ResolveEndpointValueTest` — 7/7 pass (fetch→cache→default precedence delegated to by the Swift bridge; invalid/empty/nil fetch never overwrites valid cache)
2. `./gradlew :composeApp:compileKotlinIosSimulatorArm64 --console=plain` → **BUILD SUCCESSFUL**.
3. `git diff --check` → **clean (exit 0)**, no whitespace/trailing errors.
4. `xcodebuild -workspace iosApp.xcworkspace -scheme iosApp -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build` → **BUILD SUCCEEDED** (ComposeApp framework + native Swift Firebase bridge, including the `RemoteConfigFetchAndActivateStatus`-inspecting resolution closure; an earlier attempt failed only on a corrupted `DerivedData` build database from a prior disk-full run, fixed by cleaning `DerivedData`).

Firebase cinterop note: the `pod()` Kotlin cinterop build (`cinteropFirebase*`)
was attempted early and failed solely on the Xcode 26.1 SDK modulemap
incompatibility described above; the production path is therefore native Swift.
The pure-Kotlin `EndpointPolicy.validate` + `AppStartupConfig.resolveEndpointValue`
+ `AppStartupConfig.applyEndpoint` seam is what the Swift bridge reuses and what
the common tests cover.

## srcwalk assess risk per symbol

- `App` (App.kt:22-60) — 0 name-matched callers in scope (entry from native `MainViewController`); adding the gate/loading state is additive. **Risk: low.**
- `AppConfig` (AppConfig.kt:3-5) — dotted `SERVER_BASE_URL` usage UNKNOWN to srcwalk (Kotlin property access not structurally resolved; matches DEC-006 evidence). `rg` textual confirm: single production reader at `PosesScreen.kt:167` (read-only). `const`→`var` is source-compatible. **Risk: low.**
- `PoseServiceLocator` (PoseServiceLocator.kt:12-52) — owner assess: 1 construction site (`PoseApiService`). Dotted `baseUrl`/`apiService` usage UNKNOWN per srcwalk; `rg` shows consumers: Navigation, CameraScreen, PosesScreen, SearchScreen, PoseDetailScreen. **Key risk (mitigated):** eager `communitySearchRepository` previously forced `apiService` at object-init with the compiled default. Fixed by making it `by lazy`, so the gate can set `baseUrl` before the API service is ever constructed. **Risk: low after fix.**
- `AppDelegate` (AppDelegate.swift:5-21 `@main`) — 0 in-repo callers; guarded configure + resolution is additive. **Risk: low.**
- New symbols (`EndpointPolicy`, `RuntimeConfigResolver`, `AppStartupConfig`, `Observability`, `EventSanitizer`, `RemoteConfigFetcher`) — new definitions, no blast radius; verified by compile + tests.
- `PoseApiService` — assess done (1 construction site); left untouched after a self-revert when a `baseUrl` visibility change was judged outside the approved PO boundary (per scope correction). Capture of the resolved endpoint is proven via ordering/behavior of `PoseServiceLocator` + the lazy-repo fix, not by editing `PoseApiService`.

## Credential / security audit

- No real `GoogleService-Info.plist`, Firebase API key, private key, or dSYM secret created or committed. `GoogleService-Info.plist.example` contains obviously fake values and is never bundled; the real file is git-ignored and supplied out of band.
- Analytics events use only the sanitized allowlist (`source/outcome/reason/duration_ms`); no pose/camera/payment payloads, URLs, or tokens can reach Firebase (Kotlin `EventSanitizer` + Swift value guard).
- Crashlytics breadcrumb is `endpoint_source=<source>` only.
- No claim of production Analytics/Crashlytics activity: Firebase is skipped whenever the plist is missing/placeholder (AppDelegate validation), so on this machine it reports unavailable truthfully.

## Conflict-boundary audit

- `mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PosesScreen.kt` — **not modified by this cook**. It carries a pre-existing dirty diff from another lane (Community header title/layout); this cook did not touch or revert it. The `PosesViewModel.init` assignment `PoseServiceLocator.baseUrl = AppConfig.SERVER_BASE_URL` remains, harmless because the gate writes both holders to the same resolved value before composition.
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt` — **not modified by this cook**.
- No RevenueCat / FEAT-011 / DEC-008 work performed.
- Dirty worktree preserved: unrelated pre-existing modifications (`.agent/*`, `web/*`, `docs/harness/index.md`, `web/admin-ui/*`, `web/services/*`) were not touched; staged count = 0; HEAD unchanged (`3d343d1b…`).

## Plan variance

- **Architecture (current):** native Swift Firebase bridge in `AppDelegate.swift`;
  Kotlin side is a pure contract/test seam. The early Kotlin cinterop attempt
  failed only on the Xcode 26.1 SDK modulemap incompatibility (Kotlin 2.0.0),
  which is why the production path is Swift. Behaviorally equivalent and fully
  tested on the Kotlin side; Swift reuses the same pure-Kotlin validator and
  application path.
- No Firebase `pod()` declarations were added to `build.gradle.kts` (comment
  explains why). All Firebase resolution runs in Swift.

## Limitations

- Live Firebase path (real `GoogleService-Info.plist` + `fetchAndActivate` network call + Analytics/Crashlytics upload) is **not** executed here: no real config is present and credentials must never be committed. Correctness of the Firebase-wired path is established by (a) the unsigned workspace **BUILD SUCCEEDED** against the real Firebase 12.10.0 pods, (b) exact-symbol verification against the generated `ComposeApp` header (`AppStartupConfig.shared.applyEndpoint(url:)`, `AppConfig.shared.SERVER_BASE_URL`, `EndpointPolicy.shared.validate(raw:)`), and (c) the Kotlin fallback/validation/ordering logic which is unit-tested. The runtime Firebase branch is exercised only when a real plist is dropped into the bundle out of band.
- dSYM upload is a CI/release concern documented in `FIREBASE_SETUP.md`; not run locally (no archive/upload per scope).

## Corrections applied (PO-approved Khổng Minh review)

All five corrections were implemented in this cook session and re-verified by the
exact gates (see Verification evidence). No scope expansion; no commit/stage/push.

1. **Real code fix (shipped Swift matches tested Kotlin contract).**
   `AppDelegate.swift` now captures the pre-fetch valid cache **before**
   `fetchAndActivate`, inspects `RemoteConfigFetchAndActivateStatus` (treats the
   post-fetch value as fetched only on a success status AND when it validates),
   and delegates the fetch→cache→default decision to the pure Kotlin
   `AppStartupConfig.resolveEndpointValue`. An invalid/empty/nil fetch never
   overwrites a valid cache. A `didResolve` guard prevents double apply/show;
   all UI work stays on the main queue; resolution/apply precede root creation.
   Coverage: new `ResolveEndpointValueTest` (7/7) exercises the exact precedence
   the Swift bridge delegates to, so Kotlin-only tests DO cover the Swift closure.
2. **Plan execution status closed.** `ckh plan set-status … --status completed`
   (see below); realization/evidence recorded in this report.
3. **Provisional baseline documented.** `FEAT-010`, `DEC-006`, and this report
   now state the ngrok `SERVER_BASE_URL` is a **TEMPORARY baseline selected by
   the PO**; Railway was the former baseline in git history and ngrok may be
   replaced later via Remote Config. No claim that the source default was simply
   preserved.
4. **cinterop → native Swift wording.** `mobile/iosApp/FIREBASE_SETUP.md`, the
   `build.gradle.kts` comment (removed the stale `FirebaseConfigBridge.swift`
   reference), this report, `FEAT-010`, and `DEC-007` now describe a **native
   Swift Firebase bridge in `AppDelegate.swift`** with the Kotlin side as a
   **pure contract/test seam only**. Unrelated generic KMP references untouched.
5. **Pure-Kotlin abstractions labeled.** `RemoteConfigFetcher`,
   `RuntimeConfigResolver`, `AppStartupConfig.resolveAndApply`, and
   `Observability`/`NoopObservability` (plus their tests) are documented as
   **pure Kotlin contract/test-only**; the production iOS path is the native
   Swift bridge, which reuses `EndpointPolicy.validate`, `resolveEndpointValue`,
   and `applyEndpoint`.
