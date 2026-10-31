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
| TC-CAM-016 | P0 | Camera, expanded or collapsed | 1. Read the zoom row. 2. Tap the second pill. 3. Relaunch and reopen the camera | The three zoom pills (1x · 2x · 3x today; **0.5x · 1x · 2x once the pending zoom-preset slice lands** — the ids stay `camera.zoom.<label>`) show the current level as selected; tapping a pill zooms the preview at once (no cycling); the choice survives a relaunch. What the *saved* photo shows at that zoom is TC-CAM-030 | pending — draft: docs/qa/redesign-drafts/gallery-camera/TC-CAM-016-zoom-pills.yaml (ids committed at `b8878da`; the *which pill is current* half needs request 1) |
| TC-CAM-017 | P1 | Device camera, capture allowed | Capture once with Photos access granted, then once with it denied | Snackbar at the bottom directly above the control bar, tone glyph + words ("Saved" / "Saved to gallery. Allow Photos access to also save to your library."), a View shortcut on a successful save, self-dismiss after a few seconds, tap dismisses | manual (device: checklist §5; the Simulator has no capture) |
| TC-CAM-018 | P1 | Camera refused in iOS Settings | Open the camera and read the bottom bar | The strip and the "Poses" control are gone (nothing to place a pose on); shutter and flip remain; flip / zoom / tools are greyed out; the permission panel is the only action | pending — draft: docs/qa/redesign-drafts/gallery-camera/TC-CAM-018-permission-hides-strip.yaml |
| TC-CAM-019 | P1 | Camera, strip expanded | Collapse the strip, relaunch the app keeping its data, reopen the camera | The camera opens collapsed (no strip, "Poses" control still there) — the collapsed state is persisted like the other camera settings; a fresh install opens expanded | pending — draft: docs/qa/redesign-drafts/gallery-camera/TC-CAM-019-collapse-survives-relaunch.yaml |
| TC-CAM-020 | P1 | Camera, pose catalogue unreachable / empty | Open the camera expanded with no network, then with a catalogue that has no poses | The strip is never a blank row: placeholder cards while loading, "Couldn't load poses" + Try again on failure, "No poses yet" for an empty catalogue | unit: CameraFeatureTests.CameraChromeTests (`testStripContentFollowsEveryPickerState`); device visual: checklist §2 step 6 |
| TC-CAM-021 | P1 | Camera, catalogue loaded | 1. Open the pose title sheet. 2. Type a term no pose name contains. 3. Tap the search field's clear control | The sheet's search filters the grid by pose name; a query that matches nothing replaces the grid with the shared state panel ("No poses match “<term>”") and clearing restores the full grid without a refetch | pending — draft: docs/qa/redesign-drafts/gallery-camera/TC-CAM-021-picker-search-no-match.yaml (ids `posePicker.search`, `posePicker.searchClear`, `posePicker.state`, `posePicker.grid` committed at `b8878da`) |
| TC-CAM-022 | P0 | Camera, catalogue loaded, signed in | 1. Open the pose title sheet. 2. Switch the scope chips All → Saved → All | The sheet offers a two-chip scope under the title: **All** ("All poses") and **Saved** ("Saved poses"); the active chip carries a check glyph and reports value **Selected**, switching re-filters the grid in place without closing the sheet, and the search text keeps applying inside the chosen scope | pending — draft: docs/qa/redesign-drafts/gallery-camera/TC-CAM-022-picker-scope-chips.yaml (ids landed at `a03d03a`: `posePicker.scope`, `posePicker.scope.all`, `posePicker.scope.saved` with a readable `Selected` value) |
| TC-CAM-023 | P1 | Camera, signed in, no saved poses | Open the sheet, switch to Saved | The Saved scope with nothing in it draws the Saved screen's own empty copy — "No saved poses yet" / "Save poses from Community to find them here." — instead of an empty grid, and the All chip still gets back to the catalogue in one tap | pending — draft: docs/qa/redesign-drafts/gallery-camera/TC-CAM-023-saved-scope-empty.yaml (id `posePicker.saved.empty`, landed at `a03d03a`; the flow needs a signed-in account with zero saved poses) |
| TC-CAM-033 | P1 | Camera, signed out | Open the sheet, switch to Saved | Signed out, the Saved scope explains itself with the Saved screen's copy — "Sign in to view your saved poses" / "Your saved poses are tied to your account. Sign in to keep them synced." — and shows **no** pose rows and no error; All keeps working offline of the account | pending — draft: docs/qa/redesign-drafts/gallery-camera/TC-CAM-033-saved-scope-signed-out.yaml (id `posePicker.saved.signIn`, landed at `a03d03a`) |
| TC-CAM-024 | P1 | Camera permission refused | Read the permission panel, then tap the secondary action | The panel carries the primary recovery ("Open Settings" after a refusal / "Allow Camera" when never asked) **and** a secondary **"Not now"**: it leaves the camera without opening Settings, because nothing on the screen is usable without the preview — the user lands back where the camera was opened from, not on a dead viewfinder | pending — draft: docs/qa/redesign-drafts/gallery-camera/TC-CAM-024-permission-not-now.yaml (ids `camera.permission`, `camera.permission.notNow`, landed at `a03d03a`) |
| TC-CAM-025 | P1 | Camera, device offline, some poses already downloaded | Open the sheet offline | An offline banner sits above the still-populated grid (board copy: "You're offline. Showing downloaded poses."), poses that are not available offline are marked/dimmed rather than opening a broken reference, and the state clears when the network returns | pending — ids: `posePicker.offline.banner`, per-tile offline marker; today's banner copy is "Showing your last available poses." and tiles are not marked (gap 05-11/12) |
| TC-CAM-026 | P1 | Device camera, capture in flight | Tap the shutter and read the screen while the photo is written | The shutter shows its spinner and the strip / flip / tools are visibly unavailable; the status reads "Saving photo…" while the write is in flight, then the success snackbar arrives (F5) — no long dead screen with no feedback | manual (device: checklist §5; no capture on the Simulator, and no in-flight status text exists yet — gap 05-16) |
| TC-CAM-027 | P0 | Camera, pose chosen | Open the tools panel and read the Timer and Ratio rows | Two capture rows exist: **Timer** (Off · 3s · 10s) and **Ratio** (3:4 · 9:16 · 1:1). Each shows its current value as a word (never a glyph-only state), changing one updates what the row reads, and both survive a relaunch like the other camera settings | pending — ids not settled yet (BOARD.md seat B lists the capture controls as "controls TBD"); the request is `camera.tools.timer`, `camera.tools.ratio` + a readable value per row (Requests 10), so no flow is drafted |
| TC-CAM-028 | P1 | Camera, Timer set to 3s | 1. Tap the shutter. 2. Read the screen during the countdown. 3. Repeat, then cancel the countdown | Tapping the shutter starts a visible countdown (3 → 2 → 1) over the preview and captures only at zero; a cancel control stops it with **no** photo written and the shutter returns to its idle state | pending — ids: `camera.timer.countdown` + `camera.timer.cancel` (Requests 11); the countdown may render without a camera feed, so that half is meant to be a draft flow, while "no photo written" is device-only (checklist §12) |
| TC-CAM-029 | P0 | Device camera, Ratio 3:4 / 9:16 / 1:1 | For each ratio: select it, frame a scene with obvious edges, capture, then open the photo in Gallery and in Photos | The preview shows the selected framing and the **saved** image is cropped to that ratio — 3:4 portrait, 9:16 tall, 1:1 square — with no black bars baked in and no stretching; the Gallery cell and the detail frame keep that aspect | manual (device: checklist §12; a saved file cannot be produced on the Simulator) |
| TC-CAM-030 | P1 | Device camera | Capture at 2x, then at 1x, and compare the two photos | The saved photo matches the zoom the preview showed when the shutter was pressed — no silent fall back to 1x, no framing mismatch between preview and result | manual (device: checklist §12) |
| TC-CAM-031 | P1 | Device with a front camera | Switch to the front camera, capture with text in view, then read the saved photo | The **saved image** is oriented the way the user framed it and mirrored as intended for a front-camera capture; the pose guide is never baked into the photo and the result is neither upside-down nor double-flipped. This is the *capture* path only — the tools' Mirror row (TC-CAM-032) flips the guide overlay and must not change this photo | manual (device: checklist §12) |
| TC-CAM-032 | P1 | Camera, pose chosen | Open the tools panel's pose-guide section and toggle **Mirror** | A **Mirror** row with a switch (label "Mirror pose guide", value **Mirrored** / **Normal**) flips the **pose guide overlay only** — the camera preview and the saved photo are untouched — applies live, and survives a relaunch. It is a *different* control from front-camera capture mirroring (TC-CAM-031); never assert one with the other | pending — draft: docs/qa/redesign-drafts/gallery-camera/TC-CAM-032-guide-mirror.yaml (ids landed at `da61534`: row `camera.tools.mirror`, switch `camera.tools.mirror.switch`) |
| TC-CAM-034 | P1 | Camera, pose chosen | Open the tools panel's pose-guide section and move **Scale** | A **Scale** slider resizes the guide about its centre (live, behind the panel), reads its percentage in words, is independent of the pinch gesture's own scale, and survives a relaunch | pending — ids not settled yet (BOARD.md lists the capture/guide controls after Mirror as TBD); request: `camera.tools.scale` + a readable value (Requests 10) |

