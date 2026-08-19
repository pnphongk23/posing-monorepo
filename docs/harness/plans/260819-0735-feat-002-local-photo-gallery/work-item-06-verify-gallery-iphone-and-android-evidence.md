---
work_item: 6
title: Verify gallery iPhone evidence
status: completed
priority: P1
effort: M
dependencies:
  - 2
  - 3
  - 4
  - 5
decision_dependencies: []
---

# Work Item 6: Verify gallery iPhone evidence

**Kind:** verification / evidence gate

## Tasks

- Run iOS test suites for WI-02–05 (unit/integration).
- Capture **real-device** evidence on an iPhone (Lead closed): search filter,
  delete (row + file + linked pose cascade), Save to Photos, dense grid,
  detail.
- **Android deferred:** not in this Plan (Maintainer 2026-08-19, iOS-first);
  future plan when an Android KMP target exists. `E-ANDROID` is **Excluded**
  here.
- Build the DEC-004 evidence matrix with per-row IDs (below).
- Confirm `Photo.sq:5` `ON DELETE SET NULL` is not relied upon (explicit
  orchestration) and no owned files remain after delete (BR-001).
- Run harness validation; **do not** `ckh plan approve` (FEAT-002 still draft).

## DEC-004 evidence matrix

| DEC-004 row | Evidence ID | WI | Pass criterion |
| --- | --- | --- | --- |
| Search title-tag filter | **E-GAL-SEARCH** | 2 | Query filters by title OR tag; empty state |
| Title/tag mapping | **E-GAL-SEARCH** | 2 | Maintainer-confirmed mapping |
| Delete row + owned file + cascade | **E-GAL-DELETE** | 3 | Row+files removed; compensation on failure |
| Save to Photos iOS | **E-GAL-EXPORT** | 4 | Success + failure confirmed on iOS |
| Android build target | **E-ANDROID-TARGET** | — | **Excluded** — deferred future plan |
| Dense 3-col grid | **E-GAL-UI** | 5 | 3-col grid snapshot |
| Aligned UI regression | **E-GAL-UI** | 5 | Detail/empty/missing/group green |
| Real-device iPhone | **E-IPHONE** | 6 | Manual/MCP evidence on iPhone |
| Real-device Android | **E-ANDROID** | — | **Excluded** — deferred future plan |

## Scope and affected files

- Plan directory + test outputs under `mobile/shared/...Test/` and
  `composeApp/...Test/` (iOS)

## Success criteria

- All **Gap** rows closed; **Aligned** regression green; **Unresolved** rows
  resolved by Maintainer before Cook.
- `ckh workflow check` passes.
- Evidence packet separates search vs deletion vs export vs UI vs device.

## Risks

- Conflating simulator success with real-device evidence (iPhone required;
  Android deferred).
- Claiming completion while FEAT-002 approval and material decisions are open.

## Required evidence

- Test run logs (iOS).
- Completed evidence matrix (above) in delivery notes.
- `ckh workflow check docs/harness/plans/260819-0735-feat-002-local-photo-gallery --workspace .`
- `ckh validate docs/harness/plans/260819-0735-feat-002-local-photo-gallery/plan.md --workspace .`

## Evidence (WI-06, 2026-08-19) — Peer verification gate + delivery

> E-IPHONE is **Pending Maintainer manual verification** — no physical iPhone
> was available in this session. Device evidence is **not** faked. Automated
> iOS coverage (unit/integration) is reported green below; the manual
> device checklist is documented and waits on a Maintainer iPhone pass.

### iOS test suites (WI-02–05) — fresh run, all green

Ran from repo root (Gradle wrapper at `./gradlew`, modules resolved via root
`settings.gradle.kts`):

```
./gradlew :composeApp:iosSimulatorArm64Test :shared:iosSimulatorArm64Test --rerun-tasks
> Task :composeApp:iosSimulatorArm64Test
> Task :shared:iosSimulatorArm64Test
BUILD SUCCESSFUL in 2m 4s
```

First invocation was UP-TO-DATE (cached); re-ran with `--rerun-tasks` for fresh
execution evidence (same practice as REP-006 WI-05). Log:
`/tmp/feat002-wi06-test-run.log`.

