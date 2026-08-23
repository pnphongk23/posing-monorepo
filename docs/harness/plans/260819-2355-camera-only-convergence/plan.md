---
title: Camera-Only Convergence
description: >-
  Converge the Camera implementation on approved Harness documents and the
  canonical prototype. Close authority gaps, align the iOS Camera screen with
  prototype behavior, make capture orchestration testable, and deliver real-iPhone
  evidence. Supersedes Plan 260809-1806-camera-source-of-truth-convergence.
status: pending
approval:
  status: pending
  required_by: Repository Maintainer
priority: P1
effort: XL
branch: codex/camera-only-convergence
tags:
  - camera
  - ios
  - compose
  - prototype
  - source-of-truth
  - convergence
blockedBy:
  - 260809-1805-iphone-mobile-mcp-test-harness
blocks: []
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[product-feature-inventory]]"
    - "[[ui-ux-system]]"
    - "[[model-entity-catalogue]]"
    - "[[erd]]"
  decisions: []
  plans:
    - "[[260809-1806-camera-source-of-truth-convergence/plan|260809-1806]]"
    - "[[260809-2241-selected-pose-camera-handoff/plan|260809-2241]]"
    - "[[260819-0735-feat-002-local-photo-gallery/plan|260819-0735]]"
  reports:
    - "[[REP-002-feature-gap-and-release-readiness-audit|REP-002]]"
  rules: []
  features:
    - "[[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]"
    - "[[FEAT-002-manage-a-local-photo-gallery|FEAT-002]]"
  source_paths:
    - docs/harness/plans/260819-2355-camera-only-convergence/design.md
    # Prototype is READ-ONLY reference — never modified by this plan.
    # - docs/prototype/screens/camera-live.html  (read-only UI authority)
    # - docs/prototype/scripts/app.js             (read-only UI authority)
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera
    - mobile/composeApp/src/iosMain/kotlin/com/aipose/camera
    - mobile/iosApp/iosApp/CameraViewController.swift
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PhotoRepository.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/ImageStorage.kt
    - mobile/shared/src/commonMain/sqldelight/com/aipose/Photo.sq
created: 2026-08-19T23:55:00+07:00
createdBy: Harness CLI
---

# Camera-Only Convergence

## Overview

Make the Camera implementation converge on a deliberately reconciled pair of
authorities: approved Harness documents define behavior and constraints; the
approved prototype defines layout, visual states, control placement, and
interaction presentation. Current app code is delivery evidence, never a source
of truth. When document and prototype conflict, execution stops until the
Maintainer resolves the parity matrix; no implementer chooses silently.

**Supersedes:** Plan `260809-1806-camera-source-of-truth-convergence` (pending,
never approved or cooked). This plan absorbs and refines all six work items from
the previous plan, incorporating grounding findings and Maintainer decisions
available at this date. The previous plan directory remains for reference but is
not the execution target.

**Prototype is read-only:** `docs/prototype/**` is the canonical UI authority
but is never modified or created by this plan. Prototype mismatches (shutter
redirect, flip navigation, grid default) are documented as evidence; the
production app implements the corrected behavior without altering the prototype.

**Delivery slice:** iOS only. This request explicitly requires iPhone testing and
the repository has no Android Camera actual. This does not complete FEAT-001's
Android acceptance; the Android gap is documented in the verification ledger.

### Grounding findings

- **FEAT-001 is approved** (2026-08-13, phongpn). The Authority Closure Gate is
  met; this plan may proceed through approval.
- **Prototype shutter** redirects to `camera-extracting.html` via the click
  listener at `app.js:295-334` (specifically `window.location.href` at
  `app.js:331`). FEAT-001 requires staying on Camera and refreshing the
  thumbnail. This is a **direct authority conflict** — document wins; the
  prototype is a read-only reference and the production app implements capture-
  only behavior (no redirect).