Note: since `camera.poseGuide` exists (absent when no guide is drawn), CAM-007/011 and DET-007 prove *which* pose is
drawn, and CAM-001/CAM-013 prove that a guide is drawn at all. `camera.pickerStripToggle` pairs a glyph with a label
("Hide pose picker" / "Show pose picker") and a value ("Expanded" / "Collapsed") for VoiceOver.

## F4 state coverage for the camera (loading / empty / error / offline)
| State | Where it is proven |
|---|---|
| permission (never asked / refused) | TC-CAM-006 (draft flow, refused branch) + TC-CAM-018 (draft flow) + device checklist §8 for the first-run prompt |
| picker loading | unit: `CameraPickerStatePanel` selection per picker state (`testStatePanelSelectionPerPickerState`) |
| picker empty catalogue | unit: same mapping + TC-CAM-021's no-match half (flow) |
| picker no match (search) | TC-CAM-021 (draft flow) |
| picker error | unit: `CameraStatePanel.picker` → `.pickerFailed` (shared panel + Retry); no flow — the catalogue failure cannot be forced from Maestro (see Requests) |
| picker offline | TC-CAM-025 (new) |
| strip loading / failed / empty | TC-CAM-020 (unit mapping) + device checklist §2 step 6 |
| capture in flight (busy) | TC-CAM-026 (device) |