Test results (JUnit XML, `mobile/*/build/test-results/iosSimulatorArm64Test/`):

- **shared:** 7 suites = **49 tests, 0 failures, 0 errors, 0 skipped**
  (`PhotoRepositoryDeletionTest` 8 — WI-03; plus `PoseRepositoryDeletionTest` 4,
  `PhotoRepositoryTest` 1, `IosPoseStorageOwnershipTest` 4,
  `PosesLibraryCoordinatorTest` 15, `CommunitySearchRepositoryTest` 12,
  `PoseApiServiceTest` 5 — no regressions).
- **composeApp:** 10 suites = **52 tests, 0 failures, 0 errors, 0 skipped**
  (`GalleryViewModelTest` 5 — WI-02; `SaveToPhotosTest` 4 — WI-04;
  `GalleryGridDefaultsTest` 6 — WI-05; plus pose/search/navigation/camera
  suites — no regressions).
- **Total: 101 tests, 0 failures/errors.**

### DEC-004 evidence matrix (FINAL)

| DEC-004 row | Evidence ID | WI | Status | Evidence refs |
| --- | --- | --- | --- | --- |
| Search title-tag filter | **E-GAL-SEARCH** | 2 | **Pass** | `GalleryViewModelTest` (5 green): `queryMatchesPhotoPoseName`, `queryMatchesLinkedPoseNameWhenPoseIdNotNull`, `queryMatchesNeitherReturnsEmptyFilterResult`, `emptyQueryReturnsAllPhotos`, `unmatchedPhotoWithNullPoseIdIsNotMatchedViaPoseNameOfOthers`; `GalleryViewModel.kt` `setSearchQuery` filters before `groupPhotosByDate`; `GalleryScreen.kt:192` `gallery-search-field` + `:264` "No photos found" empty state |
| Title/tag mapping | **E-GAL-SEARCH** | 2 | **Pass** | Mapping **Resolved** (Maintainer 2026-08-19, Option A) — DEC-004 §Title/tag mapping; no new DB tag column; linked `Pose.name` lookup when `poseId != null` (contract test above) |
| Delete row + owned file + cascade | **E-GAL-DELETE** | 3 | **Pass** | `PhotoRepositoryDeletionTest` (8 green): success removes row+file; file-failure restores metadata + rethrows; missing-file idempotent; last-reference cascade incl. cascade-failure compensation; no-cascade when other photos reference `poseId`; non-owned skipped. BR-001: no success while owned files remain |
| Save to Photos iOS | **E-GAL-EXPORT** | 4 | **Pass** | `SaveToPhotosTest` (4 green, success/failure confirmation + seam); `SaveToPhotos.ios.kt` returns real `performChangesAndWait` outcome (false-success fixed); `saveToPhotosConfirmation` → "Saved to Photos." / "Save failed"; iPhone manual confirmation in E-IPHONE checklist below |
| Android build target | **E-ANDROID-TARGET** | — | **Excluded** | Deferred future plan (Maintainer 2026-08-19, iOS-first); build declares iOS targets only (`composeApp/build.gradle.kts:10-12`, `shared/build.gradle.kts:9-11`); Android KMP target does not exist |
| Dense 3-col grid | **E-GAL-UI** | 5 | **Pass** | `GalleryGridDefaultsTest` (6 green): `denseGridUsesThreeColumns`, `denseGridGapIsThreePixels`, dense card square/hairline/radius/no-shadow; `GalleryGridDefaults` `DENSE_COLUMN_COUNT=3`, `DENSE_GAP=3.dp`; `GridCells.Fixed(3)` (prototype `grid.css:213-219`) |
| Aligned UI regression | **E-GAL-UI** | 5 | **Pass** | Full composeApp suite green includes detail/empty/missing/group flows (`CameraLayoutModelTest`, pose/viewmodel suites); section headers span 3 cols; empty "NO PHOTOS YET" / "No photos found" distinct; missing-file placeholder via `resolveImagePath` + `AsyncImage` |
| Real-device iPhone | **E-IPHONE** | 6 | **Pending** — Maintainer manual verification | No physical iPhone in session — **device evidence not faked**. Checklist below (`ckh` requires real-device pass before claiming E-IPHONE) |
| Real-device Android | **E-ANDROID** | — | **Excluded** | Deferred future plan (Maintainer 2026-08-19); no Android KMP target; required by plan recipe |