- **Prototype flip** links to `camera-pose-overlay.html` (`camera-live.html:109`).
  FEAT-001 requires switching hardware camera facing (BACK ↔ FRONT). This is a
  **direct authority conflict** — document wins; the prototype is a read-only
  reference and the production app implements hardware flip behavior (no link).
- **Prototype grid default** is `checked` (`camera-live.html` grid-switch).
  Decision: default OFF in production to avoid surprising persisted state.
- **`CameraScreen` owns too many concerns**: UI, permission, native control,
  persistence, and transient feedback in one composable. Only layout helpers
  (`CameraLayoutModel.kt`) have unit tests.
- **Grid/overlay disabled**: overlay rendering is `if (false)` at
  `CameraScreen.kt:173`. Grid changes only Compose state; native start/stop
  bridge commands are no-ops.
- **Capture persistence lacks rollback**: write-then-insert has no read
  verification, no collision-resistant naming (second-level collision risk),
  and no compensation on partial failure.
- **Capture→Gallery pipeline incomplete**: successful capture does not provably
  appear in Gallery; no end-to-end acceptance test covers capture→file→metadata
  →thumbnail→Gallery display.
- **FEAT-002 ownership/deletion boundary undefined from Camera side**: the
  capture-side contract for owned files (which files Camera creates, how
  Gallery deletion cleans them up) is not explicitly specified.
- **Simulator cannot prove real Camera**: empty capture bytes are returned on
  simulator; all physical Camera claims require a real iPhone.

### Superseded plan comparison

| Aspect | 260809-1806 (old) | 260819-2355 (this plan) |
| --- | --- | --- |
| FEAT-001 status | `draft` (blocker) | `approved` (gate met) |
| Prototype reference | Listed as modification target | Read-only; evidence documented, not modified |
| Capture→Gallery pipeline | Implicit | Explicit end-to-end pipeline with acceptance |
| FEAT-002 boundary | Documented only | Ownership/deletion boundary specified |
| Authority matrix | WI-01 scope | WI-01 + design.md full matrix |
| Previous work items | 6 WIs, pending | 6 WIs, refined with FEAT-002 pipeline |
| Verification | Blocked on harness preflight | Full command list + Gallery evidence |

### Scope boundaries — features included and excluded

**IN SCOPE (Camera-only):**

| Concern | Owner |
| --- | --- |
| Live preview (native camera feed) | This plan |
| Camera permission request/deny/recovery | This plan |
| Camera native lifecycle (start/stop/interrupt) | This plan |
| Capture (shutter press → bytes → file → metadata) | This plan |
| Latest thumbnail update and Gallery handoff | This plan |
| Local Photo persistence (PhotoRepository, ImageStorage, Photo.sq) | This plan |
| Camera controls: facing, flash, zoom, grid, frame ratio | This plan |
| Camera UI alignment with canonical prototype | This plan |
| Accessibility (labels, test tags, VoiceOver order, hit targets) | This plan |
| Real-device iPhone verification | This plan |

**OUT OF SCOPE — documented non-dependency boundaries:**

| Concern | Owner | Boundary note |
| --- | --- | --- |
| Prototype modification (`docs/prototype/**`) | Read-only reference | This plan **never** edits, creates, or deletes files under `docs/prototype/`; prototype is UI authority reference only |
| Pose extraction (FEAT-004) | Plan TBD | Camera shutter **must never navigate** to camera-extracting.html or extraction flow; capture outputs file + metadata only |
| Pose overlay / Try Pose overlay (FEAT-003/008) | Plan `260809-2241` | Camera overlay rendering stays `if (false)`; typed `PreparedPoseReference` contract is emitted but not rendered |
| Gallery search, delete cascade, export (FEAT-002) | Plan `260819-0735` (completed) | Photo records are shared; gallery consumes what Camera produces |
| Gallery deletion file cleanup | Plan `260819-0735` (completed) | `PhotoRepository.deletePhoto` removes owned file + metadata; Camera defines the write-side ownership contract |
| Selected-pose camera handoff | Plan `260809-2241` | `PoseServiceLocator.preparedReference` exists but overlay rendering is deferred |
| Android camera implementation | Future plan | No Android Camera actual exists; build targets are iOS only |

