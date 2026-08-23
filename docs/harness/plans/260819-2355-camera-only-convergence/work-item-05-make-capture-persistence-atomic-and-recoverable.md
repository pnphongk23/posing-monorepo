---
work_item: 5
title: Make capture persistence atomic and recoverable
status: pending
priority: P1
effort: L
dependencies:
  - 4
decision_dependencies: []
---

# Work Item 5: Make capture persistence atomic and recoverable

**Kind:** technical

## Tasks

1. Replace second-resolution filenames (`capture_{timestamp}.jpg`) with
   collision-resistant capture IDs (UUID v4 or monotonic counter + random suffix).
2. Define one image ownership/lifecycle contract shared with FEAT-002:
   - A file is "owned" when it was created by Camera capture and has exactly
     one metadata reference in `Photo.sq`.
   - Ownership is checked via `PoseStorage.isOwned()` (existing boundary).
   - FEAT-002 deletion respects ownership; this plan defines the write-side
     contract:
     - Camera **creates** files via `ImageStorage.writeJpeg` and **creates**
       metadata via `PhotoRepository.insertCapturedPhoto`.
     - Gallery **reads** metadata reactively and **deletes** via
       `PhotoRepository.deletePhoto` (owned by Plan `260819-0735`).
     - Camera never deletes files it did not create.
     - Gallery never creates files.
     - Each owned file has exactly one metadata reference in `Photo.sq`.
3. Implement atomic persistence orchestration:
   ```
   a. Receive non-empty encoded bytes + validated captureId
   b. Generate filename: capture_{captureId}.jpg
   c. Write file via ImageStorage.writeJpeg(bytes)
   d. Verify file is readable (exists + length > 0)
   e. Insert metadata via PhotoRepository.insertCapturedPhoto(path)
   f. If (d) fails → delete file, return Error
   g. If (e) fails → delete file (compensation), return Error
   h. Return inserted Photo record directly (not re-query latest)
   ```
4. Expose typed errors suitable for Camera UI recovery:
   - `PersistenceError.WriteFailure` — disk full or I/O error.
   - `PersistenceError.ReadVerificationFailed` — file exists but unreadable.
   - `PersistenceError.MetadataInsertFailed` — database error.
   - `PersistenceError.CompensationFailed` — cleanup failed; requires manual
     repair.
5. Never publish thumbnail state before both file and metadata are valid.
6. Add storage/repository/orchestration tests:
   - Successful capture → exactly one file + one metadata row.
   - Two rapid captures → two unique files, no overwrite.
   - File write failure → no metadata row, error returned.
   - Metadata insert failure → file deleted, error returned.
   - Read verification failure → file deleted, error returned.
   - Compensation failure → error returned with cleanup state.
   - Duplicate callback for same captureId → idempotent, no duplicate files.
7. Add capture→Gallery pipeline proof test:
   - Successful capture produces file + metadata record.
   - File is readable (exists + length > 0).
   - Metadata record has correct imagePath pointing to the created file.
   - Gallery's reactive query (`getAllPhotos`) would include this record.
   - Thumbnail state updates with the correct imagePath.
8. Add failure-never-claims-success test:
   - Inject file write failure → no metadata row, error returned, no thumbnail
     update.
   - Inject metadata insert failure → file deleted, error returned, no
     thumbnail update.
   - Verify no orphan files or metadata rows remain after any failure.

## Scope and affected files

- `mobile/shared/src/commonMain/kotlin/com/aipose/data/ImageStorage.kt`
- `mobile/shared/src/iosMain/kotlin/com/aipose/data/ImageStorage.kt`
- `mobile/shared/src/commonMain/kotlin/com/aipose/data/PhotoRepository.kt`
- `mobile/shared/src/commonMain/sqldelight/com/aipose/Photo.sq` (if schema changes
  needed for capture ID)
- Camera coordinator integration from Work Item 2.
- `mobile/shared/src/iosSimulatorArm64Test/kotlin/com/aipose/data/` (tests).

## Success criteria

- Successful capture produces exactly one unique readable file and exactly one
  matching metadata record, returned directly to UI state.
- Every injected failure leaves no newly broken record or orphan file; cleanup
  failure is observable and repairable rather than hidden.
- Two rapid captures cannot overwrite each other.
- Thumbnail is never published until file + metadata are both valid.
- Capture filename includes capture ID (not just timestamp).
- **Capture→Gallery proof:** successful capture provably produces a file +
  metadata record that Gallery's reactive query would display.
- **Failure never claims success:** every injected failure results in no
  thumbnail update and no false success state.
- **FEAT-002 ownership boundary defined:** write-side contract specifies
  Camera creates, Gallery reads/deletes; each owned file has exactly one
  metadata reference.

## Risks

- Filesystem and SQL database cannot share a native atomic transaction; the
  compensation order and crash-recovery marker must be explicit.
- FEAT-002 deletion owns the reverse lifecycle (Plan `260819-0735`); avoid
  incompatible duplicate policies and link follow-up work if outside this plan.
- UUID generation in Kotlin/Native may have platform-specific constraints.

## Required evidence

- Focused unit/integration test output.
- Temporary-storage artifact inspection (file exists, correct name, readable).
- SQL row assertions (exactly one row per capture).
- Two-rapid-capture test showing two unique files.
- Capture→Gallery pipeline proof (file + metadata + Gallery query match).
- Failure-never-claims-success test output (all failure paths).
- FEAT-002 ownership boundary documentation.
- Real-device readable-file plus metadata proof.