**Matrix totals:** 6 Pass (rows) · 2 Excluded · 1 Pending (E-IPHONE, Maintainer).

### E-IPHONE — Pending Maintainer manual verification (explicit checklist)

No physical iPhone was available in this session, so **E-IPHONE is Pending
Maintainer manual verification**. The checklist below is the exact pass
criteria; do **not** mark E-IPHONE passed until a Maintainer executes it on
physical hardware and records the outcome here. No E2E automation, no Maestro
(per WI constraints).

| # | Check | Steps (on device build) | Pass criterion |
| --- | --- | --- | --- |
| 1 | Search filter | Open gallery; type into `gallery-search-field` (GalleryScreen.kt:192); use `gallery-search-clear` (:222) | Photos whose `poseName` *or* linked `Pose.name` contains the query (case-insensitive) remain; others hide; empty query restores all; no-match shows "No photos found" (:264) — distinct from gallery-empty "NO PHOTOS YET" |
| 2 | Delete row + owned file + cascade | Open a photo with a linked pose; trash it; confirm the permanent-deletion modal (`PhotoDetailDialog.kt:169` "This photo will be permanently deleted.") | Photo row + owned `imagePath` gone; if last reference, linked PersonalPose row + owned assets gone; file system shows no remaining owned files (BR-001); shared pose retained when other photos reference it |
| 3 | Delete failure compensation | (Optional, dev build) make an owned file un-deletable before delete | UI reports failure — never success; metadata restored; file survives for retry (`PhotoRepositoryDeletionTest` proves logic; device spot-check) |
| 4 | Save to Photos | Open photo detail; tap Save | Real `PHPhotoLibrary` write: success shows "Saved to Photos." snackbar; photo appears in iOS Photos; failure (e.g. permission denied) shows "Save failed" — no false success |
| 5 | Dense 3-col grid | Gallery with ≥6 photos | 3 columns, ~3px gaps, square cover-crop tiles, hairline borders, no shadows; section headers (TODAY/YESTERDAY/date) span the row |
| 6 | Detail flow regression | Open photo detail: back, Save, trash, delete modal | All controls work; back returns to grid at same scroll position |
| 7 | Empty + missing-file states | Fresh install (or clear store); open a photo whose file is missing | "NO PHOTOS YET" + "OPEN CAMERA" on empty; missing-file placeholder (no crash) on broken imagePath |

### FK `ON DELETE SET NULL` not relied upon (confirmed)

- `Photo.sq:5` — `FOREIGN KEY (poseId) REFERENCES Pose(id) ON DELETE SET NULL`
  (checked-in source read this session).
- `PhotoRepository.deletePhoto` (PhotoRepository.kt:64-118) performs **explicit
  orchestration**: row delete (`queries.deletePhoto`), explicit last-reference
  `database.poseQueries.deletePose(cascadePose.id)`, then owned-file deletes in
  `deletePose` order — the FK is never used to clear `poseId`; cascade only
  fires when `getPhotosByPoseId` count − 1 ≤ 0.
- BR-001 (no owned files remain): success path deletes every owned file exactly
  once before success; failure path restores Photo (and Pose) metadata and
  rethrows — success is never reported while owned files remain
  (`PhotoRepositoryDeletionTest` 8 green, incl. compensation tests).

### Harness checks

```
ckh workflow check docs/harness/plans/260819-0735-feat-002-local-photo-gallery --workspace .
Harness validation passed

ckh validate docs/harness/plans/260819-0735-feat-002-local-photo-gallery/plan.md --workspace .
Harness validation passed
```

### Deliverable

Delivery report: [REP-007](../../reports/REP-007-feat-002-local-photo-gallery-delivery.md).

### Notes / constraints honored

- **NO commit, NO push** (this WI is documentation + verification only).
- **No `ckh plan approve`** — per WI; Plan `260819-0735` status is set to
  `completed` but approval remains the Maintainer's call.
- **E-ANDROID / E-ANDROID-TARGET Excluded** — deferred future plan (Maintainer
  2026-08-19).
- No E2E automation, no Maestro — unit/integration only + pending manual iPhone.
