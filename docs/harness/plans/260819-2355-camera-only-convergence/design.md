# Camera-Only Convergence — Design and Brainstorm

## Exact requirements

- **Expected output:** an iOS Camera screen whose behavior follows approved
  Harness documents and whose visual/interaction states match the reconciled
  prototype, with real-iPhone evidence.
- **Acceptance:** FEAT-001 FR-001, FR-002, BR-001, lifecycle and
  persistence failure cases, plus an approved parity matrix with no unexplained
  app/prototype divergence.
- **Explicit exclusions:** video, cloud backup, Android implementation,
  pose extraction (FEAT-004), pose overlay/Try Pose overlay (FEAT-003/008 via
  Plan `260809-2241`), and gallery management details (FEAT-002 via Plan
  `260819-0735`).
- **Non-negotiable constraints:** offline capture; iOS 15+; no duplicate capture;
  one readable file plus one metadata record or complete compensation; no app
  implementation treated as authority; real iPhone for physical Camera claims;
  shutter must never navigate to extraction; flip must switch hardware facing.
- **Affected touchpoints:** Camera Compose UI/state/contract, iOS native bridge,
  local image/database lifecycle, tests and accessibility semantics. Prototype
  files are read-only reference only.

## Authority model

Recommended precedence:

1. Approved FEAT-001 and linked specs own behavior, error handling, persistence,
   accessibility constraints, and exclusions.
2. The approved Camera prototype is the **read-only UI authority** for
   composition, control placement, sizing, visual tokens, and visible
   interaction states. The prototype is **never modified** by this plan. Where
   the prototype conflicts with FEAT-001, the document wins and the production
   app implements the corrected behavior.
3. A parity matrix resolves every conflict before implementation. If documents
   and prototype disagree, neither current app behavior nor developer preference
   breaks the tie; the Repository Maintainer decides and the parity matrix and
   production code are updated — the prototype remains untouched.
4. Current app code supplies implementation constraints and gap evidence only.

### Prototype mismatch evidence (read-only reference)

The prototype contains behaviors that conflict with FEAT-001. These are
**not** modification targets — they are documented evidence. The production app
implements the corrected behavior without altering the prototype.

| Prototype element | Prototype behavior (evidence) | FEAT-001 intended behavior | Production parity correction | Work Item |
| --- | --- | --- | --- | --- |
| Shutter button (`shutter-btn`) | Flash animation then `location.href = 'camera-extracting.html'` at `app.js:331` (click listener `app.js:295-334`) | Stay on Camera; save to Gallery; refresh thumbnail | Capture-only: flash animation + persist + thumbnail update; no navigation | WI-03 |
| Flip button (`nb-btn--square`) | `<a href="camera-pose-overlay.html">` (`camera-live.html:109`) | Switch hardware camera facing BACK ↔ FRONT | Hardware flip: `controller.switchCamera()` toggles facing; no navigation | WI-03 |
| Grid switch default | `checked` (`camera-live.html` grid-switch) | Optional; default unspecified | Default OFF; toggle in more/settings popup | WI-03 |

**Rule:** No file under `docs/prototype/` is created, edited, or deleted by this
plan. The prototype is a static read-only reference.

## Approaches

### A — Patch the current composable in place

Keep permission, UI, native callbacks, persistence, and feedback inside
`CameraScreen`; fill gaps with local flags and callbacks.

- Advantages: smallest diff and fastest first screenshot match.
- Disadvantages: callback races, timeout/late-callback behavior, atomic
  persistence, and lifecycle recovery remain hard to test deterministically.
- Risk: visual convergence can mask fragile delivery semantics.
- Validation: mostly real-device E2E; insufficient isolation for failure paths.

### B — Testable Camera coordinator with the existing Compose/native bridge

Keep Compose UI and Swift/Mijick camera integration, but introduce a small
state/action coordinator and explicit ports for native Camera, image storage,
photo metadata, clock/ID, and timeout. Make `CameraScreen` render state and emit
actions; native callbacks return success/failure with capture identity.

- Advantages: preserves working platform investment, isolates device-specific
  behavior, makes permission/capture/lifecycle/persistence tests deterministic,
  and supports prototype-aligned UI without a platform rewrite.
