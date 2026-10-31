# Camera and pose guide (FEAT-005/012)

Redesign reference: F12 (collapsed strip + one re-open control), F4 (one shared state panel), F5 (bottom snackbar),
owner feedback of 2026-10-31. The camera chrome (top bar, strip, zoom pills, snackbar, permission panel) is
`CameraFeature.swift`; the device-only half of this table is mirrored in `docs/qa/camera-device-checklist.md` §2–§8.

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-CAM-001 | P0 | Clean install, network, camera allowed | 1. Launch. 2. Open first card, scroll until "Use this pose" is visible. 3. Tap "Use this pose" | The camera opens on the chosen pose: top bar Close · the pose name · the eye · tools, the pose strip above the control bar, and the guide drawn by the same pose | automated: TC-CAM-001-use-pose-opens-camera.yaml |
| TC-CAM-002 | P1 | Camera, guide on | Pinch, twist and drag the guide | Guide scales/rotates/moves with the fingers; stays within sane bounds; the top bar, strip and rail do not move | manual (device: checklist §4) |
| TC-CAM-003 | P1 | Camera, pose chosen | Open tools, move the opacity slider, pick the other line colour | Guide opacity/colour update live behind the panel; the panel stays open; the chosen colour carries a tick, not just a fill | manual (device: checklist §4) |
| TC-CAM-004 | P0 | Clean install, camera allowed | 1. Launch. 2. Tap dock camera. 3. Open camera tools, tap grid toggle. 4. Tap the pose title | Grid is drawn over the preview and the panel stays open; the title opens the "Choose a pose" sheet with a search field and the pose grid | automated: TC-CAM-004-grid-and-picker.yaml |
| TC-CAM-005 | P1 | Picker sheet open | Search for a pose, pick it | Sheet closes; the guide switches to that pose; the top-bar title becomes that pose's name; no name card overlays the viewfinder | manual (device: checklist §3; the search mechanics themselves are TC-CAM-021) |
| TC-CAM-006 | P1 | Camera never asked / refused | Open the camera | One centred panel over a scrim — camera glyph, "Camera access is off", the panel copy, exactly one action: "Allow Camera" when never asked, "Open Settings" after a refusal; no viewfinder, no crash, no second button | pending — draft: docs/qa/redesign-drafts/gallery-camera/TC-CAM-006-permission-panel.yaml (ids committed at `b8878da`; the "Open Settings" branch is checked on device, checklist §8) |
| TC-CAM-007 | P1 | Clean install, network | 1. Open first card, tap Use this pose. 2. Relaunch the app. 3. Tap dock camera with no pose chosen | Camera opens with the LAST used pose guide (`camera.poseGuide` text = pose id) | automated: TC-CAM-007-last-pose-after-relaunch.yaml |
| TC-CAM-008 | P2 | Device with front camera | Tap switch camera | Preview flips; guide persists; the shutter still works on the new camera | manual (device: checklist §7) |
| TC-CAM-009 | P0 | Clean install | 1. Launch. 2. Tap dock camera. 3. Tap Close camera | Back on Home (catalogue), camera gone | automated: TC-CAM-009-camera-from-home-closes-to-home.yaml |
| TC-CAM-010 | P1 | Remembered pose was deleted, made private or unsaved | Tap dock camera | Camera opens with no pose and no error; paywall gate still runs for the remembered pose | manual (needs a pose removed behind the app's back) |
| TC-CAM-011 | P1 | As CAM-007, camera open with the remembered pose | Open the pose picker, pick another pose | Guide switches to the picked pose, not the remembered one | automated: TC-CAM-011-explicit-pose-beats-remembered.yaml |
| TC-CAM-012 | P0 | Clean install, camera allowed | 1. Tap dock camera (strip expanded). 2. Tap the "Poses" control. 3. Tap it again | Collapsed: strip gone, only thumbnail · shutter · flip on the bar, and the same "Poses" control remains (up chevron, "Show pose picker"). Reopened: the strip is back above the bar, same order, everything else unmoved | pending — draft: docs/qa/redesign-drafts/gallery-camera/TC-CAM-012-collapse-and-reopen-strip.yaml (ids committed at `b8878da`; promote after a green run on the dev17 build) |
| TC-CAM-013 | P1 | Camera with a pose guide drawn | Collapse the strip, then re-open it | The guide stays drawn the whole time — `camera.poseGuide` keeps the same pose id through the collapse and after reopening, and collapsing never hides the guide | pending — draft: docs/qa/redesign-drafts/gallery-camera/TC-CAM-013-guide-kept-while-collapsed.yaml |
| TC-CAM-014 | P0 | Clean install, camera allowed | 1. Tap dock camera with no pose. 2. Read the top bar. 3. Tap the pose title, pick a pose. 4. Read the top bar again | One row: Close · "Choose a pose" title · tools — and NO eye. After a pose is chosen the title becomes the pose name and an eye control appears between title and tools. The eye hides/shows the guide and reports "Shown"/"Hidden" | pending — draft: docs/qa/redesign-drafts/gallery-camera/TC-CAM-014-topbar-eye-and-title.yaml |
| TC-CAM-015 | P1 | Camera, pose chosen | 1. Tap tools. 2. Tap Done. 3. Tap tools again, tap outside the panel | Panel opens under the top bar on the right (no sheet, no scrim, no handle) with rows Flash · Grid · Pose guide · Opacity · Line colour. Done closes it; an outside tap closes it and leaves no scrim | pending — draft: docs/qa/redesign-drafts/gallery-camera/TC-CAM-015-tools-panel-done.yaml |
| TC-CAM-016 | P1 | Camera, expanded or collapsed | 1. Read the zoom row. 2. Tap 2x. 3. Relaunch and reopen the camera | Three pills 1x · 2x · 3x with the current one selected; tapping 2x selects 2x (no cycling through 3x); 2x is still the selection after a relaunch | pending — draft: docs/qa/redesign-drafts/gallery-camera/TC-CAM-016-zoom-pills.yaml (ids committed at `b8878da`; the *which pill is current* half needs request 1) |
| TC-CAM-017 | P1 | Device camera, capture allowed | Capture once with Photos access granted, then once with it denied | Snackbar at the bottom directly above the control bar, tone glyph + words ("Saved" / "Saved to gallery. Allow Photos access to also save to your library."), a View shortcut on a successful save, self-dismiss after a few seconds, tap dismisses | manual (device: checklist §5; the Simulator has no capture) |
| TC-CAM-018 | P1 | Camera refused in iOS Settings | Open the camera and read the bottom bar | The strip and the "Poses" control are gone (nothing to place a pose on); shutter and flip remain; flip / zoom / tools are greyed out; the permission panel is the only action | pending — draft: docs/qa/redesign-drafts/gallery-camera/TC-CAM-018-permission-hides-strip.yaml |
| TC-CAM-019 | P1 | Camera, strip expanded | Collapse the strip, relaunch the app keeping its data, reopen the camera | The camera opens collapsed (no strip, "Poses" control still there) — the collapsed state is persisted like the other camera settings; a fresh install opens expanded | pending — draft: docs/qa/redesign-drafts/gallery-camera/TC-CAM-019-collapse-survives-relaunch.yaml |
| TC-CAM-020 | P1 | Camera, pose catalogue unreachable / empty | Open the camera expanded with no network, then with a catalogue that has no poses | The strip is never a blank row: placeholder cards while loading, "Couldn't load poses" + Try again on failure, "No poses yet" for an empty catalogue | unit: CameraFeatureTests.CameraChromeTests (`testStripContentFollowsEveryPickerState`); device visual: checklist §2 step 6 |
| TC-CAM-021 | P1 | Camera, catalogue loaded | 1. Open the pose title sheet. 2. Type a term no pose name contains. 3. Tap the search field's clear control | The sheet's search filters the grid by pose name; a query that matches nothing replaces the grid with the shared state panel ("No poses match “<term>”") and clearing restores the full grid without a refetch | pending — draft: docs/qa/redesign-drafts/gallery-camera/TC-CAM-021-picker-search-no-match.yaml (ids `posePicker.search`, `posePicker.searchClear`, `posePicker.state`, `posePicker.grid` committed at `b8878da`) |

Note: since `camera.poseGuide` exists (absent when no guide is drawn), CAM-007/011 and DET-007 prove *which* pose is
drawn, and CAM-001/CAM-013 prove that a guide is drawn at all. `camera.pickerStripToggle` pairs a glyph with a label
("Hide pose picker" / "Show pose picker") and a value ("Expanded" / "Collapsed") for VoiceOver.

## Requests to Feature (via the QA lead)
Confirmed and landed at `b8878da`: `camera.close`, `camera.choosePose` (title pill → sheet), `camera.guideToggle`,
`camera.gallery`, `camera.flip`, `camera.pickerStripToggle` (glyph ⌃ collapsed / ⌄ expanded, label "Show/Hide pose
picker"), `camera.poseStrip`, `camera.poseStrip.card.<poseId>`, `camera.poseStrip.retry`, `camera.zoom.<1x|2x|3x>`,
`camera.status`, `camera.permission`, `camera.tools` (top-right) + `camera.tools.*` + `camera.tools.done`,
`posePicker.search|searchClear|grid|state|close`. Still open:

1. `camera.zoom.<label>` needs a readable selected state — an `accessibilityValue` ("Selected" on the current level,
   "Not selected" elsewhere) or the trait is invisible to Maestro, so TC-CAM-016 can only assert that the three pills
   exist. Without it the "tap 2x actually selected 2x" half of the case stays manual.
2. The permission panel's single action carries no identifier (`APEmptyStateView` is built without
   `actionIdentifier`), so a flow must match the label, which changes with the permission state. Please add
   `camera.permission.action` + a value ("allow" / "settings").
3. Strip card ids embed the pose id (`camera.poseStrip.card.<pose id>`), which a flow cannot know. An index-based id
   (`camera.poseStrip.card.0`, `.1`, …) or the pose name in an `accessibilityValue` would make "tap a different card
   switches the guide" automatable.
4. `dock.gallery` — the dock tab item has a label but no identifier (already logged as `TODO(QA-261029-ID)` in
   TC-GAL-001/TC-EXT-003); Gallery flows start by tapping the "Gallery" text, which is also the title on the Gallery
   screen.
5. Optional: a tone word on `camera.status` (`accessibilityValue` = "Success"/"Error") so the F5 "glyph **and** word"
   pair is assertable without pixels.
