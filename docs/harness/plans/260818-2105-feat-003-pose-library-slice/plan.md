---
title: FEAT-003 pose library slice
description: Scoped iOS delivery for FEAT-003 browse (My/Community), pose-detail Try Pose prepare+emit, Create Pose Camera capture entry (Option A), retaining the search toolbar icon wired to SearchScreen — excluding FEAT-004 extraction, Android, and FEAT-008 Save.
status: completed
approval:
  status: approved
  required_by: Repository Maintainer
  decided: 2026-08-18
priority: P1
effort: M
branch: codex/feat-003-pose-library-slice
tags:
  - poses
  - ios
  - compose
  - community
  - navigation
  - camera-capture-entry
blockedBy: []
blocks:
  - 260809-2241-selected-pose-camera-handoff
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[product-feature-inventory]]"
    - "[[ui-ux-system]]"
  decisions:
    - "[[DEC-003-feat-003-scoped-parity-matrix|DEC-003]]"
  plans:
    - "[[260809-2241-selected-pose-camera-handoff/plan|260809-2241]]"
    - "[[260818-2112-community-title-search-production/plan|260818-2112]]"
  reports:
    - "[[REP-003-pose-reference-library-convergence-delivery|REP-003]]"
  rules: []
  features:
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
  source_paths:
    - docs/harness/plans/260818-2105-feat-003-pose-library-slice/design.md
    - docs/harness/plans/260818-2105-feat-003-pose-library-slice/scout-summary.txt
    - docs/harness/decisions/DEC-003-feat-003-scoped-parity-matrix.md
    - docs/prototype/screens/poses-list.html
    - docs/prototype/screens/pose-detail.html
    - docs/prototype/screens/camera-live.html
    - docs/prototype/screens/camera-pose-overlay.html
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PosesLibraryCoordinator.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseServiceLocator.kt
created: 2026-08-18T21:05:00+07:00
createdBy: Harness CLI
---

# FEAT-003 pose library slice

## Overview

Deliver the **scoped** FEAT-003 iOS slice per Maintainer **Option A** (2026-08-18):

- poses-list **My Poses / Community** browse — **regression verify** (2240/REP-003 read-only)
- **Retain the search toolbar icon** wired to `SearchScreen` (Plan 2112 cooks search behavior first; 2105 does **not** undo search UI)
- **Create Pose (+)** → `CameraTab` **capture entry** only (`camera-live.html`) — **not** FEAT-004 extraction
- pose-detail **Try Pose prepare + emit** `PreparedPoseReference` — overlay/persistence deferred to Plan **2241**

**Explicitly OUT:** FEAT-004 `extractPose` wiring, SearchScreen behavior, server `?q=`,
`CommunitySearchProvider` changes, Android, FEAT-008 Save. Plan `260809-2240` and
REP-003 are **read-only** unless a named regression fails.

### Plan 2241 seam (M1)

| Owner | Responsibility |
| --- | --- |
| **2105 (this Plan)** | `tryPose()` prepare; set in-memory `preparedReference`; switch to CameraTab |
| **2241** | Durable store; Camera **consume** reference; enable overlay (`CameraScreen.kt:173`) |

Plan 2241 WI-03 ("durably commit selection first") is **stale** vs current
`Navigation.kt:152-156` in-memory emit — 2241 must reconcile on execution; 2105
does not implement persistence.

### Plan 2112 ordering (M3)

Plan **2112** cooks search behavior (SearchScreen, provider, server `q`)
independently — it does **not** depend on 2105 and reintroduces nothing 2105
removed. Plan **2105** retains the search toolbar icon wired to `SearchScreen`
and, after 2112 delivers, verifies the affordance remains wired (WI-03). 2105
does **not** hide or unwire search UI.

Grounding: [scout-summary.txt](./scout-summary.txt), [design.md](./design.md),
[DEC-003](../../decisions/DEC-003-feat-003-scoped-parity-matrix.md) (**approved**;
WI-01 documents matrix only).

## Work Items

- [Work Item 1: Close FEAT-003 scoped authority and parity matrix](./work-item-01-close-feat-003-scoped-authority-and-parity-matrix.md)
- [Work Item 2: Wire Create Pose (+) to Camera capture entry](./work-item-02-wire-create-pose-plus-button-to-camera-capture-entry.md)
- [Work Item 3: Regression verify poses-list browse and retain search affordance](./work-item-03-regression-verify-poses-list-browse-and-retain-search-affordance.md)
- [Work Item 4: Regression verify pose-detail and Try Pose prepare+emit](./work-item-04-regression-verify-pose-detail-and-try-pose-prepare-emit.md)
- [Work Item 5: Verify scoped FEAT-003 evidence and camera handoff boundary](./work-item-05-verify-scoped-feat-003-evidence-and-camera-handoff-boundary.md)

## Coverage

| Objective | Work Items |
| --- | --- |
| DEC-003 parity + Option A authority | 1 |
| Create Pose (+) → Camera capture entry | 2 |
| Browse regression + search affordance retained | 3 |
| Detail regression + Try Pose prepare+emit | 4 |
| Evidence matrix + 2241 boundary | 5 |

| True delta (Cook changes) | WI |
| --- | --- |
| `onExtractPoseClick` → `CameraTab` | 2 |
| Everything else | regression / evidence only |

| Out of scope | Owner |
| --- | --- |
| FEAT-004 extraction / `extractPose` | Future FEAT-004 slice |
| Search behavior + server `q` | Plan 260818-2112 |
| Camera overlay + durable handoff | Plan 260809-2241 |
| Android, FEAT-008 Save | Deferred |

## Verification

- **Positive:** search toolbar button visible on poses-list and navigates to `SearchScreen` (WI-03, evidence ID `E-SEARCH-WIRED`).
- **Negative:** no acceptance step calls `extractPose` (evidence ID `E-EXTRACT-DEFER`).
- Navigation test: Create Pose → `CameraTab` (evidence ID `E-CAM-ENTRY`).
- Detail tests: prepare+emit `preparedReference`; overlay **not** required (`E-TRY-EMIT`).
- Overlay remains `if (false)` — Plan 2241 (`E-2241-BOUNDARY`).
- Browse/community regression tests (2240 baseline).
- `ckh workflow check docs/harness/plans/260818-2105-feat-003-pose-library-slice --workspace .`
- `ckh validate docs/harness/plans/260818-2105-feat-003-pose-library-slice/plan.md --workspace .`

**Approval:** changes_requested (2026-08-18) — Maintainer re-approval required after this material scope revision.
