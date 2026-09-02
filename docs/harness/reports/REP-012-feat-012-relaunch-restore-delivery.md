---
schema_version: 1
title: FEAT-012 Relaunch Restore delivery
relationships:
  specs: []
  decisions: []
  plans:
    - "[[260831-0000-feat-012-relaunch-restore/plan|FEAT-012 Relaunch Restore]]"
  reports: []
  rules: []
  features:
    - "[[FEAT-012-restore-pose-and-camera-settings-across-relaunch|FEAT-012]]"
  source_paths:
    - mobile/shared/src/commonMain/sqldelight/com/aipose/CameraSnapshot.sq
    - mobile/shared/src/commonMain/sqldelight/com/aipose/1.sqm
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraSnapshotRepository.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraState.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt
    - mobile/composeApp/src/commonTest/kotlin/com/aipose/camera/CameraSnapshotIntegrationTest.kt
type: report
id: REP-012
status: completed
delivered: 2026-09-01
---

# REP-012: FEAT-012 Relaunch Restore delivery

## Delivered outcome

WI-01, WI-02, WI-03, and WI-04 are completed. FEAT-012 restores the pose identity and exactly eight camera setting groups across relaunch through the existing SQLDelight-backed persistence layer, while preserving capture/gallery behavior and verify-before-emit. WI-04 simulator evidence was accepted for this delivery; the physical cold-relaunch criterion remains Unresolved.

## Changed files

- `mobile/shared/src/commonMain/sqldelight/com/aipose/CameraSnapshot.sq` — singleton snapshot schema with `settings_json` and nullable `pose_json`.
- `mobile/shared/src/commonMain/sqldelight/com/aipose/1.sqm` — standard SQLDelight schema 1 → 2 migration; forward-only/no downgrade accepted for pre-release.
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraSnapshotRepository.kt` — persistence, independent settings/pose parsing, fallback, replace/clear pose-only updates.
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraState.kt` — pose-only state transformation preserving settings.
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt` — relaunch/clear/replace integration without stale `remember` recreation; zoom remains in `CameraZoomUiState`.
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt` — existing restore/bootstrap integration.
- `mobile/composeApp/src/commonTest/kotlin/com/aipose/camera/CameraSnapshotIntegrationTest.kt` — integration and clear/replace regression coverage.
- `docs/harness/plans/260831-0000-feat-012-relaunch-restore/design.md` and WI-01..WI-04 documents — approved contract, evidence, and corrected artifact attribution.

FEAT-011 was not changed by this delivery; its WI-04 remains blocked with the prior external-configuration reason.

## Verification evidence

All verification below was run against iOS Simulator `FEAT012-Test-iPhone`, UDID `6257BF4A-4EED-4421-AED1-C28606526D21`, iOS 26.1:

- `./gradlew :composeApp:linkDebugTestIosSimulatorArm64 --console=plain --no-daemon --stacktrace` — `BUILD SUCCESSFUL in 49s`; 15 actionable tasks (3 executed, 12 up-to-date).
- `./gradlew :composeApp:iosSimulatorArm64Test --tests 'com.aipose.camera.CameraSnapshotIntegrationTest' --console=plain` — `BUILD SUCCESSFUL in 1s`; 5 tests passed.
- `./gradlew :composeApp:iosSimulatorArm64Test --tests 'com.aipose.camera.CameraSnapshotRepositoryTest' --console=plain` — `BUILD SUCCESSFUL in 1s`; 6 tests passed.
- `./gradlew :composeApp:allTests --console=plain` — `BUILD SUCCESSFUL in 4s`; `:composeApp:iosX64Test SKIPPED` (not executed).
- `./gradlew :shared:iosSimulatorArm64Test --console=plain` — `BUILD SUCCESSFUL in 619ms`; 6 actionable tasks up-to-date.

XML artifacts (ignored build output, not versioned repository evidence):