## Work Items

- [Work Item 1: Close Camera authority and build the parity matrix](./work-item-01-close-camera-authority-and-build-the-parity-matrix.md)
- [Work Item 2: Refactor Camera state and capture orchestration](./work-item-02-refactor-camera-state-and-capture-orchestration.md)
- [Work Item 3: Align the Camera UI with the canonical prototype](./work-item-03-align-the-camera-ui-with-the-canonical-prototype.md)
- [Work Item 4: Complete native iOS controls and lifecycle behavior](./work-item-04-complete-native-ios-controls-and-lifecycle-behavior.md)
- [Work Item 5: Make capture persistence atomic and recoverable](./work-item-05-make-capture-persistence-atomic-and-recoverable.md)
- [Work Item 6: Verify Camera behavior from unit tests through real iPhone](./work-item-06-verify-camera-behavior-from-unit-tests-through-real-iphone.md)

### Work item dependency graph

```
WI-01 (authority + parity)
  → WI-02 (state/coordinator)
    → WI-03 (UI alignment)
      → WI-04 (native controls)
        → WI-05 (persistence)
          → WI-06 (verification)
```

Linear chain: each work item builds on the previous. WI-01 is docs-only and
unblocks everything. WI-02 through WI-05 are technical/story work. WI-06 is
verification that gates plan completion.

## Coverage

### FEAT-001 requirement coverage

| FEAT-001 requirement | Work Items |
| --- | --- |
| FR-001: Capture disabled until permission authorized | 2, 4, 6 |
| FR-002: One accepted capture produces one local photo outcome | 2, 5, 6 |
| Capture→Gallery pipeline (file → metadata → thumbnail → Gallery display) | 2, 3, 5, 6 |
| FEAT-002 ownership/deletion boundary (write-side contract) | 5, 6 |
| BR-001: Failed/unreadable write must not represent valid capture | 5, 6 |
| Authority closure and document/prototype parity | 1 |
| Production parity with prototype (read-only reference) | 1, 3, 6 |
| Camera controls: facing, flash, zoom, grid, frame ratio | 3, 4, 6 |
| Lifecycle interruption and late callback recovery | 2, 4, 5, 6 |
| Offline Camera operation | 4, 5, 6 |

### Cross-feature traceability

| Feature | Relationship to Camera | Boundary |
| --- | --- | --- |
| FEAT-001 | Primary owner — this plan delivers it | N/A |
| FEAT-002 | Consumer — Gallery reads Photo records Camera produces | **Ownership contract (this plan):** Camera creates file via `ImageStorage.writeJpeg` + inserts `Photo` row via `PhotoRepository.insertCapturedPhoto`. Every owned file has exactly one metadata reference. **Deletion contract (Plan 260819-0735):** `PhotoRepository.deletePhoto` removes the Photo row and owned `imagePath` file; last-reference cascade to Pose row. Camera never deletes files it did not create. Gallery never creates files. |
| FEAT-003 | Adjacent — Poses list navigates to Camera for pose use | Camera "users" button navigates to PosesTab; no camera rendering dependency |
| FEAT-004 | Downstream — Extraction uses Camera's captured image | Camera shutter **must not** navigate to extraction; capture outputs file + metadata only. Extraction is a separate consumer of the captured image. |
| FEAT-005 | Downstream — Pose guide is post-extraction | No camera dependency |
| FEAT-006 | Downstream — Publishing is post-extraction | No camera dependency |
| FEAT-007 | Downstream — Admin is server-side | No camera dependency |
| FEAT-008 | Adjacent — Try Pose sends PreparedPoseReference to Camera | Overlay rendering is `if (false)`; Plan `260809-2241` owns rendering; Camera only receives typed contract |

### Authority/parity matrix

