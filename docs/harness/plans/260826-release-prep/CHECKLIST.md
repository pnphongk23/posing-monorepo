# Mobile Release-Readiness Audit — 260826 Release Prep

- **Auditor:** Cam Ninh [Lính · executor] · **Reviewer/Lead:** Tướng quân (Gia Cát Cẩn)
- **Scope:** `mobile/` KMP (composeApp commonMain + iosApp), FEAT-010/FEAT-011 dirty work on top of HEAD `49a2eb3`.
- **Mode:** read-only audit. No code, build, or infra changed. Deliverable is this checklist only.
- **Testimony:** TestFlight **build 4** already uploaded & `VALID_BINARY`. No upload done here (forbidden).

---

## 1) OK / VERIFIED

| # | Item | Evidence | Notes |
|---|------|----------|-------|
| V1 | Firebase pods declared + lockfile in sync | `mobile/iosApp/Podfile` (+9) adds `FirebaseCore`, `FirebaseAnalytics`, `FirebaseCrashlytics`, `FirebaseRemoteConfig`; `Podfile.lock` pins all (Firebase 12.10.0) + `PODFILE CHECKSUM e65916ac...` + `COCOAPODS 1.16.2` at tail | Lock matches Podfile; no missing/stale podspecs observed |
| V2 | Pods installed on this machine | `mobile/iosApp/Pods/` populated (FirebaseCrashlytics, FirebaseCore, etc. present) | `.gitignore` keeps Pods out of VCS (expected) |
| V3 | Common & commonTest source sets wired | `mobile/composeApp/build.gradle.kts` `commonTest` deps: `kotlin("test")`, `libs.coroutines.test`, `libs.ktor.client.mock` | FIREBASE_SETUP gate target exists |
| V4 | New config/observability tests compile & PASS on dirty code | `./gradlew :composeApp:iosSimulatorArm64Test --rerun-tasks` → **BUILD SUCCESSFUL (53s)**; tasks `compileTestKotlinIosSimulatorArm64`, `linkDebugTestIosSimulatorArm64`, `iosSimulatorArm64Test` all ran | 5 new test files executed (EndpointPolicyTest, ResolveEndpointValueTest, RuntimeConfigResolverTest, StartupConfigApplyTest, EventSanitizerTest); zero failures |
| V5 | Deployment target vs Firebase requirement OK | `project.yml` + `project.pbxproj` `IPHONEOS_DEPLOYMENT_TARGET=15.0` (:272,:334); Firebase iOS 12.x min iOS ≥15 → no conflict | |
| V6 | App icon present (release needs no missing-icon fix) | `iosApp/Assets.xcassets/AppIcon.appiconset/` has 20/29/40/60/76/83.5/1024 pngs | |
| V7 | Native Firebase init is guarded & release-profile safe | `AppDelegate.swift` `tryConfigureFirebase()` validates API_KEY (`AIza` prefix), GOOGLE_APP_ID regex, and rejects any value containing `placeholder`/`example`; boots without Firebase if absent/invalid | Good defensive design |
| V8 | iOS bundle id matches plist bundle id | `project.pbxproj` `PRODUCT_BUNDLE_IDENTIFIER = camerapose.app` (:363,:386); `GoogleService-Info.plist` `BUNDLE_ID = camerapose.app` | Match confirmed |
| V9 | Endpoint precedence logic is unit-covered | `AppStartupConfig.resolveEndpointValue` (fetch→cache→default) tested; sanitizer allowlist tested | Pure logic, no I/O |
| V10 | No stray markers in new code | grep for `YOUR_|TODO|PLACEHOLDER|FIXME|HACK` over `config/`,`observability/`,`AppConfig.kt`,`PoseServiceLocator.kt` → none | |

## 2) MISSING / NEEDS WORK (owner)

| # | Item | Status | Evidence | Next action / owner |
|---|------|--------|----------|---------------------|
| M1 | **Default endpoint is a LOCAL DEV TUNNEL — must not ship** | **RELEASE BLOCKER** | `AppConfig.kt:11` and `PoseServiceLocator.kt:13` both default to `https://specked-unhelpful-dispatch.ngrok-free.dev` (HEAD had `pose-extract-server-production.up.railway.app`). Compile-time default / Remote-Config fallback now points at an ephemeral ngrok tunnel. | Lính: revert defaults to production railway URL (or confirm a production value is set in Firebase Remote Config **and** that the compile default is the purpose prod URL). Do **not** ship with ngrok default. |
| M2 | **CFBundleVersion stale vs TestFlight** | **NEEDS DECISION** | `iosApp/Info.plist:21` `CFBundleVersion=1`, `:19` `ShortVersion=1.0`; unchanged from HEAD and not bumped for the 4 in-flight builds. Re-uploading with CFBundleVersion `1` risks ASC rejection (build number already used). | Tướng quân: choose next build number (≥ current max used in ASC). Recommend `CFBundleVersion=4` to track build 4, or bump higher; keep ShortVersion `1.0`. Lính applies + re-archives. |
| M3 | **GoogleService-Info.plist NOT wired into the Xcode target** | **NEEDS BUILD-STEP** | `project.pbxproj` contains **0** references to `GoogleService` (grep count 0); Resources build phase (`A7F4C2D8E6B04913A5D7F1C2`) lists only `Assets.xcassets` + `LaunchScreen.storyboard`. The committed project is regenerated from `project.yml`, whose `resources:` also lists only those two. So `Bundle.main.url(forResource:"GoogleService-Info")` returns nil unless the project is (re)generated via **xcodegen** with the real plist on disk. | Lính: Release step must run `xcodegen` after placing the real plist so it is copied into the bundle; verify with `codesign`/`lsappinfo`/simulator that the file lands in the .app. |
| M4 | iOS **minimum-version doc drift** | Low | `build.gradle.kts` + `FIREBASE_SETUP.md` comment says "Kotlin 2.0.0"; actual wrapper is **Kotlin 1.9.20 / Gradle 8.5** (`./gradlew --version`). | Lính: fix stale comment or the toolchain mismatch — confirm which Kotlin the CI uses. |
| M5 | Crashlytics dSYM upload — CI step to set up (no CI today) | OWNER: CI/release-runner | Deferred in `FIREBASE_SETUP.md` "dSYM handling" → must run at release-archive time. Command shape: `pod download Firebase/Crashlytics` (or use installed `Pods/FirebaseCrashlytics/upload-symbols`), then `Pods/FirebaseCrashlytics/upload-symbols -gsp <GoogleService-Info.plist> -p ios <dSYMs dir>`. Requires Firebase CLI + `GOOGLE_APP_ID` at run time. Diagnostic-only — never blocks app launch. | Documented here; CI owner wires the step when CI exists. |

