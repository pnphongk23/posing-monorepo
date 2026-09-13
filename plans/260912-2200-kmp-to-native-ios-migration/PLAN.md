# PLAN_FINAL — KMP → Full Native iOS

Mission `m-kmp-to-native-ios`, lease epoch `1`, owner `43b52475-f2ed-40d0-b255-ac0def587e38`.

## Decision

Approaches considered: (A) repoint the existing `iosApp` executable to SwiftUI while retaining KMP as an out-of-target oracle; (B) add a second native executable; (C) bridge native screens to KMP. Choose A: one signing/configuration surface, rollback evidence, and a true native-only final target. Reject B for config drift and C for violating target isolation/AC5.

## Executable baseline and preflight

`mobile/iosApp/project.yml` is canonical; run `xcodegen generate --spec mobile/iosApp/project.yml` from repo root, with paths relative to `mobile/iosApp`. Worker 1 must create/restore this missing file before running XcodeGen, with: `name: iosApp`; iOS `15.0`; four configs `Debug-Dev`, `Release-Dev`, `Debug-Prod`, `Release-Prod`; one application target sourced only from `iosApp`; one unit-test target sourced from `iosAppTests`; `configFiles` mapped to the four `Config/*.xcconfig`; and schemes `Dev`/`Prod` mapped to matching run/test/profile/archive configs. Its package map must use exact versions: Firebase URL/tag `12.10.0` products `FirebaseCore`, `FirebaseAnalytics`, `FirebaseCrashlytics`, `FirebaseRemoteConfig`; RevenueCat URL/tag `5.87.1` product `RevenueCat`; GRDB URL/tag `v7.6.0` product `GRDB`. Set Swift 6 and commit `Package.resolved`. No target dependency may mention `ComposeApp`, Kotlin, CocoaPods, or Gradle.

Retain iOS 15; feature code must use `NavigationView` or availability gates, never an unguarded `NavigationStack`. Register `aipose://` in `Info.plist`. Include a non-secret `GoogleService-Info.plist` placeholder; runtime accepts only a valid environment plist, otherwise exposes disabled Firebase state, bounded Remote Config fallback, and no crash.

## SQLite safety contract

Before opening GRDB, inspect without creating files both `AiPoseDatabase.db` and `aipose.db` in this order: `Library/Application Support/databases`, `Library/Application Support`, `Documents`. Validate SQLite header plus required legacy tables/columns. Open exactly one valid candidate in place. Multiple valid candidates, malformed candidates, or unknown schema stop startup recoverably and never create a replacement. Only zero candidates permits creating `Library/Application Support/databases/aipose.db`. Migrations are additive, transactional, idempotent, and assert table info, indexes, foreign keys, `user_version`, row counts, IDs, paths, and snapshot JSON against SQLDelight.

## Ownership, verification, next action

Existing untracked drafts are worker inputs, not trusted code. Ownership is exclusive: W1 project/config/xcodeproj/AppDelegate/ContentView/Info/plist; W2 `Core/Database/**`, database tests/fixtures; W3 `Core/Network/**`, `OAuthHandoff.swift`, `RevenueCatAdapter.swift`; W4 `Core/Camera/**`, `Features/Camera/**`, `CameraViewController.swift`; W5 `Core/DesignSystem/**`, `Features/AppFeatureRoot.swift`, `Features/Poses/**`, `Features/Gallery/**`, `Features/Support/**`, feature tests. Pods/Podfile/Gradle/KMP stay untouched until final cleanup. W2’s fixture matrix must cover both filenames, all directories, no/ambiguous/malformed candidates, pre/post `PRAGMA` and schema parity, row/ID/path/JSON preservation, and reopen idempotence.

Gates: native tests; all four builds and both schemes; no-reference scan; copied-legacy-DB device upgrade rehearsal; prototype UI parity. Then create rollback artifact, remove KMP/Gradle/Pods, and archive. Risks remain `Pending-validation` for credentials, device DB location, and runtime parity; never claim AC2–AC4 without evidence. Next: obtain one fresh planning verdict, then dispatch W1 followed by W2–W5.
