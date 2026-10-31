# BUG camera-18-03 — Timer and Ratio options do not expose their own accessibility ids

- **Build:** dev18, 1.1 (18), lane-2 CF871F97
- **Severity:** low (visual UI is correct; E2E/VoiceOver handle is broken)
- **Steps:** open the camera → tools → read the accessibility hierarchy of the Timer and Ratio rows.
- **Expected:** each choice carries its documented id — `camera.tools.timer.off|3s|10s` and
  `camera.tools.ratio.3x4|1x1|9x16` (they are set in source at `CameraFeature.swift:2642-2662`).
- **Actual:** every Timer choice reports `camera.tools.timer` and every Ratio choice reports `camera.tools.ratio` — the row
  id — so `camera.tools.timer.3s`, `camera.tools.ratio.1x1`, … are **not in the tree** (`Element not found`).
- **Evidence:** `/tmp/qa-cam-1.1-18/hierarchy-popover.txt` (five `camera.tools.timer` nodes, five `camera.tools.ratio`
  nodes, no per-option ids); failure log in `/Users/phamnhuphong/.maestro/tests/2026-11-01_030720/`.
- **Impact / workaround:** TC-CAM-027 now selects the choices by their words (`Timer 3 s`, `1:1`, `9:16`) and passes; the
  device checklist is unaffected. Restore the per-option ids and the flow can go back to ids.
