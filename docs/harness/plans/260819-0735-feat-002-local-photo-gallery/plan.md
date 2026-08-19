---
title: FEAT-002 local photo gallery
description: Scoped iOS delivery for FEAT-002 gallery gaps — title-tag search, atomic photo deletion with linked PersonalPose cascade, Save to Photos (iOS), dense-grid UI parity, and real-device iPhone verification. Android deferred (Maintainer 2026-08-19). FEAT-002 is draft; execution approval is blocked on Product Authority approval of the Feature.
status: completed
approval:
  status: approved
  required_by: Repository Maintainer
  decided: 2026-08-19
priority: P1
effort: M
branch: codex/feat-002-local-photo-gallery
tags:
  - gallery
  - photos
  - search
  - deletion
  - export
  - ios
  - compose
blockedBy: []
blocks: []
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[product-feature-inventory]]"
    - "[[ui-ux-system]]"
    - "[[model-entity-catalogue]]"
    - "[[erd]]"
  decisions:
    - "[[DEC-004-feat-002-gallery-parity-matrix|DEC-004]]"
  plans:
    - "[[260809-1806-camera-source-of-truth-convergence/plan|260809-1806]]"
    - "[[260809-2240-pose-reference-library-convergence/plan|260809-2240]]"
  reports:
    - "[[REP-002-feature-gap-and-release-readiness-audit|REP-002]]"
    - "[[REP-007-feat-002-local-photo-gallery-delivery|REP-007]]"
  rules: []
  features:
    - "[[FEAT-002-manage-a-local-photo-gallery|FEAT-002]]"
  source_paths:
    - docs/harness/plans/260819-0735-feat-002-local-photo-gallery/design.md
    - docs/harness/plans/260819-0735-feat-002-local-photo-gallery/scout-summary.txt
    - docs/harness/decisions/DEC-004-feat-002-gallery-parity-matrix.md
    - docs/prototype/screens/gallery.html
    - docs/prototype/screens/gallery-detail.html
    - docs/prototype/scripts/app.js
    - docs/prototype/scripts/fixtures.js
    - docs/prototype/styles/components/card.css
    - docs/prototype/styles/components/grid.css
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PhotoRepository.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseRepository.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseStorage.kt
    - mobile/shared/src/commonMain/sqldelight/com/aipose/Photo.sq
    - mobile/shared/src/commonMain/sqldelight/com/aipose/Pose.sq
    - mobile/composeApp/src/iosMain/kotlin/com/aipose/platform/SaveToPhotos.ios.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/platform/SaveToPhotos.kt
created: 2026-08-19T07:35:00+07:00
createdBy: Harness CLI
---

# FEAT-002 local photo gallery

## Overview

Deliver the FEAT-002 gallery gaps per the Lead architecture and Maintainer-closed
scope:

- **Search (IN scope):** gallery title-tag filter per prototype
  `app.js:348-352` (title OR tag, case-insensitive) — production has **no**
  search (true delta).
- **Deletion (Maintainer 2026-08-19, Option a: last-reference):** atomic +
  recoverable photo deletion that removes the Photo row **and** owned
  `imagePath`; when `Photo.poseId != null`, also deletes the linked
  `PersonalPose` + owned assets (`imagePath`, `thumbnailPath`,
  `originalImagePath`) using the `PoseRepository.deletePose` pattern
  (`PoseRepository.kt:39-58`) **only when no other Photo references that
  `poseId` after this delete**; otherwise delete only this Photo (shared
  Pose/assets untouched). FK `ON DELETE SET NULL` is **not** relied upon.
- **Export:** Save to Photos **only** (no share sheet / generic file export),
  **iOS** actual + success confirmation.
- **UI:** dense 3-column grid parity (`grid.css:213-219`) + detail regression.
- **DEC-004** iOS-scoped parity matrix + real **iPhone** device evidence.

**Scoped iOS delivery (Maintainer 2026-08-19):** this Plan delivers the FEAT-002
gallery slice on **iOS only**. Android parity is **deferred** to a future
FEAT-002 slice — to be planned only after an Android KMP target exists (see
DEC-004: `E-ANDROID` and `E-ANDROID-TARGET` are **Excluded**).

**Explicitly OUT:** share sheet / generic file export, server gallery API,
community pose management, FEAT-001 capture orchestration (Plan 260809-1806),
modifying completed Plan 260809-2240 / REP-002 except as read-only evidence,
**Android parity** (deferred — future plan).

### Execution prerequisite (authority gate)

**FEAT-002 is `draft`** (`docs/harness/features/FEAT-002-manage-a-local-photo-gallery.md`).
This Plan is mechanically valid but **not execution-approved** until Product
Authority approves the Feature. WI-01 records the prerequisite and the
**recommended FEAT-002 updates**. Repository Maintainer approves the Plan
template/sequence; Product Authority approves the Feature. No Cook until both
are satisfied.