- Disadvantages: medium refactor; requires carefully defined compensation and
  callback threading/late-result rules.
- Migration: move behavior incrementally behind current entry point; retain
  bundle/navigation contracts.
- Validation: unit state-machine tests, storage/repository integration tests,
  bridge build checks, then Mobile MCP real-iPhone scenarios.

### C — Move the Camera surface entirely to native SwiftUI

Let SwiftUI own preview, controls, capture, and persistence, exposing only final
gallery events to Compose.

- Advantages: direct iOS lifecycle/camera APIs and potentially simpler native UI
  tuning.
- Disadvantages: duplicates design system/navigation/data boundaries, abandons
  common UI reuse, increases migration scope, and does not help Android parity.
- Risk: two UI architectures and harder cross-feature ownership.
- Validation: extensive native UI/unit rewrite plus integration bridge tests.

## Recommendation

**Choose Approach B.** It is the smallest design that satisfies the failure-mode
acceptance criteria rather than only matching screenshots. Approach A is weaker
because the current composable already couples every failure boundary; Approach C
expands scope without a demonstrated platform blocker.

Approach B was also the recommendation of the superseded Plan `260809-1806` and
has not been disputed. The Maintainer should confirm this choice.

## Proposed state and invariants

### Core states

| State | Description | Entry | Exit |
| --- | --- | --- | --- |
| `PermissionRequired` | Initial; waiting for permission decision | App launch | Permission callback |
| `PreviewReady` | Camera feed active, controls enabled | Permission granted + preview started | Capture or interruption |
| `Capturing(captureId)` | Active capture in-flight | Shutter press | Success/failure/timeout/cancel |
| `Persisting(captureId)` | Bytes received, writing file + metadata | Capture bytes arrive | Write complete |
| `CaptureSucceeded(photo)` | Capture complete, thumbnail updated | Persisting success | Brief display → PreviewReady |
| `Error(recoverable)` | Failure state with recovery path | Any failure | Retry or timeout → PreviewReady |

### Lifecycle inputs (orthogonal)

| Input | Effect |
| --- | --- |
| `active` | Preview running; controls enabled |
| `inactive` (backgrounded) | Preview stopped; active capture cancelled; controls disabled |
| `reactive` (foreground re-entry) | Restart preview; restore controls; no stale capture ID |

### Capture identity rules

- Each capture gets a unique `captureId` (UUID or monotonic counter).
- Only the active `captureId` may complete; all others are ignored and cleaned up.
- Timeout (e.g., 10 seconds) invalidates the active capture.
- Backgrounding cancels the active capture.
- Late callbacks for cancelled/expired captures are silently discarded.

### Capture→Gallery pipeline (end-to-end)

```
1. Shutter press (if permission AUTHORIZED + not in-flight)
2. Coordinator generates captureId, enters Capturing(captureId) state
3. Native camera captures bytes → callback with captureId
4. Coordinator validates captureId matches active capture
5. Generate collision-resistant filename: capture_{captureId}.jpg
6. Write file via ImageStorage.writeJpeg(bytes)
7. Verify file is readable (file.exists && file.length > 0)
8. Insert Photo record via PhotoRepository.insertCapturedPhoto(path)
9. If step 7 or 8 fails → delete file (compensation), enter Error state
10. Return inserted Photo record → enter CaptureSucceeded(photo)
11. Update ThumbnailState.Available(imagePath) in UI
12. User taps thumbnail → tabNavigator.current = GalleryTab
13. Gallery loads Photo records via PhotoRepository.getAllPhotos() Flow
14. New photo appears in Gallery grid (reactive SQLDelight query)
```

**FEAT-002 ownership boundary (write side):**
- Camera creates files (`ImageStorage.writeJpeg`) and metadata (`PhotoRepository.insertCapturedPhoto`).
- Each owned file has exactly one metadata reference in `Photo.sq`.
- Camera never deletes files it did not create.
- Gallery deletion (Plan `260819-0735`) owns the read-side cleanup: `PhotoRepository.deletePhoto` removes Photo row + owned `imagePath` file, with last-reference cascade to Pose.

### Persistence orchestration (capture boundary)

