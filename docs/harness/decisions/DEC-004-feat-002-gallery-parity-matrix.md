---
schema_version: 1
type: decision
id: DEC-004
title: FEAT-002 Gallery Parity Matrix (search, deletion, export — iOS)
status: approved
created: 2026-08-19
approved: 2026-08-19
approved_by: Repository Maintainer
relationships:
  specs:
    - "[[ui-ux-system]]"
    - "[[product-feature-inventory]]"
    - "[[model-entity-catalogue]]"
    - "[[erd]]"
  decisions:
    - "[[DEC-003-feat-003-scoped-parity-matrix|DEC-003]]"
  plans:
    - "[[260819-0735-feat-002-local-photo-gallery/plan|260819-0735]]"
    - "[[260809-1806-camera-source-of-truth-convergence/plan|260809-1806]]"
  reports:
    - "[[REP-002-feature-gap-and-release-readiness-audit|REP-002]]"
  rules: []
  features:
    - "[[FEAT-002-manage-a-local-photo-gallery|FEAT-002]]"
  source_paths:
    - docs/prototype/screens/gallery.html
    - docs/prototype/screens/gallery-detail.html
    - docs/prototype/scripts/app.js
    - docs/prototype/scripts/fixtures.js
    - docs/prototype/styles/components/card.css
    - docs/prototype/styles/components/grid.css
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PhotoRepository.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseRepository.kt
    - mobile/shared/src/commonMain/sqldelight/com/aipose/Photo.sq
    - mobile/shared/src/commonMain/sqldelight/com/aipose/Pose.sq
    - mobile/composeApp/src/iosMain/kotlin/com/aipose/platform/SaveToPhotos.ios.kt
---

# FEAT-002 Gallery Parity Matrix (search, deletion, export — iOS)

Scope boundary for Plan `260819-0735-feat-002-local-photo-gallery`. Rows marked
**Excluded** are intentionally out of Plan acceptance. This matrix documents
parity for **new** work under FEAT-002, scoped to **iOS delivery** (Maintainer
2026-08-19) — Android is **Excluded** / deferred to a future FEAT-002 slice.
**FEAT-002 is `draft`** — this DEC is `proposed` and the owning Plan cannot be
execution-approved until Product Authority approves the Feature. WI-01 records
the matrix.

## Parity matrix

| Requirement / Scenario | Prototype | Production target | Status for this Plan |
| --- | --- | --- | --- |
| **FR-001** Reactive gallery list | `gallery.html` grid + `app.js` render | `GalleryScreen.kt` + `GalleryViewModel.load()` reactive flow | **Aligned** — regression WI-05 |
| **Dense grid** | `gallery.html` `nb-gallery-grid-dense` (`grid.css:213-219`, 3-col, gap 3px) | `GalleryScreen.kt` `GridCells.Fixed(2)` | **Gap** — 3-col dense WI-05 |
| **Grid/list toggle** | `gallery.html` (no visible toggle; list CSS `grid.css:68-76`) | `gallery-grid-toggle` / `gallery-list-toggle` | **Partial** — production toggle retained; prototype gallery omits UI — WI-05 |
| **Group headers** | `nb-grid-group-title` (`grid.css:40-56`) | `SectionHeader` + `groupPhotosByDate` (TODAY/YESTERDAY/MONTH DAY) | **Aligned** — regression WI-05 |
| **Empty gallery** | prototype empty tip | `GalleryScreen.kt` "NO PHOTOS YET" + "OPEN CAMERA" | **Aligned** — regression WI-05 |
| **Search: title OR tag filter** | `gallery.html` (NO search bar; Date-first navigation) | `GalleryScreen.kt` | **Superseded / Removed** (Product Authority 2026-09-10) — Aligned with prototype `gallery.html` & `SCR-002-01` |
| **Search: field mapping (Option A)** | N/A (search bar removed from Gallery UI) | `GalleryViewModel.kt` | **Superseded** — UI text search removed; date filtering is authority |
| **Detail back / save / delete** | `gallery-detail.html` back + `gallery-save-btn` + `gallery-delete-btn` + modal | `PhotoDetailDialog.kt` back / Save / trash + `AlertDialog` | **Aligned** (controls); export semantics **Gap** — WI-05 / WI-04 |
| **Delete: metadata + owned file** | `gallery-detail.html` "permanently deleted" | `PhotoRepository.deletePhoto` row only (`PhotoRepository.kt:35-37`) | **Gap** — WI-03 |
| **Delete: linked PersonalPose cascade** | N/A (prototype has no pose link) | last-reference: cascade when `getPhotosByPoseId` count → 0 after delete | **Gap** — WI-03 (last-reference, Maintainer 2026-08-19) |
| **FK orchestration** | N/A | `Photo.sq:5` `ON DELETE SET NULL` | **Boundary** — explicit orchestration, not cascade — WI-03 |
| **Export: Save to Photos (iOS)** | `gallery-detail.html` "Saved to Photos." | `SaveToPhotos.ios.kt:9` actual | **Partial** — no success confirmation; false-success risk — WI-04 |
| **Export: Save to Photos (Android)** | N/A | `SaveToPhotos.kt:3` `expect` only | **Excluded** — deferred (future plan after Android target) |
| **Export: share sheet / generic file** | N/A | N/A | **Excluded** — Save to Photos only |
| **Server gallery API** | N/A | none (local only) | **Excluded** — no HTTP endpoint |
| **FEAT-001 capture handoff** | `camera` flow (FEAT-001) | `CameraScreen.kt` → `insertCapturedPhoto` | **Excluded** — owned by FEAT-001 / Plan 260809-1806 |
| **BR-001 no complete while owned file remains** | N/A | `PhotoRepository.deletePhoto` | **Gap** — WI-03 |
| **Missing-file E1 placeholder** | `gallery-detail.html` unavailable state | `resolveImagePath` + `AsyncImage` | **Aligned** — regression WI-05 |
| **Real-device evidence (iPhone)** | N/A | iPhone | **Gap** — WI-06 |
| **Real-device evidence (Android)** | N/A | Android (no target today) | **Excluded** — deferred to future plan |

