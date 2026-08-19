# Design: FEAT-002 Local Photo Gallery (search, deletion, export — iOS delivery)

Plan `260819-0735-feat-002-local-photo-gallery` — authority for Cook after
Repository Maintainer approval. **FEAT-002 is `draft`** — this Plan cannot be
execution-approved until Product Authority approves the Feature (WI-01 records
the prerequisite and recommended FEAT-002 updates).

## Problem

FEAT-002 governs the local photo gallery. REP-002 GAP-004
(`PhotoRepository.kt:35-37` deletes the SQL row only; `PhotoDetailDialog.kt:169`
promises permanent deletion) shows deletion is incomplete. Four true deltas
close under this Plan:

1. **Search** — prototype `app.js:348-352` filters `title` OR `tag`
   (case-insensitive); production `GalleryScreen.kt` / `GalleryViewModel.kt`
   have **no** search (true delta).
2. **Deletion** — metadata-only delete; owned `imagePath` file and linked
   `PersonalPose` assets are left behind (BR-PHOTO-003 / FEAT-002 BR-001).
3. **Export** — `saveImageToPhotos` iOS actual has a false-success risk; no
   success confirmation in `GalleryScreen.kt`.
4. **UI** — prototype is a dense **3-column** grid; production is
   `GridCells.Fixed(2)`.

## Goals (IN)

- Gallery **title-tag search** filter (WI-02) per prototype `app.js:348-352`.
- **Atomic + recoverable photo deletion** with linked `PersonalPose` cascade
  (WI-03), matching the `PoseRepository.deletePose` pattern.
- **Save to Photos** export on **iOS** with a fixed false-success guard + success
  confirmation (WI-04).
- **Dense grid / detail UI parity** (WI-05) per `gallery.html` /
  `gallery-detail.html`.
- **DEC-004** iOS-scoped parity matrix (WI-01) and real-device **iPhone**
  verification (WI-06).

## Non-goals (OUT)

- Share sheet / generic file export (Save to Photos **only**).
- Server / HTTP gallery API (FEAT-002 owns none).
- Community pose management (FEAT-003/005/006).
- Modifying completed Plan `260809-2240` or REP-002 claims except as read-only
  evidence.
- FEAT-002 approval itself (owned by Product Authority — prerequisite only).
- **Android target / actuals** — deferred to a future FEAT-002 slice
  (Maintainer 2026-08-19, iOS-first); not in this Plan's Cook scope.

## True deltas (Cook may change)

| Delta | WI | Notes |
| --- | --- | --- |
| Gallery search state + filter + affordance | WI-02 | `app.js:348-352` semantics |
| Photo + PersonalPose atomic deletion | WI-03 | `PoseRepository.kt:39-58` pattern |
| Save to Photos iOS actual fix + success confirm | WI-04 | false-success guard |
| Dense 3-col grid parity | WI-05 | `grid.css:213-219` |
| DEC-004 matrix + device evidence | WI-01, WI-06 | iOS-scoped matrix + iPhone |

## Recommended approach

### 1. Search (WI-02) — **Option A (Maintainer 2026-08-19)**

Match prototype filter semantics (`app.js:348-352`): prototype `title` OR `tag`
(case-insensitive). Production maps **both** to pose-name text — no separate
title field and **no new DB tag column** in this slice.

**Filter contract:** case-insensitive **substring** match against:

1. `Photo.poseName` (primary), **and**
2. linked `Pose.name` when `Photo.poseId != null` (via join or lookup).

A photo matches when **either** field contains the query (OR semantics, mirroring
prototype title OR tag).

- Add `searchQuery` to `GalleryUiState`, filter `photos` before
  `groupPhotosByDate`, and add a search affordance to `GalleryScreen` (the
  prototype `gallery.html` has **no visible search input** — `app.js:384`
  removed the listener — so the affordance placement is a Cook/UI decision;
  semantics, not placement, are the authority).
- Empty-result state: reuse the "NO PHOTOS YET" / empty pattern with a
  "No photos found" message (prototype `app.js:355-363`).

### 2. Atomic deletion (WI-03) — **last-reference (Maintainer 2026-08-19)**

Lifecycle contract (Cook target):

1. Photo delete **always** removes the Photo DB row **and** the owned
   `imagePath` file.
2. When `Photo.poseId != null`, delete the linked `PersonalPose` (`Pose` row)
   and its owned assets (`imagePath`, `thumbnailPath`, `originalImagePath`)
   using the same owned-file + compensation pattern as
   `PoseRepository.deletePose` (`PoseRepository.kt:39-58`) **only if** no other
   `Photo` rows still reference that `poseId` after this delete.
