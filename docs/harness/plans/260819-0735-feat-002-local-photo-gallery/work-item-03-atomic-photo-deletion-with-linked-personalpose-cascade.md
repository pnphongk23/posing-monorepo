---
work_item: 3
title: Atomic photo deletion with linked PersonalPose cascade
status: completed
priority: P1
effort: L
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 3: Atomic photo deletion with linked PersonalPose cascade

**Kind:** story

## Tasks

- Give `PhotoRepository` a storage boundary (reuse `PoseStorage` or introduce a
  `PhotoStorage` with the same `isOwned`/`exists`/`delete` contract) and access
  to `Pose` queries (or a `PoseRepository` reference) for the cascade.
- Implement the lifecycle contract (**last-reference**, Maintainer 2026-08-19):
  1. Photo delete **always** removes the Photo DB row **and** the owned
     `imagePath` file.
  2. When `Photo.poseId != null`, delete linked `PersonalPose` + owned assets
     (`imagePath`, `thumbnailPath`, `originalImagePath`) using the
     `PoseRepository.deletePose` pattern **only if** no other `Photo` rows
     reference that `poseId` after this delete.
  3. Use `getPhotosByPoseId` count; cascade when count would become **0**. If
     other Photos still reference the Pose, delete only this Photo — do **not**
     delete the shared Pose or its assets.
  4. FK `ON DELETE SET NULL` (`Photo.sq:5`) is **not** relied upon.
  5. Atomic + recoverable: never report success while owned files remain
     (BR-001 / BR-PHOTO-003); partial failures recoverable (FEAT-002 E2).
- Restore metadata (Photo row and, if already deleted, Pose row) on any
  owned-file failure; rethrow so the UI reports failure, never success.
- Handle missing files idempotently (already-gone owned files are not an error).
- Add repository/storage integration tests: success removes row+files; file
  failure restores metadata and reports failure; missing file idempotent;
  cascade deletes linked pose assets when last reference; **no cascade** when
  other Photos still reference `poseId`; non-owned refs never deleted.

## Scope and affected files

- `mobile/shared/src/commonMain/kotlin/com/aipose/data/PhotoRepository.kt`
- `mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseRepository.kt` (or
  shared cascade helper)
- `mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseStorage.kt` (contract)
- platform actuals (iOS only; Android deferred — future plan)
- `mobile/shared/src/commonTest/...` (deletion integration tests)

## Success criteria

- Successful deletion removes Photo metadata + owned `imagePath`. When
  `poseId != null` and this Photo is the **last reference**, also removes linked
  Pose metadata + owned assets. When other Photos still reference the Pose,
  only this Photo is removed.
- Reported failure never leaves "success" state; metadata is restored or
  retained; no owned files leak on the failure path (BR-001).

## Risks

- **Last-reference semantics:** closed (Maintainer 2026-08-19). Tests must cover
  both last-reference cascade and shared-Pose retention paths.
- Storage ownership vs read-resolution base dir: deletion must resolve the same
  `Application Support/aipose` base as `resolveImagePath` / `IosPoseStorage`.

## Required evidence

- **E-GAL-DELETE**: integration tests (success, file-failure compensation,
  idempotent missing file, last-reference cascade, shared-Pose no-cascade,
  non-owned skip).
- Before/after DB + filesystem evidence; BR-001 no-success-while-file-remains.

## Evidence (WI-03, 2026-08-19)

### Atomic photo deletion with last-reference PersonalPose cascade

- `PhotoRepository` now takes a `PoseStorage` boundary
  (`storage: PoseStorage = getPlatformPoseStorage()`), reusing the same
  `isOwned`/`exists`/`delete` contract as `PoseRepository`; existing call sites
  (`PhotoRepository(database)`) are unchanged (defaulted parameter).
- `Photo.sq` gained `insertPhotoWithId` so a deleted Photo row can be restored
  with its original id after a partial failure (AUTOINCREMENT would otherwise
  assign a new id, breaking the UI's reference to the surviving item).
- `deletePhoto(id)` implements the Maintainer 2026-08-19 contract:
  1. Photo delete **always** removes the Photo DB row and the owned
     `imagePath` file (metadata-first, then files).
  2. When `photo.poseId != null`, the linked PersonalPose + owned assets
     (`originalImagePath`, `thumbnailPath`, `imagePath`) are cascade-deleted
     using the `PoseRepository.deletePose` pattern (primary image last) **only
     when** no other Photo rows reference that `poseId` after this delete
     (`getPhotosByPoseId` count − 1 ≤ 0). Otherwise only this Photo is
     deleted — the shared Pose and its assets stay untouched.
  3. FK `ON DELETE SET NULL` (`Photo.sq:5`) is **not** relied upon — the
     cascade is explicit orchestration.
  4. Atomic + recoverable (BR-001): owned files are deleted inside a guarded
     block; on any owned-file failure the metadata rows are restored
     (Pose row first so the restored Photo's `poseId` can reference it, then
     the Photo row) and the failure is rethrown — success is never reported
     while owned files remain.
  5. Missing owned files are idempotent: `isOwned` → `exists` → `delete`
     short-circuits before the filesystem, so already-gone files are not an
     error; non-owned refs (remote URLs / data URIs / traversal paths) never
     reach the filesystem.

### E-GAL-DELETE integration tests (unit/integration only — no E2E/UI)

`mobile/shared/src/iosSimulatorArm64Test/kotlin/com/aipose/data/PhotoRepositoryDeletionTest.kt`

```
./gradlew :shared:iosSimulatorArm64Test --tests "com.aipose.data.PhotoRepositoryDeletionTest"
> Task :shared:iosSimulatorArm64Test
BUILD SUCCESSFUL

TEST-com.aipose.data.PhotoRepositoryDeletionTest.xml
  tests="8" failures="0" errors="0" skipped="0"
  - testDeletionSuccessRemovesRowAndOwnedImageFile
  - testDeletionFileFailureRestoresMetadataAndRethrows
  - testDeletionMissingOwnedImageFileIsIdempotent
  - testDeletionLastReferenceCascadesToLinkedPoseAndAssets
  - testDeletionCascadeFileFailureRestoresPhotoAndPoseMetadata
  - testDeletionNoCascadeWhenOtherPhotosStillReferencePoseId
  - testDeletionSkipsNonOwnedReferences
  - testDeletionLastReferenceCascadeSkipsNonOwnedPoseAssets
```

Full `:shared:iosSimulatorArm64Test` suite also passes (no regression in
`PoseRepositoryDeletionTest`, `PhotoRepositoryTest`, etc.).

### BR-001 evidence (no success while owned files remain)

- Success path: `tests="8" failures="0"` — every owned file deleted exactly
  once (photo image last; pose assets in deletePose order) before success is
  reported.
- Failure path (`testDeletionFileFailureRestoresMetadataAndRethrows`,
  `testDeletionCascadeFileFailureRestoresPhotoAndPoseMetadata`): metadata rows
  restored (Photo and, when cascade was triggered, Pose) and the exception is
  rethrown — the UI reports failure, never success; the file that failed to
  delete survives for retry.

### `ckh workflow check`

```
Harness workflow check — see WI status ledger in work-item-03 header/status.
```