## Material scope decisions

1. **Search in Gallery REMOVED / SUPERSEDED (Product Authority 2026-09-10):**
   In alignment with the approved visual prototype (`docs/prototype/screens/gallery.html`) and Basic Design (`SCR-002-01`), the search bar affordance is removed from GalleryScreen. Gallery navigation is strictly Date-first (filter chips: All, Today, 7 days, 30 days, Date; grouped dense grid). Search across published poses is owned exclusively by SearchScreen (`SCR-003-02`).
2. **Deletion cascade (last-reference, Maintainer 2026-08-19):** photo delete
   removes Photo row + owned `imagePath` always; when `poseId != null`, also
   delete linked `PersonalPose` + owned assets using the `PoseRepository.deletePose`
   pattern **only if** no other `Photo` rows reference that `poseId` after this
   delete (`getPhotosByPoseId` count → 0). FK `ON DELETE SET NULL` is not relied
   upon.
3. **Export scope:** Save to Photos **only** — no share sheet / generic file
   export.
4. **Android deferred (Maintainer 2026-08-19, iOS-first):** the build has **no
   Android target** (iOS only), so Android parity would be a build-platform
   addition, not a single actual. Android is **Excluded** from this Plan and
   deferred to a future FEAT-002 slice (planned only after an Android KMP
   target exists).
5. **Title/tag mapping (Option A, Maintainer 2026-08-19):** case-insensitive
   substring on `Photo.poseName` + linked `Pose.name` when `poseId != null`;
   prototype title/tag both map to pose-name text; no new DB tag column.

## Verification labels

- **Aligned** — existing behavior meets acceptance; regression in WI-05.
- **Gap** — must close in this Plan before approval.
- **Partial** — user-visible step works up to a documented boundary.
- **Boundary** — explicit orchestration required; cite handoff contract.
- **Excluded** — must not block Plan approval.
- **Resolved** — Maintainer-closed decision recorded in Plan/DEC.

## Evidence IDs (WI-06 cross-reference)

| ID | Row / concern | Owner |
| --- | --- | --- |
| `E-GAL-SEARCH` | Gallery search filter (Option A mapping) | WI-02 |
| `E-GAL-DELETE` | Atomic photo + last-reference pose cascade | WI-03 |
| `E-GAL-EXPORT` | Save to Photos iOS + success confirm | WI-04 |
| `E-ANDROID-TARGET` | Android build target prerequisite | **Excluded** — future plan |
| `E-GAL-UI` | Dense 3-col grid + aligned UI regression | WI-05 |
| `E-IPHONE` | Real iPhone device evidence | WI-06 |
| `E-ANDROID` | Real Android device evidence | **Excluded** — future plan |