| Camera element | FEAT-001 document authority | Prototype authority | Current app | Parity status | Resolution |
| --- | --- | --- | --- | --- | --- |
| Shutter (normal capture) | Stay on Camera, save to Gallery, refresh thumbnail | Redirects to `camera-extracting.html` via `window.location.href` at `app.js:331` (click listener `app.js:295-334`) | Stays on Camera, persists, refreshes thumbnail | **Conflict** | Document wins; prototype is read-only evidence; production implements capture-only (no redirect) in WI-03 |
| Shutter (capture flash) | Brief flash feedback | White flash overlay 0.25s (`app.js:300-312`) | Flash overlay 140ms | **Partial** | Align timing to 250ms per prototype |
| Flip control | Switch hardware facing BACK ↔ FRONT | Links to camera-pose-overlay.html (`camera-live.html:109`) | Switches facing via `controller.switchCamera()` | **Conflict** | Document wins; prototype is read-only evidence; production implements hardware flip (no link) in WI-03 |
| Gallery thumbnail | Navigate to GalleryTab | Links to gallery.html | Navigates to GalleryTab | **Match** | — |
| Poses/profile button | Navigate to PosesTab | Floating blue circle in viewport bottom-right, `nb-camera-viewport__profile-btn`, links to `poses-list.html` (`camera-live.html:95-97`) | Navigates to PosesTab | **Match** | Prototype layout reference; production navigates to PosesTab |
| Grid default | Optional; default unspecified | Checked/visible (`grid-switch checked`) | `isGridVisible = false` | **Proposed** | Default OFF in production (no surprising persisted state); prototype checked state is evidence only; Maintainer approval required |
| Grid rendering | 3×3 rule-of-thirds overlay | 3×3 CSS grid lines | `if (false)` — disabled | **Broken** | Enable in WI-03 |
| Frame ratio | Must apply selected configuration | No visible ratio control in prototype | Changes Compose state only, no native effect | **Proposed** | Wire to native in WI-04; production-only toggle in more/settings menu; prototype is not modified |
| Flash modes | OFF/ON/AUTO cycle | Flash button in more menu | OFF/ON/AUTO cycle via more popup | **Match** | — |
| Zoom | Selectable zoom factor | Zoom indicator + slider | Zoom indicator + slider, 1–3× | **Match** | — |
| More/settings | Accessible from camera surface | More button top-right | More button top-right | **Match** | — |
| Permission denied | Show recovery guidance, keep capture disabled | Not prototyped | PermissionDeniedOverlay with Open Settings | **Match** | — |
| Capture in-flight | Prevent duplicate capture | No in-flight state prototyped | `isCaptureInFlight` flag | **Match** | — |
| Pose overlay | Excluded from FEAT-001 | camera-pose-overlay.html exists | `if (false)` — disabled | **Excluded** | Owned by Plan `260809-2241` |
| Static composition guide | Not specified in FEAT-001 | Center crosshair visible | CenterCrosshair composable exists | **Proposed** | Treat as optional; not a pose overlay; WI-03; Maintainer approval required |
| Home indicator area | Safe area treatment | Bottom phone footer indicator | `padding(bottom = 24.dp)` | **Partial** | Validate against safe areas in WI-03 |

### UI state matrix

| State | Permission | Preview | Controls | Capture btn | Thumbnail | Overlay | Status text |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Initial (not determined) | Requesting | Hidden | Hidden | Disabled | Empty/last | Hidden | None |
| Permission denied | DENIED | Hidden | Hidden | Disabled | Empty | None | "Camera permission required" |
| Permission restricted | RESTRICTED | Hidden | Hidden | Disabled | Empty | None | "Camera permission required" |
| Preview ready | AUTHORIZED | Live feed | All enabled | Enabled | Empty/last | Grid if on | None |
| Capturing (in-flight) | AUTHORIZED | Live feed | All disabled | Disabled (spinning) | Last | Flash overlay | None |
| Capture succeeded | AUTHORIZED | Live feed | All re-enabled | Enabled | Updated | Grid if on | Brief "Saved" |
| Capture failed (write) | AUTHORIZED | Live feed | All re-enabled | Enabled | Last | None | "Failed to save photo" |
| Capture failed (empty bytes) | AUTHORIZED | Live feed | All re-enabled | Enabled | Last | None | "Capture unavailable" |
| App backgrounded | AUTHORIZED | Stopped | Disabled | Disabled | Last | Hidden | None |
| App foregrounded (re-entry) | AUTHORIZED | Restarted | Restored | Enabled | Last | Restored | None |