## 3) NEEDS PO ACTION (user must provide / confirm)

| # | Item | Status | Evidence | What PO/user must do |
|---|------|--------|----------|----------------------|
| P1 | **GoogleService-Info.plist authenticity** | **REQUIRED before ship** | A file `iosApp/iosApp/GoogleService-Info.plist` (878B, git-ignored) IS present with **real-looking** values: `API_KEY=AIzaSyCM3...`, `GOOGLE_APP_ID=1:624694870654:ios:64079f..., PROJECT_ID=camerapose-a0877`, `STORAGE_BUCKET=camerapose-a0877.firebasestorage.app`. The native guard treats this as valid, so **FirebaseApp.configure() will run**. If this is not a genuine download from the user's own Firebase console, Analytics/Crashlytics/RemoteConfig silently report to a project the team doesn't control. | PO/user: **confirm this plist was downloaded from their Firebase console for bundle id `camerapose.app`**, and that the API key / project are owned by the team. If in doubt, supply the real file (do not commit it). The `.example` is correctly a template. |
| P2 | **Firebase Remote Config `api_baseurl`** (production value) | **REQUIRED before ship** | Endpoint comes from RC key `api_baseurl` (`EndpointPolicy.REMOTE_CONFIG_KEY`); fallback is the (ngrok) compile default (M1). Scope/ownership of the RC key + whether it should be `https`, value sanitation. | PO/user: set/create `api_baseurl` to the **production** endpoint in the Firebase project; confirm ownership of the project that owns this key. |
| P3 | App Store developer credentials / signing for release archive | Required for App Store/TestFlight beyond existing build 4 | Not in repo. | PO/user: provide signing team for `camerapose.app` release build (assuming build 4 was signed by the same account). |

## 4) RISK / NOTES

| # | Item | Evidence | Mitigation |
|---|------|----------|-----------|
| R1 | ngrok default also appears as test fixture baseline | `EndpointPolicyTest.kt`, `ResolveEndpointValueTest.kt`, `RuntimeConfigResolverTest.kt` hardcode the ngrok URL as `default`. | Harmless in tests; ensure the *shipped* default (M1) is prod. Do not let test constants encourage a dev URL in src. |
| R2 | Pre-existing (non-FEAT) compile deprecation in SearchScreen | `SearchScreen.kt:256` uses deprecated `outlinedTextFieldColors` (Warning only). | Non-blocking; Tướng quân may backlog a fix. Not part of this dirty set. |
| R3 | ATS: EndpointPolicy allows `http://` endpoints | `EndpointPolicy.kt` allows scheme `http`/`https`. | If RC ever returns http, ATS blocks -> app falls back. Keep prod default `https`; no ATS exception declared (good). |
| R4 | Doc contradiction: Podfile comment says "composeApp KMP podspec declares same deps for cinterop" vs build.gradle comment says cinterop `pod()` **not** declared (Kotlin 2.0.0 can't parse Xcode 26.1 modulemap). | `Podfile` post-install comment vs `build.gradle.kts` cocoapods comment. | Native Swift bridge is the intended path; no action unless switching back to Kotlin cinterop. |
| R5 | Comment mentions "Kotlin 2.0.0" but toolchain is 1.9.20 | See M4 | Confirm intended Kotlin before release archive. |

---

## RELEASE GATE (must all be true before upload)

- [x] Build 4 validity — already `VALID_BINARY` (no action; do not re-upload platform binary here).
- [ ] **M1** Compile-time default & RC fallback point at a **production** endpoint (railway or approved prod), not ngrok.
- [ ] **P1** GoogleService-Info.plist confirmed as genuine & owned by the team (PO/user).
- [ ] **P2** Firebase Remote Config `api_baseurl` set to production in the correct project (PO/user).
- [ ] **M3** Release build regenerates project via `xcodegen` with the real plist so Firebase is bundled; verified in the archive.
- [ ] **M2** CFBundleVersion bumped to next available (≥ current build in ASC) to avoid rejection; ShortVersion confirmed (recommend `1.0`).
- [ ] **M5** Crashlytics dSYM upload step wired for the release archive.
- [x] **V4** Shared/starting-gate tests green on dirty code (`iosSimulatorArm64Test` BUILD SUCCESSFUL).
- [ ] **M4** Kotlin version doc/toolchain consistency confirmed before release.

**Overall: NOT RELEASE-READY as-is.** One hard code blocker (M1 ngrok default) + two PO confirmation gates (P1 plist authenticity, P2 RC value) + one build-step gap (M3 plist not wired unless xcodegen) + version bump (M2). Tests are green; Firebase wiring is otherwise well-guarded.