- `/Users/phamnhuphong/Git/ai-pose/mobile/composeApp/build/test-results/iosSimulatorArm64Test/TEST-com.aipose.camera.CameraSnapshotIntegrationTest.xml` — `<testsuite name="com.aipose.camera.CameraSnapshotIntegrationTest" tests="5" skipped="0" failures="0" errors="0" timestamp="2026-09-01T06:23:57" hostname="MacBook-Air-cua-Pham.local" time="0.0">`
- `/Users/phamnhuphong/Git/ai-pose/mobile/composeApp/build/test-results/iosSimulatorArm64Test/TEST-com.aipose.camera.CameraSnapshotRepositoryTest.xml` — `<testsuite name="com.aipose.camera.CameraSnapshotRepositoryTest" tests="6" skipped="0" failures="0" errors="0" timestamp="2026-09-01T06:24:00" hostname="MacBook-Air-cua-Pham.local" time="0.044">`
- `/Users/phamnhuphong/Git/ai-pose/mobile/composeApp/build/test-results/iosSimulatorArm64Test/TEST-com.aipose.camera.CameraCoordinatorTest.xml` — `<testsuite name="com.aipose.camera.CameraCoordinatorTest" tests="26" skipped="0" failures="0" errors="0" timestamp="2026-09-01T06:23:57" hostname="MacBook-Air-cua-Pham.local" time="0.006">`
- `/Users/phamnhuphong/Git/ai-pose/mobile/composeApp/build/test-results/iosSimulatorArm64Test/TEST-com.aipose.platform.SaveToPhotosTest.xml` — `<testsuite name="com.aipose.platform.SaveToPhotosTest" tests="4" skipped="0" failures="0" errors="0" timestamp="2026-09-01T06:23:57" hostname="MacBook-Air-cua-Pham.local" time="0.0">`

`CameraSnapshotIntegrationTest` has 5 current tests; the historical 3-test description refers only to DTO mapping/bootstrap/invalid-transport tests. The all-eight-settings database round-trip is `CameraSnapshotRepositoryTest.freshSchemaCreatesSnapshotAndRoundTripsAllEightGroups`.

## Plan variance

No approved architecture, scope, schema decision, transport boundary, or simulator/physical decision was changed. Maintainer/user provenance is recorded verbatim: `Có iphone rồi đó. dùng simulator giúp tôi nhé`. The physical criterion is intentionally Unresolved, not a simulator substitute:

`Tôi không thể xác minh điều này hoạt động vì không có iPhone thật; chỉ có iOS Simulator`

Physical terminate-from-app-switcher → relaunch → Camera verification remains a follow-up.

## Repeated friction

Friction recorded: initial simulator-device absence, Gradle daemon/cache recovery after authorized cleanup, an invalid test fixture corrected during verification, and `iosX64Test SKIPPED` in the available allTests run. No physical iPhone semantic evidence or Compose UI harness evidence was available for this delivery.

## Decisions and review synthesis

Option 1 is the declared human decision: “choose Option 1, standard SQLDelight — add the snapshot table to the .sq schema plus migration file 1.sqm, upgrade schema 1 -> 2, runtime-managed by the existing SQLDelight driver, and accept forward-only/no downgrade because the app is pre-release.” The existing `AiPoseDatabase` SQLDelight driver owns the singleton snapshot; `PreparedPoseReference` remains read-only transport, no `ActivePoseReference` was created, and no new dependency or FK was added. Decision Peer `882186e7-28b6-4d56-99e2-52f31b2c0435` supported Option 1; `fa5e8bf4-bf6c-4315-9c8c-5b8cdda383fb` proposed runtime IF NOT EXISTS/reversible migration and is recorded as reasoned dissent, not adopted.

Review outcomes: `c79a2b97-49db-4401-b597-1e38cf78301e` Lê Quý Đôn correctness-evidence BLOCKER (real clear reset bug; fixed); `8979e40f-e056-4085-9549-ae6b64796e58` Nguyễn Trãi architecture-risk ACCEPTED; `09178b33-9258-4369-a627-b172aaeb2b71` Trần Hưng Đạo correctness-evidence REQUIRED (stale WI-04 count/timestamp; fixed); `2fed9381-e142-4939-a38e-530f3ae9df46` Hàn Tín architecture-risk NIT (pure seam/zoom tautology and lifecycle residuals; not blocking); closing `1e1c8a2e-8842-44c4-b017-74d5d70fe676` Lê Văn Hưu correctness-evidence ACCEPTED; `1de1c92f-acf3-41bd-96ce-f2dd1c0b482e` Trần Quốc Tuấn architecture-risk ACCEPTED.

Review budget: S=4/5 (cross-module source/docs/tests, roughly 6–10+ files), I=4/5 (persistence + SQLDelight migration), U=3/5 (physical follow-up and missing Compose UI/physical semantic evidence), R=11. Rationale: R=S+I+U=11; two reviewers were allocated to persistence/integration risk.

Remaining external dependencies: physical-device terminate/relaunch/Camera follow-up, and FEAT-011 user assets/configuration (2 App Store Connect IAP, RevenueCat offering/entitlement public key, sandbox tester, legal URLs). Do not resume FEAT-011; its WI-04 remains blocked with: `chờ external config từ user: 2 IAP App Store Connect, RevenueCat offering/entitlement public key, sandbox tester, legal URLs; resume khi user cấp`.