```
1. Receive non-empty encoded bytes (captureId validated)
2. Generate collision-resistant filename: capture_{captureId}.jpg
3. Write file via ImageStorage
4. Verify file is readable (file.exists && file.length > 0)
5. Insert metadata via PhotoRepository → receive photo record
6. If step 4 or 5 fails → delete file (compensation)
7. If step 5 fails → delete file (compensation)
8. Only publish thumbnail state after both file and record are valid
9. Return photo record to UI state
```

### Camera controller ports (explicit boundaries)

| Port | Responsibility | Test seam |
| --- | --- | --- |
| `CameraController` (native) | Permission, preview start/stop, capture, switch, flash, grid, zoom | Fake with enum/state |
| `ImageStorage` | Write JPEG bytes, return path | Fake with in-memory map |
| `PhotoRepository` | Insert metadata, query latest, delete | Fake or use test database |
| `Clock` | Generate timestamps, detect timeout | Fake with controllable time |
| `IdGenerator` | Generate capture IDs | Fake with sequential counter |

## UI convergence boundary

Match the prototype's full-bleed preview, safe areas, more/settings placement,
zoom affordance, poses shortcut, distinct shutter bar, latest thumbnail, shutter,
and flip placement as the read-only UI reference. Replace dead `if (false)`
overlay code with explicit UI states. Production implements the corrected
behavior (capture-only shutter, hardware flip, default-OFF grid) without
modifying the prototype. Keep a static composition/face guide separate from a
selected pose overlay, which remains out of scope.

### Prototype-to-app mapping (read-only reference)

The prototype is the visual/interaction reference. The production app matches
its layout and tokens but implements corrected behavior where the prototype
conflicts with FEAT-001. The prototype is never modified.

| Prototype element | App component | Notes |
| --- | --- | --- |
| `nb-camera-viewport` (full-bleed) | `CameraPreview` fills Box | Match full-bleed, no padding on viewport |
| `nb-shutter-bar` (bottom row) | `Row` with thumbnail/capture/flip | Match spacing, alignment, safe area |
| `nb-btn--shutter` (pink circle) | `CaptureButton` | Match size (64dp), shape, color |
| `nb-btn--square` (flip) | `FlipShortcutButton` | Match size (48dp), shape; fix to toggle facing |
| `nb-shutter-bar__thumb` | `GalleryThumbnailButton` | Match size (48dp), shape; show latest photo |
| More button (top-right) | `CameraMoreButton` | Match position, size (40dp) |
| More popup | `CameraMorePopup` | Flash cycle, grid toggle; frame ratio if approved |
| Zoom indicator | `CameraZoomIndicator` | Match position (bottom center), size (36dp) |
| Zoom slider | `CameraZoomSlider` | Match range (1–3×), style |
| Grid overlay | `CameraGridOverlay` | 3×3 rule-of-thirds; enable when grid on |
| Center crosshair | `CenterCrosshair` | Optional static guide; not a pose overlay |

Critical controls receive stable accessibility labels and test tags. Dynamic
type, VoiceOver order, contrast, hit target (minimum 44×44pt), and
reduced-motion behavior are checked rather than inferred from labels.

## Material choices requiring Maintainer confirmation

1. **Approve Approach B** (recommended) versus A or C.
2. **Approve iOS-only delivery slice**; Android remains an explicit FEAT-001 gap
   and the Feature cannot be called fully delivered.
3. **Grid default OFF** — no surprising persisted state on first launch.
4. **Static composition/face guide** — treat as optional decorative element, not
   a FEAT-003 pose overlay. It may be present but must not be confused with the
   selected-pose overlay owned by Plan `260809-2241`.
5. **Frame ratio** — if no visible ratio control is in the prototype, narrow
   the scope to a production-only toggle in the more/settings menu. The
   prototype is not modified.
6. **Prototype mismatch resolution** — approve the three production parity
   corrections in the table above (shutter capture-only, hardware flip,
   grid default OFF) before WI-03 implementation begins. The prototype itself
   is never modified.

Until these choices and FEAT-001 approval exist, this Plan is grounded but not
implementation-ready. **Update:** FEAT-001 is approved (2026-08-13); choices
1–6 remain for the Maintainer.
