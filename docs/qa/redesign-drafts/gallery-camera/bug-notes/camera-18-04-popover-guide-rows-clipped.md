# BUG camera-18-04 — with a pose chosen, the popover's pose-guide rows are below the fold but still "tappable"

- **Build:** dev18, 1.1 (18), lane-2 CF871F97
- **Severity:** medium-high — Mirror / Opacity / Scale / Line colour cannot be reached or verified from an automated run,
  and their reported hit frames land on other rows, so a tap is silently swallowed (a VoiceOver user focusing the Mirror
  switch gets a control that does nothing).
- **Steps:** camera → pick a pose → tools → the panel shows Flash · Grid · Timer · Ratio and then ends (clipped at the Ratio
  row). Read the hierarchy: the pose-guide section is present, positioned below the panel's visible bottom edge.
- **Expected:** the pose-guide section is visible after scrolling inside the panel, and only visible controls are hittable;
  tapping the Mirror switch flips it ("Normal" → "Mirrored").
- **Actual:** the section is below the panel's fold; `camera.tools.mirror.switch` exists with bounds
  `[305,576][353,620]`, and tapping it leaves the value at **"Normal"** (`selected:false`/`checked:false`) — the tap lands
  elsewhere. The popover gained two new rows (Timer, Ratio) in build 18 while the panel's capped height stayed
  `CameraProto.popupMaxHeight = 420` (`CameraFeature.swift:1516`, `:1218-1222`), so the guide section was pushed out of
  view.
- **Evidence:** `/tmp/qa-cam-1.1-18/probe-mirror-on.png` (panel clipped after Ratio, no guide section) and the hierarchy
  dumps `hierarchy-mirror.txt` / `hierarchy-mirror-on.txt` (switch present at 576–620 pt, value unchanged after the tap).
- **Flows affected:** TC-CAM-032 (mirror) FAILED for this reason; TC-CAM-003 (opacity/line colour, device) and TC-CAM-034
  (guide scale) are blocked on the same clipping.
- **Open question for Feature:** is scrolling inside the panel intended to bring the guide section into view? A human swipe
  inside the panel was not verifiable in this run (the follow-up probe lost focus to the springboard), so it is untested
  rather than disproven — but the a11y tree exposing un-hittable rows is a defect either way.
