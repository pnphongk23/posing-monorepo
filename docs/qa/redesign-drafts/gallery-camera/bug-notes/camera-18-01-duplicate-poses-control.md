# BUG camera-18-01 — the Poses control is rendered twice on the camera

- **Build:** dev18, 1.1 (18), lane-2 CF871F97, run 2026-11-01 02:4x–03:1x
- **Severity:** medium (duplicate control; VoiceOver announces two identical buttons; the panel one sits in the old
  build-17 place and doubles the strip's chrome)
- **Steps:** launch → dock camera → look at the row above the bottom bar.
- **Expected:** exactly **one** `⌃ Poses` control, at the right end of the zoom row (`CameraChromeLayout`'s intended home in
  build 18).
- **Actual:** two `⌃ Poses` chips — one at the right end of the zoom row and a second one inside the bottom panel, directly
  above the shutter. The accessibility hierarchy contains **two** `camera.pickerStripToggle` elements.
- **Evidence:** `/tmp/qa-cam-1.1-18/probe-strip.png`, `/tmp/qa-cam-1.1-18/probe-tools.png` (both show both chips);
  `/tmp/qa-cam-1.1-18/hierarchy-popover.txt` (`camera.pickerStripToggle` × 2).
- **Source:** `CameraFeature.swift` renders `stripToggle` in the panel (`:1938-1940`) *and* in `scaleRow` (`:2095-2100`);
  the panel copy should have been removed when the control moved to the scale row.
- **Flows affected:** TC-CAM-012 / TC-CAM-019 still pass (they tap the first match, both toggle the same state), so this is
  a visual/a11y defect rather than a functional one.

## Status
- **Fix on main:** `7153c95` (fix(ios): draw the camera's Poses control once, on the scale row) — **not yet verified**: needs the dev19 run (and, for the capture/guide
  defects, the device run).
- **Evidence:** the screenshots/hierarchy dumps quoted above were captured under `/tmp/qa-cam-1.1-18/`, which the
  2026-11-01 reboot wiped. The path strings are kept as the historical record; from dev19 on, artefacts that must
  survive a reboot live in `docs/qa/redesign-drafts/gallery-camera/evidence/` (repo) instead of `/tmp`.