### Interaction/state transitions

```
                     ┌──────────────┐
                     │   Not        │
                     │   Determined │
                     └──────┬───────┘
                            │ requestPermission()
                            ▼
              ┌─────────────┴─────────────┐
              │                           │
        ┌─────┴─────┐              ┌──────┴──────┐
        │ AUTHORIZED │              │ DENIED /     │
        └─────┬─────┘              │ RESTRICTED   │
              │ startPreview()      └──────┬──────┘
              ▼                            │ openAppSettings()
     ┌────────────────┐                    ▼
     │  Preview Ready │             (returns to OS;
     └────┬───────┬───┘              may re-enter
          │       │                    on relaunch)
   capture()   switch/flash/
          │     zoom/grid
          ▼
  ┌───────────────┐
  │ Capturing     │
  │ (in-flight)   │
  └───┬───────┬───┘
      │       │
  success   failure/timeout/cancel
      │       │
      ▼       ▼
  ┌───────┐ ┌────────┐
  │ Succeed│ │ Error  │
  └───┬───┘ └────┬───┘
      │          │
      ▼          ▼
  ┌────────────────┐
  │  Preview Ready │  (loop back)
  └────────────────┘
```

### Capture→Gallery pipeline

The complete capture-to-Gallery pipeline is the core deliverable of this plan:

```
1. Shutter press (if enabled + not in-flight)
2. Capture bytes from native camera (with captureId)
3. Generate collision-resistant filename: capture_{captureId}.jpg
4. Write file via ImageStorage.writeJpeg(bytes)
5. Verify file is readable (exists + length > 0)
6. Insert Photo record via PhotoRepository.insertCapturedPhoto(path)
7. If step 5 or 6 fails → delete file (compensation), report error
8. Return inserted Photo record directly to UI state
9. Update thumbnail state with captured image path
10. User taps thumbnail → navigates to GalleryTab
11. Gallery loads Photo records reactively → new photo appears in grid
```

**FEAT-002 ownership/deletion boundary:**
- Camera **creates** files via `ImageStorage.writeJpeg` and **creates** metadata via `PhotoRepository.insertCapturedPhoto`.
- Gallery **reads** metadata reactively and **deletes** via `PhotoRepository.deletePhoto` (owned by Plan `260819-0735`).
- An owned file is one created by Camera capture with exactly one metadata reference in `Photo.sq`.
- `PhotoRepository.deletePhoto` removes the Photo row and owned `imagePath` file; last-reference cascade to Pose row if applicable.
- Camera never deletes files it did not create; Gallery never creates files.

**Acceptance criteria for capture→Gallery:**
- A successful capture provably appears in the Gallery (photo record exists, file is readable, Gallery grid shows it).
- A failed capture never claims success (file + metadata are both cleaned up or both present).
- Two rapid captures produce two distinct files and two distinct Photo records.

### Data/persistence invariants

