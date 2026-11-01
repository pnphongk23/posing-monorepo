# BUG camera-18-02 — the pose picker sheet has no reachable entry point (Browse card off-screen)

- **Build:** dev18, 1.1 (18), lane-2 CF871F97
- **Severity:** **high** — the only way into the "Choose a pose" sheet (`All / Saved` scopes + search) is gone from the UI
  and from the accessibility tree, so a camera user cannot open the picker sheet at all.
- **Steps:** launch (clean state) → dock camera → look at the pose strip → try to open the pose picker sheet.
- **Expected:** the strip ends with a **Browse** card (`camera.choosePose`, magnifier icon, "Browse all poses") which opens
  the sheet — that card is what replaced the removed top "Choose a pose" pill.
- **Actual:** with a loaded catalogue the strip shows four pose cards and the **Browse card is not on screen**; it is also
  **absent from the accessibility hierarchy** (`camera.choosePose` → 0 occurrences), so neither a tap nor VoiceOver can
  reach it. The sheet is unreachable.
- **Evidence:** `/tmp/qa-cam-1.1-18/probe-strip.png` (4 cards, no Browse card);
  `/tmp/qa-cam-1.1-18/hierarchy-popover.txt` (`camera.choosePose` absent while `camera.poseStrip` and four
  `camera.poseStrip.card.<id>` are present).
- **Source:** `browseAllCard` is appended to the end of the horizontal strip `ScrollView` (`CameraFeature.swift:1976-1988`)
  and the strip is *not* scrolled to it; because the card is the last child, it stays outside the viewport.
- **Flows blocked (7, all FAILED for this reason):** TC-CAM-001, TC-CAM-004, TC-CAM-011, TC-CAM-014, TC-CAM-021,
  TC-CAM-022, TC-CAM-033 — every one fails at `assertVisible/tapOn camera.choosePose`.
- **Suggested fix (for Feature, not QA):** pin the Browse card outside the scroll content (a fixed trailing card), or
  scroll the strip to it on first appearance — and make sure it is exposed to accessibility even when it is off-screen.

## Status
- **Fix on main:** `17fdd9f` (fix(ios): lead the camera pose strip with its Browse card) — **not yet verified**: needs the dev19 run (and, for the capture/guide
  defects, the device run).
- **Evidence:** the screenshots/hierarchy dumps quoted above were captured under `/tmp/qa-cam-1.1-18/`, which the
  2026-11-01 reboot wiped. The path strings are kept as the historical record; from dev19 on, artefacts that must
  survive a reboot live in `docs/qa/redesign-drafts/gallery-camera/evidence/` (repo) instead of `/tmp`.