## Re-baseline when the build lands (existing cases whose expected outcome may change)
- **TC-CAM-017** — the shipped success copy is **"Saved"**; the board says **"Photo saved"**. The camera copy slice is in
  progress, so this case (and checklist §5) must be re-recorded against whatever ships, and the "View" shortcut re-checked
  with it.
- **TC-CAM-021** — if the All/Saved scope chips land in the same sheet, the search case grows a scope dimension: the
  no-match copy may become scope-specific ("No saved poses match …"), so the expected text needs re-recording.
- **TC-CAM-005** — the sheet gains scope chips; "search for a pose and pick it" then has two entry paths, and the case
  must say which scope it runs in.
- **TC-CAM-020** — strip copy/state mapping is stable, but the strip's empty wording ("No poses yet") is shared with the
  picker's saved-empty copy ("No saved poses yet"); if those are unified, the row changes.
- **TC-CAM-016** — the zoom presets move to **0.5x / 1x / 2x** in a pending slice (ids unchanged, `camera.zoom.<label>`):
  re-record the pill labels and re-run the draft flow against the source at that commit before promoting it, rather than
  trusting this row's 1x · 2x · 3x wording.
- **TC-CAM-003** — now that Timer / Ratio / Scale / mirror ship, the tools panel gains two capture rows and the guide
  section two controls: the case must be re-recorded against the new row set and its "only opacity and line colour"
  wording retired.
- **TC-CAM-002** — if the guide's Scale control ships, the pinch case must say how pinch and the slider interact (the
  slider follows the pinch, or pinch is disabled) — re-record whichever ships.

## Out of scope for 1.1 (no flows; kept as acceptance targets)
- The paywall press opening an inline "Capture needs Premium / See plans / Not now" card — the paywall worker's area; the
  camera keeps opening the full paywall.

Timer, Ratio, guide Scale and guide mirror are **in scope** for 1.1 (owner decision, 20:50) and are covered by
TC-CAM-027/028/029/030/031/032; TC-CAM-027's earlier "held" wording is retired.

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
6. Landed at `a03d03a`: `posePicker.scope` (container), `posePicker.scope.all` / `posePicker.scope.saved` (chips with a
   readable `Selected` value), and the Saved scope's own states `posePicker.saved.loading|signIn|error|empty`.
   Landed at `da61534`: `camera.tools.mirror` (row) + `camera.tools.mirror.switch` (value "Mirrored"/"Normal"), and
   `camera.permission.notNow` at `a03d03a`. TC-CAM-022/023/024/032/033 are now drafted against them.
7. Picker offline needs `posePicker.offline.banner` and a per-tile marker (`posePicker.card.<poseId>.offline`), and the
   banner copy has to settle (board: "You're offline. Showing downloaded poses." vs today's "Showing your last available
   poses.") — TC-CAM-025.
8. A way to force the picker's failure state from Maestro (a Debug launch arg for a dead catalogue endpoint, or a
   `-AIPosePickerFixture failed` switch) — otherwise the picker-error panel stays unit-only.
9. Product answer needed for the permission panel's secondary **"Not now"** (TC-CAM-024): `APEmptyStateView` takes one
   action, and dismissing the panel leaves the user on a camera that cannot show a viewfinder.
10. The newly in-scope capture controls need ids **and a readable value** each (same problem as the zoom pills):
    `camera.tools.timer` (value "Off"/"3s"/"10s"), `camera.tools.ratio` (value "3:4"/"9:16"/"1:1"),
    `camera.tools.scale` (value = the percentage), `camera.tools.mirror` (value "Mirrored"/"Not mirrored").
    TC-CAM-027/032 cannot be drafted until they exist — the state has to be a value, not only the `.isSelected` trait.
11. Timer countdown needs `camera.timer.countdown` (label = the remaining seconds) and `camera.timer.cancel`, so
    TC-CAM-028 can be a draft flow instead of a device-only case.
