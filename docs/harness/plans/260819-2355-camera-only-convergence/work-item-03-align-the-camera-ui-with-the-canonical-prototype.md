---
work_item: 3
title: Implement production parity for Camera UI
status: pending
priority: P1
effort: L
dependencies:
  - 2
decision_dependencies: []
---

# Work Item 3: Implement production parity for Camera UI

**Kind:** story

**Note:** The prototype (`docs/prototype/**`) is a read-only UI authority
reference. This work item implements corrected production behavior — it does
not modify, create, or delete any prototype file.

## Tasks

1. Implement the approved full-bleed preview with proper safe-area treatment
   (top notch + bottom home indicator), using the prototype layout as the
   read-only visual reference.
2. Implement the shutter bar layout using the prototype as the read-only
   layout reference:
   - Gallery thumbnail (left): 48dp, rounded, shows latest captured photo via
     `ThumbnailState.Available(imagePath)`.
   - Capture button (center): 64dp, pink/primary color, rounded 18dp.
   - Flip button (right): 48dp, rounded, toggles facing BACK ↔ FRONT; must
     **not** navigate to any other screen.
3. **Production parity correction — shutter:** Capture is capture-only. On
   successful capture: flash animation (~250ms), persist file + metadata,
   update thumbnail. **Never navigate** to `camera-extracting.html` or any
   extraction flow. (Prototype evidence: `window.location.href` at `app.js:331`
   inside click listener `app.js:295-334` redirects to `camera-extracting.html`; production implements capture-only.)
4. **Production parity correction — flip:** Flip button calls
   `controller.switchCamera()` to toggle hardware facing BACK ↔ FRONT. **Never
   navigate** to `camera-pose-overlay.html` or any other screen. (Prototype
   evidence: `camera-live.html:109` links to `camera-pose-overlay.html`;
   production implements hardware flip.)
5. **Production parity correction — grid default:** Grid overlay is hidden by
   default (`isGridVisible = false`). User toggles via more/settings popup.
   (Prototype evidence: `grid-switch` is `checked`; production defaults OFF.)
6. Remove dead `if (false)` overlay block at `CameraScreen.kt:173`; replace
   with explicit UI states driven by the coordinator. Keep selected-pose
   overlay as `if (false)` (owned by Plan `260809-2241`).
7. Enable grid overlay rendering when `isGridVisible` is true; remove the
   `if (false)` gate.
8. Implement the static composition/face guide (center crosshair) as an optional
   decorative element, clearly separated from the pose overlay (which remains
   `if (false)` and owned by Plan `260809-2241`).
9. Update capture flash animation timing to ~250ms (prototype reference:
   `app.js:300-312` white flash overlay).
10. Wire coordinator states to UI:
    - `PermissionRequired` → request permission.
    - `PreviewReady` → live feed + all controls.
    - `Capturing` → flash overlay + disabled capture button.
    - `CaptureSucceeded` → brief status text + thumbnail update.
    - `Error` → status message.
11. Add stable accessibility labels and test tags to all controls:
    - `camera-capture-btn` (capture button).
    - `camera-gallery-thumbnail` (gallery thumbnail).
    - `camera-flip-btn` (flip button).
    - `overlayAction_More` (more button).
    - `zoomButton` / `zoomSlider` (zoom controls).
    - `poseButton` (users/poses button).
12. Add VoiceOver order: preview → controls → shutter bar → status.
13. Validate minimum 44×44pt hit targets for all interactive controls.
14. Add focused presentation/layout tests across supported real-iPhone
    sizes/orientations. Capture→Gallery flow: verify thumbnail updates after
    capture and tapping thumbnail navigates to GalleryTab.

## Scope and affected files

- `mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt`
- Camera UI components and shared theme/components only when the approved
  parity matrix requires a reusable token/component correction.
- Common Camera tests and approved visual evidence fixtures.
- `docs/prototype/**` — **READ-ONLY reference only**; no files created,
  edited, or deleted. Prototype evidence is documented in `design.md`.

## Success criteria

- Every approved parity-matrix row is implemented or explicitly marked as a
  later Feature dependency; no unexplained UI divergence remains.
- All controls remain operable with VoiceOver semantics and minimum hit targets.
- **Shutter is capture-only:** on normal success, the user stays on Camera,
  thumbnail updates, and no navigation to extraction occurs.
- **Flip is hardware-only:** flip button switches camera facing; it does
  **not** navigate to any other screen.
- **Grid default OFF:** grid overlay renders when enabled; hidden by default.
- Capture flash duration is ~250ms (matching prototype visual timing).
- Prototype is never modified; it remains a static read-only reference.
- Capture→Gallery: thumbnail updates after capture; tapping thumbnail
  navigates to GalleryTab.

## Risks

- Pixel matching without safe-area/device normalization can regress smaller
  iPhones; validate structure and tokens, not one hard-coded screenshot.
- MijickCamera SwiftUI view may render differently under UIKitView wrapper.

## Required evidence

- Unit/layout test output.
- Accessibility snapshots (test tags, content descriptions).
- App screenshots at named checkpoints (production parity, not prototype
  comparison).
- `git diff` showing UI-only changes (no prototype edits, no persistence/
  navigation contract changes).
