---
work_item: 4
title: Verify cold relaunch on real iPhone and regression
status: completed
priority: P2
effort: TBD
dependencies:
  - 3
decision_dependencies: []
---

# Work Item 4: Verify cold relaunch on real iPhone and regression

## Tasks

- Chạy matrix cold relaunch: no pose, valid pose, corrupt pose; đủ tám nhóm settings; replace, clear, capture.
- Xác minh trên real iPhone: terminate từ app switcher, relaunch, mở Camera; lưu screenshot/log/accessibility evidence.
- Cập nhật verification ledger: chỉ chuyển `Unresolved` thành `Verified` khi có evidence; blocker phải ghi rõ.

## Scope and affected files

- Automated tests và device evidence cho FEAT-012; không sửa application code/test/source trong docs-only lane này.

## Success criteria

- Mỗi acceptance scenario có evidence hoặc trạng thái `Unresolved` kèm blocker cụ thể; không claim simulator thay cho real iPhone.
- Targeted checks/validation và regression evidence pass.

## Risks

- Simulator cold relaunch không chứng minh physical-device termination; thiếu real-iPhone evidence là blocker acceptance.

## Required evidence

- Test run log, real-iPhone screenshots/accessibility hoặc blocker note, verification ledger update, và `ckh workflow check` pass.

## Evidence — iOS Simulator

- Declared user decision provenance (verbatim): `Có iphone rồi đó. dùng simulator giúp tôi nhé`
- User decision: user hiện có iPhone thật nhưng chọn hoàn tất lần này bằng iOS Simulator; physical-device criterion remains `Unresolved` and may be verified later as a follow-up. Simulator evidence is not treated as a substitute for physical-device evidence.
- Device: `FEAT012-Test-iPhone`, UDID `6257BF4A-4EED-4421-AED1-C28606526D21`, runtime `iOS 26.1`, state `Shutdown` after test execution.
- Native simulator test command: `./gradlew :composeApp:iosSimulatorArm64Test :shared:iosSimulatorArm64Test --console=plain` → `BUILD SUCCESSFUL in 15s`, exit `0`.
- Matrix evidence (all labelled iOS Simulator): the historical grouping of 3 DTO mapping/bootstrap/invalid-transport tests is part of `CameraSnapshotIntegrationTest`; the current cycle-2 artifact contains 5 tests including the two corrective state/replacement regressions, XML `/Users/phamnhuphong/Git/ai-pose/mobile/composeApp/build/test-results/iosSimulatorArm64Test/TEST-com.aipose.camera.CameraSnapshotIntegrationTest.xml`, testsuite line `<testsuite name="com.aipose.camera.CameraSnapshotIntegrationTest" tests="5" skipped="0" failures="0" errors="0" timestamp="2026-09-01T06:23:57" hostname="MacBook-Air-cua-Pham.local" time="0.0">`; the database all-eight-settings round-trip belongs to `CameraSnapshotRepositoryTest.freshSchemaCreatesSnapshotAndRoundTripsAllEightGroups`, which contains 6 persistence tests including migration, corrupt/fallback, replace/clear, XML `/Users/phamnhuphong/Git/ai-pose/mobile/composeApp/build/test-results/iosSimulatorArm64Test/TEST-com.aipose.camera.CameraSnapshotRepositoryTest.xml`, testsuite line `<testsuite name="com.aipose.camera.CameraSnapshotRepositoryTest" tests="6" skipped="0" failures="0" errors="0" timestamp="2026-09-01T06:24:00" hostname="MacBook-Air-cua-Pham.local" time="0.044">`; `CameraCoordinatorTest` XML `/Users/phamnhuphong/Git/ai-pose/mobile/composeApp/build/test-results/iosSimulatorArm64Test/TEST-com.aipose.camera.CameraCoordinatorTest.xml`, testsuite line `<testsuite name="com.aipose.camera.CameraCoordinatorTest" tests="26" skipped="0" failures="0" errors="0" timestamp="2026-09-01T06:23:57" hostname="MacBook-Air-cua-Pham.local" time="0.006">`; `SaveToPhotosTest` XML `/Users/phamnhuphong/Git/ai-pose/mobile/composeApp/build/test-results/iosSimulatorArm64Test/TEST-com.aipose.platform.SaveToPhotosTest.xml`, testsuite line `<testsuite name="com.aipose.platform.SaveToPhotosTest" tests="4" skipped="0" failures="0" errors="0" timestamp="2026-09-01T06:23:57" hostname="MacBook-Air-cua-Pham.local" time="0.0">`. Zoom is not in `CameraUiState`; it is restored into `CameraZoomUiState` from `restoredSnapshot.settings.zoom`. XML files are build artifacts and are not claimed as versioned evidence. The automated evidence covers no-pose/default fallback and relaunch/bootstrap behavior; no physical lifecycle evidence is inferred.
- Physical terminate-from-app-switcher → relaunch → Camera scenario: `Unresolved`.

Tôi không thể xác minh điều này hoạt động vì không có iPhone thật; chỉ có iOS Simulator

Concrete blocker: terminate from the app switcher, relaunch, and opening Camera were not verified on a physical iPhone. This criterion remains open for a future physical-device follow-up.