| Invariant | Contract | Current gap | Target |
| --- | --- | --- | --- |
| One file per capture | `ImageStorage.writeJpeg` returns unique filename | Second-level collision risk (`capture_{timestamp}.jpg`) | Collision-resistant ID (UUID or monotonic counter) |
| One metadata row per capture | `PhotoRepository.insertCapturedPhoto` returns inserted ID | Re-queries ambiguous `getLatestPhotoPath()` | Return inserted record directly |
| Readable file before publish | Thumbnail only shown after file + metadata are valid | No read verification after write | Verify file readability before thumbnail update |
| Atomic compensation | If metadata insert fails, delete the file | No compensation | File deleted on metadata failure; cleanup is idempotent |
| No orphan files | Every file has exactly one metadata reference | Possible orphan on crash between write and insert | Crash-recovery marker or startup scan (WI-05) |
| No duplicate captures | Only one active capture ID at a time | `isCaptureInFlight` flag exists but no ID tracking | Capture ID with timeout and cancellation |
| Gallery displays captured photo | Gallery reads `Photo` records reactively | No end-to-end capture→Gallery acceptance test | Prove captured photo appears in Gallery grid |
| Gallery deletion cleans up owned file | `deletePhoto` removes file + metadata | Boundary documented in Plan `260819-0735` | Write-side ownership contract defined in this plan |

## Verification

### Test commands

```bash
# Unit tests (common)
./gradlew :composeApp:allTests

# iOS simulator integration tests
./gradlew :shared:iosSimulatorArm64Test

# Full build check
./gradlew :composeApp:linkDebugFrameworkIosArm64
```

### Verification ledger

| Claim | Status | Evidence |
| --- | --- | --- |
| FEAT-001 is approved and executable | **Verified** | Approved 2026-08-13, phongpn |
| Document and prototype agree on shutter flow | **Failed** | FEAT main flow vs `app.js:331` (click listener `app.js:295-334`) |
| Document and prototype agree on flip control | **Failed** | FEAT-001 requires hardware flip vs `camera-live.html:109` prototype link |
| Frame ratio reaches native camera | **Failed** | `CameraScreen.kt:121-123`; no controller API |
| Preview lifecycle start/stop is effective | **Failed** | Swift bridge treats commands as no-op |
| Capture persistence is atomic/read-verified | **Failed** | `CameraScreen.kt:330-339`; `ImageStorage.kt` |
| Android is implementable in this Plan | **Failed** | No Android Camera actual/preview |
| Existing Camera behavior has automated coverage | **Partial** | Layout model tests only; no orchestration/device tests |
| Real iPhone evidence path is ready | **Failed** | Requires build/sign/install workflow |
| FEAT-002 gallery consumes Photo records correctly | **Verified** | Plan `260819-0735` completed |
| Camera overlay boundary is documented | **Verified** | `if (false)` at `CameraScreen.kt:173`; Plan `260809-2241` owns rendering |
| Prototype is read-only; no prototype files modified | **Verified** | Plan scope excludes `docs/prototype/**` modification |
| Capture→Gallery end-to-end flow works | **Unresolved** | Requires WI-02 through WI-06 completion |
| FEAT-002 ownership/deletion boundary is defined | **Unresolved** | Requires WI-05 completion |

**Ledger totals:** 5 Verified · 6 Failed · 1 Partial · **2 Unresolved** (14 claims).

### Required evidence commands

- `ckh validate docs/harness/plans/260819-2355-camera-only-convergence/plan.md --workspace .`
- `ckh workflow check docs/harness/plans/260819-2355-camera-only-convergence --workspace .`

### iOS-first limitations

| Limitation | Impact | Mitigation |
| --- | --- | --- |
| No Android Camera actual | FEAT-001 cannot claim cross-platform delivery | Documented as explicit gap; future plan |
| Simulator returns empty capture bytes | Cannot prove real capture in CI | Real iPhone required for capture claims |
| MijickCamera API constraints | Flash/grid/zoom capabilities depend on SDK version | Verify resolved dependency before WI-04 |
| Flash availability varies by device | Some devices lack flash on front camera | Model capability; don't promise all modes |
| Safe area dimensions vary by iPhone model | Bottom bar / top safe area may overlap | Use Compose safe-area APIs, not hard-coded dp |

**Approval:** pending. No Cook or application change is authorized until this
plan is approved by the Repository Maintainer and all work items are individually
authorized.