> **Closed at Cook start (WI-01, 2026-08-19):** FEAT-002 is `approved`
> (Product Authority, phongpn, 2026-08-19) and DEC-004 is `approved`
> (Repository Maintainer, 2026-08-19). The draft-only gate above is
> superseded — see
> [WI-01 Evidence](./work-item-01-close-feat-002-authority-and-parity-matrix.md#evidence-wi-01-2026-08-19).

### Relationship notes

- **Plan 260809-1806** (camera source-of-truth convergence): documented
  relationship only; **no `blockedBy`** — no scout evidence of a hard
  dependency (gallery consumes `Photo` records; capture orchestration is
  FEAT-001's concern).
- **Plan 260809-2240** WI-05 (completed): reference pattern for atomic
  PersonalPose deletion — read-only evidence.
- Grounding: [scout-summary.txt](./scout-summary.txt), [design.md](./design.md),
  [DEC-004](../../decisions/DEC-004-feat-002-gallery-parity-matrix.md) (proposed;
  WI-01 records the matrix).

## Work Items

- [Work Item 1: Close FEAT-002 authority and parity matrix](./work-item-01-close-feat-002-authority-and-parity-matrix.md)
- [Work Item 2: Implement gallery title-tag search filter](./work-item-02-implement-gallery-title-tag-search-filter.md)
- [Work Item 3: Atomic photo deletion with linked PersonalPose cascade](./work-item-03-atomic-photo-deletion-with-linked-personalpose-cascade.md)
- [Work Item 4: Save to Photos export (iOS)](./work-item-04-save-to-photos-export-ios-and-android-parity.md)
- [Work Item 5: Gallery UI prototype parity](./work-item-05-gallery-ui-prototype-parity.md)
- [Work Item 6: Verify gallery iPhone evidence](./work-item-06-verify-gallery-iphone-and-android-evidence.md)

## Coverage

| Objective / requirement | Work Items |
| --- | --- |
| FEAT-002 approval prerequisite + recommended updates | 1 |
| DEC-004 parity matrix | 1 |
| Search title-tag filter (prototype authority) | 2 |
| FR-002 / BR-001 delete + PersonalPose cascade | 3 |
| FR-002 export (Save to Photos, iOS) | 4 |
| FR-001 reactive presentation + dense grid / detail | 5 |
| Real-device iPhone evidence | 6 |

| True delta (Cook changes) | WI |
| --- | --- |
| Gallery search state + filter + affordance | 2 |
| PhotoRepository storage + cascade deletion | 3 |
| Save to Photos iOS actual fix + success confirm | 4 |
| Dense 3-col grid + UI alignment | 5 |
| Everything else | evidence / regression |

| Out of scope | Owner |
| --- | --- |
| Share sheet / generic file export | Explicitly OUT |
| Server gallery API | FEAT-002 owns none |
| FEAT-001 capture orchestration | Plan 260809-1806 |
| Community pose management | FEAT-003/005/006 |
| Android parity | Deferred (future plan) |

## Verification

### Verification ledger

| Claim | Verdict | Evidence |
| --- | --- | --- |
| `deletePhoto` removes SQL row only (no file) | **Verified** | `PhotoRepository.kt:35-37` |
| Detail dialog promises permanent deletion | **Verified** | `PhotoDetailDialog.kt:169` |
| FK is `ON DELETE SET NULL` (not cascade) | **Verified** | `Photo.sq:5` |
| Atomic pose-delete + compensation pattern exists | **Verified** | `PoseRepository.kt:39-58`, `70-86` |
| Ownership boundary guards non-owned refs | **Verified** | `PoseStorage.kt` `isOwned` |
| Prototype filter = title OR tag (case-insensitive) | **Verified** | `app.js:348-352` |
| Production gallery has no search | **Verified** | `GalleryScreen.kt` / `GalleryViewModel.kt` full read |
| Save to Photos iOS actual exists; no Android actual | **Verified** | `SaveToPhotos.ios.kt:9`; `find` → iOS only |
| Android parity (build target + actual) | **Excluded** | deferred — iOS-first (Maintainer 2026-08-19); build declares iOS targets only (`composeApp/build.gradle.kts:10-12`, `shared/build.gradle.kts:9-11`); future plan after Android KMP target exists |
| Search title/tag mapping (Option A) | **Resolved** (Maintainer 2026-08-19) | case-insensitive substring on `Photo.poseName` + linked `Pose.name` when `poseId != null`; prototype title/tag both map to pose-name text; no new DB tag column |
| Cascade multi-reference (last-reference) | **Resolved** (Maintainer 2026-08-19) | delete linked PersonalPose + assets only when no other `Photo` rows reference `poseId` after this delete (`getPhotosByPoseId` count → 0) |

**Ledger totals:** 8 Verified · 1 Excluded · 2 Resolved · **0 Unresolved** (11 claims).

**Material findings for Maintainer:** Android parity is a **build-platform
addition**, not a single actual — **deferred** to a future FEAT-002 slice
(Maintainer 2026-08-19; evidence `E-ANDROID-TARGET` is **Excluded** here).
Search mapping (Option A) and cascade semantics (last-reference) are **closed**
(2026-08-19). Remaining gate before Cook: FEAT-002 Product Authority approval.

### Required evidence commands

- `ckh validate docs/harness/plans/260819-0735-feat-002-local-photo-gallery/plan.md --workspace .`
- `ckh workflow check docs/harness/plans/260819-0735-feat-002-local-photo-gallery --workspace .`

### Recommended FEAT-002 updates (documented in WI-01)

1. Add a search requirement (title-tag filter per `app.js:348-352`).
2. Clarify deletion contract: photo row + owned file + linked PersonalPose
   cascade (extend BR-001 wording beyond singular "owned file").
3. Clarify export scope: Save to Photos only (no share sheet / generic file).
4. Defer Android platform parity to a future FEAT-002 slice (iOS-first per
   Maintainer 2026-08-19; Android planned only after an Android KMP target
   exists).
5. Note FK `ON DELETE SET NULL` is not a cascade — explicit orchestration
   required.

**Approval:** pending (2026-08-19). Not execution-approved while FEAT-002 is
`draft`. — *superseded at Cook start (2026-08-19): FEAT-002 approved; see
[WI-01 Evidence](./work-item-01-close-feat-002-authority-and-parity-matrix.md#evidence-wi-01-2026-08-19).* Ledger has **0 Unresolved** claims (Maintainer closed mapping and
cascade 2026-08-19).
