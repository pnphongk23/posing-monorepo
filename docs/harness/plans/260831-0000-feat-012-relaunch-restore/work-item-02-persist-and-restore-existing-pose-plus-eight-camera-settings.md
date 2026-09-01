---
work_item: 2
title: Persist and restore existing pose plus eight camera settings
status: completed
priority: P2
effort: TBD
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 2: Persist and restore existing pose plus eight camera settings

## Tasks

- Dùng persistence layer hiện có để ghi snapshot single-device, có version/atomicity theo pattern đã có.
- Persist/restore pose identity hợp lệ và đúng tám nhóm settings; settings phải độc lập với pose.
- Rehydrate `PreparedPoseReference` khi locator hợp lệ; pose missing/corrupt thì clear pose portion và fallback settings, không crash.

## Scope and affected files

- Chỉ persistence implementation paths được WI-01 xác nhận và các consumer hiện có; `PreparedPoseReference` vẫn read-only transport.

## Success criteria

- Tests chứng minh round-trip đủ tám nhóm settings, pose optional, corrupt pose giữ settings, corrupt snapshot fallback an toàn.
- Không có runtime type mới thay `PreparedPoseReference`; không có dependency mới.

## Risks

- Partial write có thể làm pose locator không còn resolve được; atomic write và validation phải ngăn broken overlay.

## Required evidence

- Test names/paths, persistence path evidence, schema/version note trong `design.md` hoặc WI body, và targeted validation pass.

## Decision provenance

Repository Maintainer/user decided verbatim: “choose Option 1, standard SQLDelight — add the snapshot table to the .sq schema plus migration file 1.sqm, upgrade schema 1 -> 2, runtime-managed by the existing SQLDelight driver, and accept forward-only/no downgrade because the app is pre-release.” This decision is closed and is not reopened.

## Evidence

- Persistence: `mobile/shared/src/commonMain/sqldelight/com/aipose/CameraSnapshot.sq` and `1.sqm`; generated SQLDelight schema reports version 2 and migration 1→2.
- Implementation: `mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraSnapshotRepository.kt`; stores separate `PersistedCameraSettings` and `PersistedPoseIdentity`, never `CameraUiState` or `PreparedPoseReference`.
- Simulator tests: `mobile/composeApp/src/iosSimulatorArm64Test/kotlin/com/aipose/camera/CameraSnapshotRepositoryTest.kt`.
- Command: `./gradlew :composeApp:iosSimulatorArm64Test --tests 'com.aipose.camera.CameraSnapshotRepositoryTest' --rerun-tasks --console=plain` → `BUILD SUCCESSFUL`; 6 tests completed, 0 failures.
- Coverage: fresh schema; v1 fixture migration preserving Pose/Photo; all eight settings; optional pose; corrupt pose preserving settings; corrupt/partial/unknown payload fallback; replace/clear; no FK/transport-type leakage. Test databases use isolated random names and never `aipose.db`.