3. **Last-reference rule:** use `getPhotosByPoseId` count; cascade when the
   count would become **0** after removing this Photo. If other Photos still
   reference the Pose, delete only this Photo — **do not** delete the shared
   Pose or its assets.
4. FK `ON DELETE SET NULL` (`Photo.sq:5`) is **not** relied upon — explicit
   orchestration only.
5. Atomic + recoverable: metadata-first or file-first with compensation; never
   report success while owned files remain (BR-001); partial failures
   recoverable (FEAT-002 E2).

`PhotoRepository` must gain (a) an injected storage boundary (reuse `PoseStorage`
or introduce a `PhotoStorage` with the same `isOwned`/`exists`/`delete`
contract) and (b) access to `Pose` queries (or a `PoseRepository` reference) for
the cascade and reference counting. The exact metadata/file ordering is Cook's
implementation choice within the contract; the reference metadata-first
ordering is `PoseRepository.deletePose`.

### 3. Save to Photos export (WI-04)

- Save to Photos **only** — no share sheet / generic file export.
- Verify/fix the iOS actual (`SaveToPhotos.ios.kt:9`); no Android work in this
  Plan.
- Add **success confirmation** (prototype `gallery-detail.html` shows
  "Saved to Photos."; production `GalleryScreen.kt` currently shows only
  "Save failed").
- Fix the iOS false-success risk: `success = true` is set inside the
  `performChangesAndWait` change block rather than its completion handler —
  a failed write may report success (REP-002 line 46).

**Android deferred (future prerequisite):** the build declares only iOS targets
(`composeApp/build.gradle.kts:10-12`, `shared/build.gradle.kts:9-11`). Android
parity would require adding an Android KMP target + AGP + `androidMain` source
sets + Android actuals for `saveImageToPhotos`, `getPlatformPoseStorage`, and
`DatabaseDriverFactory`, plus an Android app host — a **material
build-platform addition**, not a single actual function. Per Maintainer
decision (2026-08-19, iOS-first), Android is **deferred** to a future FEAT-002
slice. DEC-004 marks `E-ANDROID-TARGET` / `E-ANDROID` **Excluded** for this
Plan.

### 4. Dense grid / detail UI parity (WI-05)

- Dense 3-col grid: align `GridCells.Fixed(2)` → 3-col dense grid matching
  `nb-gallery-grid-dense` (`grid.css:213-219`, gap 3px).
- Detail: back, Save to Photos, delete modal are Aligned; export semantics are
  a Gap owned by WI-04.
- Grid/list toggle: production has it; prototype `gallery.html` omits a visible
  toggle (list CSS exists `grid.css:68-76`) — parity matrix labels this
  explicitly.

### 5. Evidence (WI-06)

Real **iPhone** device evidence is required in the final WI (Lead closed).
Android device evidence is **deferred** to a future FEAT-002 slice (no Android
target today). Evidence IDs cross-reference DEC-004 rows.

## Prototype mapping

| Prototype | Production | Plan |
| --- | --- | --- |
| `gallery.html` dense grid + scroll | `GalleryScreen.kt` | WI-05 |
| `app.js:348-352` filter | `GalleryViewModel.kt` + `GalleryScreen.kt` | WI-02 |
| `gallery-detail.html` save/delete/back | `PhotoDetailDialog.kt` | WI-03, WI-04, WI-05 |
| `card.css:174` `.nb-card--gallery-dense` | `PhotoCard` | WI-05 |
| `grid.css:213-219` `.nb-gallery-grid-dense` | `GridCells.Fixed(2)` | WI-05 |

## Dependencies

| Dependency | Role |
| --- | --- |
| FEAT-002 (**draft**) | Governing feature — **approval prerequisite** (Product Authority) |
| REP-002 GAP-004 | Gap evidence (read-only) |
| Plan 260809-1806 | Relationship only (camera convergence) — no `blockedBy` |
| Plan 260809-2240 WI-05 | Completed atomic PersonalPose deletion pattern (reference) |
| DEC-004 (proposed) | Parity matrix (this Plan's WI-01) |

## Risks

- **Android target scope:** deferred (Maintainer 2026-08-19, iOS-first); do not
  assume Android parity is one actual file — it is a build-platform addition
  owned by a future FEAT-002 slice.
- **Title/tag mapping:** closed — Option A (Maintainer 2026-08-19); substring on
  `Photo.poseName` + linked `Pose.name`.
- **Cascade multi-reference:** closed — last-reference rule (Maintainer
  2026-08-19); cascade only when `getPhotosByPoseId` count → 0.
- **iOS export false success:** `success = true` inside the change block may
  report success on failed write.
- **Claiming complete while owned files remain:** must never happen (BR-001).
