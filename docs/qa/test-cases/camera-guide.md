# Camera and pose guide (FEAT-005/012)

Redesign reference: F12 (collapsed strip + one re-open control), F4 (one shared state panel), F5 (bottom snackbar),
owner feedback of 2026-10-31. The camera chrome (top bar, strip, zoom pills, snackbar, permission panel) is
`CameraFeature.swift`; the device-only half of this table is mirrored in `docs/qa/camera-device-checklist.md` §2–§8.

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-CAM-001 | P0 | Clean install, network, camera allowed | 1. Launch. 2. Open first card, scroll until "Use this pose" is visible. 3. Tap "Use this pose" | The camera opens on the chosen pose: top bar Close · the eye · tools, the zoom/Poses row above the control bar (no strip), and the guide drawn by the same pose | automated: TC-CAM-001-use-pose-opens-camera.yaml — ids re-verified at `70d38cfe` (`camera.choosePose` is the Poses chip on the scale row) |
| TC-CAM-002 | P1 | Camera, guide on | Pinch, twist and drag the guide | Guide scales/rotates/moves with the fingers; stays within sane bounds; the top bar, strip and rail do not move | manual (device: checklist §4) |
| TC-CAM-003 | P1 | Camera, pose chosen | Open tools, move the opacity slider, pick the other line colour | Guide opacity/colour update live behind the panel; the panel stays open; the chosen colour carries a tick, not just a fill | manual (device: checklist §4) |
| TC-CAM-004 | P0 | Clean install, camera allowed | 1. Launch. 2. Tap dock camera. 3. Open camera tools, tap grid toggle. 4. Tap the pose title | Grid is drawn over the preview and the panel stays open; the title opens the "Choose a pose" sheet with a search field and the pose grid | automated: TC-CAM-004-grid-and-picker.yaml — ids re-verified at `d001b80`; the popover has no Done, the grid tap keeps it open and the Browse card opens the sheet |
| TC-CAM-005 | P1 | Picker sheet open | Search for a pose, pick it | Sheet closes; the guide switches to that pose; the top-bar title becomes that pose's name; no name card overlays the viewfinder | manual (device: checklist §3; search mechanics are TC-CAM-021). The sheet opens from the strip's Browse card (`camera.choosePose`) since `d001b80` |
| TC-CAM-006 | P1 | Camera never asked / refused | Open the camera | One centred panel over a scrim — camera glyph, "Camera access is off", the panel copy, exactly one action: "Allow Camera" when never asked, "Open Settings" after a refusal; no viewfinder, no crash, no second button | automated: TC-CAM-006-permission-panel.yaml Re-pointed for `feat/camera-pose-popup`: the Poses chip (`camera.choosePose`) and the sheet are absent, instead of the old the retired strip ids. |
| TC-CAM-007 | P1 | Clean install, network | 1. Open first card, tap Use this pose. 2. Relaunch the app. 3. Tap dock camera with no pose chosen | Camera opens with the LAST used pose guide (`camera.poseGuide` text = pose id) | automated: TC-CAM-007-last-pose-after-relaunch.yaml |
| TC-CAM-008 | P2 | Device with front camera | Tap switch camera | Preview flips; guide persists; the shutter still works on the new camera | manual (device: checklist §8) |
| TC-CAM-009 | P0 | Clean install | 1. Launch. 2. Tap dock camera. 3. Tap Close camera | Back on Home (catalogue), camera gone | automated: TC-CAM-009-camera-from-home-closes-to-home.yaml |
| TC-CAM-010 | P1 | Remembered pose was deleted, made private or unsaved | Tap dock camera | Camera opens with no pose and no error; paywall gate still runs for the remembered pose | manual (needs a pose removed behind the app's back) |
| TC-CAM-011 | P1 | As CAM-007, camera open with the remembered pose | Open the pose picker, pick another pose | Guide switches to the picked pose, not the remembered one | automated: TC-CAM-011-explicit-pose-beats-remembered.yaml — ids re-verified at `d001b80` (`camera.choosePose` = strip Browse card) |
| TC-CAM-012 | P0 | Clean install, camera allowed | 1. Tap dock camera (strip expanded). 2. Tap the "Poses" control. 3. Tap it again | Collapsed: strip gone, only thumbnail · shutter · flip on the bar, and the same "Poses" control remains (up chevron, "Show pose picker"). Reopened: the strip is back above the bar, same order, everything else unmoved | **retired** — inline pose strip removed; the Poses control always opens the sheet (feat/camera-pose-popup). The flow was deleted with the product, so nothing points at a missing file. |
| TC-CAM-013 | P1 | Camera with a pose guide drawn | Collapse the strip, then re-open it | The guide stays drawn the whole time — `camera.poseGuide` keeps the same pose id through the collapse and after reopening, and collapsing never hides the guide | **retired** — inline pose strip removed; the Poses control always opens the sheet (feat/camera-pose-popup). The flow was deleted with the product, so nothing points at a missing file. |
| TC-CAM-014 | P0 | Clean install, camera allowed | 1. Tap dock camera with no pose. 2. Read the top bar and the eye's own words. 3. Open the picker from the Poses chip, pick a pose. 4. Read the top bar again, tap the eye, toggle **Show guide** | One row with **no pose pill**: Close on the left, the eye and tools on the right. The eye is **always drawn** (`camera.guideToggle`, label "Adjust guide"): without a guide it is disabled and reports **"Unavailable. Choose a pose first"**; with one it reports **"Open guide settings"** and **opens the sheet** (`camera.guideAdjust`) — owner decision 2026-11-08, the eye is the entry point, not a visibility switch. Hide/show is the sheet's **Show guide** toggle (`camera.guideAdjust.showGuide`: off removes `camera.poseGuide`, on brings it back) and Done closes the sheet. The Poses chip reads "Choose a pose" / "Change pose" and the top bar never re-grows a "Choose a pose" pill | automated: TC-CAM-014-topbar-eye-and-title.yaml — re-pointed to `feat/design-sync-1108` (`70d38cfe`): picker from the Poses chip, row picked by its "Use <name> pose" label, eye's Shown/Hidden semantics replaced by the sheet's Show guide toggle. |
| TC-CAM-015 | P1 | Camera, pose chosen | 1. Tap tools. 2. Read the popover's first row. 3. Tap outside the popover. 4. Re-open it | Popover opens under the top bar on the right, **starting at the Flash row — no title row, no Done button** (no sheet, no scrim, no handle), with rows Flash · Grid · Pose guide · Opacity · Scale · Mirror · Line colour. Every change applies immediately; the outside tap closes it and leaves no scrim; VoiceOver's escape gesture does the same | automated: TC-CAM-015-tools-panel-done.yaml |
| TC-CAM-016 | P0 | Camera | 1. Read the zoom control. 2. Change it. 3. Relaunch and re-open | Zoom is **one continuous slider** (`camera.zoom.slider`, label "Zoom"), not presets: it reports its factor as a value (e.g. `1.0×`), the retired pills `camera.zoom.0.5x|1x|2x|3x` must be absent, and the setting survives a relaunch. Maestro can read the value but cannot drag a slider to an exact factor, so *setting* 0.5×/2×/3× and comparing the preview to the captured photo is a device step (checklist §7) | automated: TC-CAM-016-zoom-pills.yaml |
| TC-CAM-017 | P1 | Device camera, capture allowed | Capture once with Photos access granted, then once with it denied | Snackbar at the bottom directly above the control bar, tone glyph + words ("Saved" / "Saved to gallery. Allow Photos access to also save to your library."), a View shortcut on a successful save, self-dismiss after a few seconds, tap dismisses | manual (device: checklist §9; the Simulator has no capture) |
| TC-CAM-018 | P1 | Camera refused in iOS Settings | Open the camera and read the bottom bar | The "Poses" control is gone (nothing to place a pose on — the strip no longer exists in any state); shutter and flip remain; flip / zoom / tools are greyed out; the permission panel is the only action | automated: TC-CAM-018-permission-hides-strip.yaml Re-pointed for `feat/camera-pose-popup`: asserts the Poses chip and the sheet are unavailable instead of `camera.poseStrip` / `camera.pickerStripToggle`. |
| TC-CAM-019 | P1 | Camera, strip expanded | Collapse the strip, relaunch the app keeping its data, reopen the camera | The camera opens collapsed (no strip, "Poses" control still there) — the collapsed state is persisted like the other camera settings; a fresh install opens expanded | **retired** — inline pose strip removed; the Poses control always opens the sheet (feat/camera-pose-popup). The flow was deleted with the product, so nothing points at a missing file. |
| TC-CAM-020 | P1 | Camera, pose catalogue unreachable / empty | Open the camera expanded with no network, then with a catalogue that has no poses | The strip is never a blank row: placeholder cards while loading, "Couldn't load poses" + Try again on failure, "No poses yet" for an empty catalogue | unit: CameraFeatureTests.CameraChromeTests (`testStripContentFollowsEveryPickerState`); device visual: checklist §3 |
| TC-CAM-021 | P1 | Camera, catalogue loaded | 1. Open the pose title sheet. 2. Type a term no pose name contains. 3. Tap the search field's clear control | The sheet asks the **server** the Search screen's own question (debounced ~350 ms, then a round trip), so the answer arrives **after a request** — the flow waits for the state panel instead of asserting on the keystroke. A query that matches nothing replaces the grid with the shared state panel ("No poses match “<term>”"); clearing drops the query, cancels nothing in flight and puts the loaded catalogue back **without a request** | automated: TC-CAM-021-picker-search-no-match.yaml Re-pointed for `feat/camera-pose-popup`: entry is the Poses chip → sheet (search sits on top); the search/no-match/clear assertions are unchanged and the card copy is the Search screen's own. |
| TC-CAM-022 | P0 | Camera, catalogue loaded, signed in | 1. Open the pose title sheet. 2. Switch the scope chips All → Saved → All | The sheet offers a two-chip scope under the title: **All** ("All poses") and **Saved** ("Saved poses"); the active chip carries a check glyph and the `isSelected` trait (build 23 exposes it as a **trait, not** a value string), switching re-filters in place without closing the sheet, and **the typed query survives the switch** — the field keeps its text and the new scope answers the same question (asserted in the flow) | automated: TC-CAM-022-picker-scope-chips.yaml Re-pointed for `feat/camera-pose-popup`: the All/Saved chips live in the sheet opened by the Poses chip; assertions otherwise unchanged. |
| TC-CAM-023 | P1 | Camera, signed in, no saved poses | Open the sheet, switch to Saved | The Saved scope with nothing in it draws the Saved screen's own empty copy — "No saved poses yet" / "Save poses from Community to find them here." — instead of an empty grid, and the All chip still gets back to the catalogue in one tap | **reworked at `d001b80`** (the sheet opens from the strip's Browse card); run on the 18 app.  pending — draft: docs/qa/redesign-drafts/gallery-camera/TC-CAM-023-saved-scope-empty.yaml (id `posePicker.saved.empty`, landed at `a03d03a`; the flow needs a signed-in account with zero saved poses) |
| TC-CAM-033 | P1 | Camera, signed out | Open the sheet, switch to Saved | Signed out, the Saved scope explains itself with the Saved screen's copy — "Sign in to view your saved poses" / "Your saved poses are tied to your account. Sign in to keep them synced." — and shows **no** pose rows and no error; All keeps working offline of the account | automated: TC-CAM-033-saved-scope-signed-out.yaml Re-pointed for `feat/camera-pose-popup`: same entry change (Poses → sheet); the signed-out Saved-scope copy is unaffected. |
| TC-CAM-024 | P1 | Camera permission refused | Read the permission panel, then tap the secondary action | The panel carries the primary recovery ("Open Settings" after a refusal / "Allow Camera" when never asked) **and** a secondary **"Not now"**: it leaves the camera without opening Settings, because nothing on the screen is usable without the preview — the user lands back where the camera was opened from, not on a dead viewfinder | automated: TC-CAM-024-permission-not-now.yaml |
| TC-CAM-025 | P1 | Camera, device offline, some poses already downloaded | Open the sheet offline | An offline banner sits above the still-populated grid (board copy: "You're offline. Showing downloaded poses."), poses that are not available offline are marked/dimmed rather than opening a broken reference, and the state clears when the network returns | pending — ids: `posePicker.offline.banner`, per-tile offline marker; today's banner copy is "Showing your last available poses." and tiles are not marked (gap 05-11/12) |
| TC-CAM-026 | P1 | Device camera, capture in flight | Tap the shutter and read the screen while the photo is written | The shutter shows its spinner and the strip / flip / tools are visibly unavailable; the status reads "Saving photo…" while the write is in flight, then the success snackbar arrives (F5) — no long dead screen with no feedback | manual (device: checklist §9; no capture on the Simulator) |
| TC-CAM-027 | P0 | Camera, pose chosen | Open the tools panel and read the Timer and Ratio rows | Two capture rows exist: **Timer** (Off · 3s · 10s) and **Ratio** (3:4 · 9:16 · 1:1). Each shows its current value as a word (never a glyph-only state), changing one updates what the row reads, and both survive a relaunch like the other camera settings | automated: TC-CAM-027-timer-and-ratio.yaml |
| TC-CAM-028 | P1 | Camera, Timer set to 3s | 1. Tap the shutter. 2. Read the screen during the countdown. 3. Repeat, then cancel the countdown | Tapping the shutter starts a visible countdown (3 → 2 → 1) over the preview and captures only at zero; a cancel control stops it with **no** photo written and the shutter returns to its idle state | pending — ids landed at `117b8bb` (not in the 17 app): `camera.timer.countdown`, `camera.timer.cancel`; the countdown likely needs a real feed, so this stays device-only (checklist §5) and a flow is written only if it renders on the 18 app |
| TC-CAM-029 | P0 | Device camera, Ratio 3:4 / 9:16 / 1:1 | For each ratio: select it, frame a scene with obvious edges, capture, then open the photo in Gallery and in Photos | The preview shows the selected framing and the **saved** image is cropped to that ratio — 3:4 portrait, 9:16 tall, 1:1 square — with no black bars baked in and no stretching; the Gallery cell and the detail frame keep that aspect | manual (device: checklist §6; a saved file cannot be produced on the Simulator) |
| TC-CAM-030 | P1 | Device camera | Capture at 2x, then at 1x, and compare the two photos | The saved photo matches the zoom the preview showed when the shutter was pressed — no silent fall back to 1x, no framing mismatch between preview and result | manual (device: checklist §7) |
| TC-CAM-031 | P1 | Device with a front camera | Switch to the front camera, capture with text in view, then read the saved photo | The **saved image** is oriented the way the user framed it and mirrored as intended for a front-camera capture; the pose guide is never baked into the photo and the result is neither upside-down nor double-flipped. This is the *capture* path only — the tools' Mirror row (TC-CAM-032) flips the guide overlay and must not change this photo | manual (device: checklist §8) |
| TC-CAM-032 | P1 | Camera, pose chosen | Open the guide-adjust sheet through the **visible eye** in the top chrome (`camera.guideToggle`, label "Adjust guide") and toggle **Mirror guide** | A **Mirror guide** button (`camera.guideAdjust.flip`) whose **value** flips **Normal** ⇄ **Mirrored** (the label does not change) flips the **pose guide overlay only** — the camera preview and the saved photo are untouched — applies live, and survives a relaunch. The sheet must open from the **visible** eye, never by tapping the pose reference (that hidden route is why this surface regressed in build 23). It is a *different* control from front-camera capture mirroring (TC-CAM-031); never assert one with the other | automated: TC-CAM-032-guide-mirror.yaml |
| TC-CAM-034 | P1 | Camera, pose chosen | Open the guide-adjust sheet (the top chrome's **eye**, `camera.guideToggle`) and move **Scale** | A **Scale** slider resizes the guide about its centre (the camera stays live behind the sheet), reads its percentage in words (`camera.guideAdjust.scale`), and survives a relaunch | pending — `camera.guideAdjust.scale` exists with a readable value since `70d38cfe`; the flow is not written yet (Requests 10, answered) |
| TC-CAM-035 | P0 | Device with a front camera | 1. Front camera, hold an asymmetric subject (`HELLO` on paper / one hand raised). 2. Note which side it is on in the preview. 3. Capture, then open the photo in Gallery and in Photos. 4. Repeat on the rear camera | The **saved photo matches the preview**: same left/right orientation, the word reads the same way round, the hand stays on the same side — in Gallery and in Photos alike, never flipped vertically. The rear camera keeps its real-world orientation (the fix must not mirror the back path) | manual (device: checklist §8; no capture on the Simulator, so no flow — bug note `docs/qa/redesign-drafts/gallery-camera/bug-notes/camera-18-05-front-capture-flipped.md`. The regression should carry a unit/rendering test on an asymmetric fixture: Feature to name it) |
| TC-CAM-036 | P0 | Camera, no pose; then a second pass with a pose applied | 1. Cold launch → dock camera → tap **Poses**. 2. Close the sheet. 3. Open a pose detail → "Use this pose" → tap **Poses** again | Both taps open the same sheet — asserted on the sheet's own container (`posePicker.sheet`), which is what closes too — search on top, scopes under it, results below, at least one row carrying `posePicker.row.<poseID>`, including when a pose is already applied (the chip reads "Change pose" then, same id). Closing leaves no sheet (`posePicker.sheet` gone) and a camera whose guide and chrome are unchanged | automated: TC-CAM-036-picker-sheet-opens-from-poses.yaml |
| TC-CAM-037 | P0 | Camera, sheet open with the catalogue loaded | Pick a pose row | The guide switches to that pose and the sheet closes by itself — no Done step, and `posePicker.sheet` is gone; the shutter is usable immediately and the chip now reads "Change pose" | automated: TC-CAM-037-picker-pick-applies-and-closes.yaml |
| TC-CAM-038 | P1 | Camera, sheet open on the full list | Type a term no pose matches, then clear it | The sheet answers with the **Search screen's own words** — "No poses match “term”" and "Try a different pose name." — in the shared card, the grid is gone while the card shows while the sheet itself stays open (`posePicker.sheet`), and clearing restores the grid — rows (`posePicker.row.<poseID>`) included — without refetching | automated: TC-CAM-038-picker-search-parity.yaml |
| TC-CAM-039 | P0 | Camera, tools popover reachable | Open tools, pick **1:1**, then **9:16**, then back to **3:4** | All three ratio chips exist and read as words; choosing one reshapes the preview frame and persists. The frame change is visual, so the flow captures `tools-popover-ratio-chips`, `camera-1x1`, `camera-9x16`, `camera-3x4`; the saved-file crop stays TC-CAM-029 (device) | automated: TC-CAM-039-ratio-preview-frame.yaml |
| TC-CAM-040 | P1 | Camera permission refused | Open the camera and try to reach the pose picker | With no camera the **Poses chip is not offered at all**, so no empty sheet can be opened — asserted on the container (`posePicker.sheet` absent), not only on its children; the permission panel (with "Not now") is the only action and the bar keeps its escape routes | automated: TC-CAM-040-refused-camera-opens-no-sheet.yaml |
| TC-CAM-041 | P0 | Camera, pose chosen | 1. Open the camera, pick a pose in the picker sheet. 2. Tap the **eye** in the top chrome (`camera.guideToggle`, label "Adjust guide", value "Open guide settings") — never the pose reference. 3. Toggle **Show guide** off and back on. 4. Select **black**, turn **Mirrored** on, Done. 5. Reopen through the same eye. 6. Done, relaunch (no clearState), reopen through the eye again | The guide's settings are reachable through a **visible** control, which is the point: a build that only offers the hidden guide tap fails this case. **Owner decision 2026-11-08:** the eye *opens the sheet* — there is no separate open button (`camera.guideAdjust.open` retired), **no Reset row** (`camera.guideAdjust.reset` retired) and no long press; showing/hiding the guide is the sheet's first row, the **Show guide** toggle (`camera.guideAdjust.showGuide`), and toggling it must hide and re-show `camera.poseGuide`. Colour is **black or white only** (`camera.guideAdjust.lineColor.black|white`, that order) and **white is the Selected default**; a chosen swatch reports value "Selected", flip reports value "Normal"/"Mirrored" (label fixed at "Mirror guide"), scale reads "100%" at the default. Colour, mirror and opacity all survive a relaunch (`CameraSettings` snapshot). No retired popover id may appear. A user upgrading from a build with a legacy pink/yellow/green colour sees a **white** guide — that migration (`GuideLineColor.stored`) is a device step, since a flow cannot seed the settings blob | automated: TC-CAM-041-guide-adjust-reachable.yaml |

Note: since `camera.poseGuide` exists (absent when no guide is drawn), CAM-007/011 and DET-007 prove *which* pose is
drawn, and CAM-001/CAM-013 prove that a guide is drawn at all. The old `camera.pickerStripToggle` is retired with the strip, so nothing may assert it.

## Design sync — the current guide surface (`feat/design-sync-1108`, `70d38cfe`)

Owner decision 2026-11-08 (final), read from that source — this supersedes every earlier "open the sheet by tapping the
guide" or "separate Adjust guide button" note:

- **Entry point:** the **eye** in the top chrome, `camera.guideToggle` — glyph `eye`, label **"Adjust guide"**, value
  **"Open guide settings"** (or "Unavailable. Choose a pose first" while no guide exists), action
  `model.openGuideAdjust()`. The button is always drawn — dimmed and disabled without a guide — so the sheet always has a
  visible, labelled way in. **No** separate open button, **no** long press. Tapping the reference still works but is the
  hidden route, so no flow may depend on it.
- **No Reset row:** `camera.guideAdjust.reset` and a separate `camera.guideAdjust.open` **never exist** in this source —
  flows guard both with `assertNotVisible` (TC-CAM-041). The board's sheet is a container (`camera.guideAdjust`) with
  `showGuide` · `opacity` · `scale` · line colour + mirror · `done`.
- **Visibility:** the sheet's first row is the **Show guide** toggle (`camera.guideAdjust.showGuide`, `isPoseGuideVisible`);
  `camera.poseGuide` is drawn only while a guide exists *and* that flag is on, which is what makes hiding/re-showing
  assertable. The eye no longer toggles visibility — it opens the sheet (TC-CAM-014 was re-pointed to that at `70d38cfe`).
- **Presentation:** an in-place overlay (not a `.sheet`), so the camera stays live behind it; an outside tap closes it and
  the in-between area is a clear tap catcher, so a flow must close the sheet (`camera.guideAdjust.done`) before touching
  the top chrome again.
- **Line colour / mirror:** `camera.guideAdjust.lineColor.black|white` (white is the default), and `camera.guideAdjust.flip`
  is a button labelled "Mirror guide" whose **value** flips "Normal" ⇄ "Mirrored".

## Pose-popup branch (`feat/camera-pose-popup`, f0bd7a2) — ids verified in that source
- **Kept:** `camera.choosePose` is now the **Poses chip** on the zoom/scale row (label "Choose a pose" when nothing
  is picked / "Change pose" after, value **the same string** as the label when nothing is picked — design-sync
  `70d38cfe` replaced the old "None selected" value — or the **selected pose name** once one is chosen, reported by
  name, not the word "Selected") and is the sheet's **only** entry;
  `camera.tools.ratio` + `camera.tools.ratio.3x4|1x1|9x16` stay in the tools popover; `posePicker.search`,
  `.searchClear`, `.close`, `.state`, `.grid`, `.scope` + `.scope.all|saved`, `.saved.loading|signIn|error|empty`;
  `camera.poseGuide|shutter|gallery|flip|status|timer.countdown|cancel|permission` unchanged.
- **Removed:** `camera.poseStrip`, `camera.poseStrip.retry`, `camera.poseStrip.card.<id>`, `camera.pickerStripToggle` —
  they survive in source only inside `CameraChromeLayout.retiredIdentifiers` (a unit-test guard), so no flow may use them
  (build 23 re-checked: the list is unchanged and the flows no longer reference any of them).
- **Gaps:** the sheet has **no container id** (flows prove it is open via `posePicker.search`); pose rows carry only the
  label "Use <name> pose"; there is **no full-screen tap catcher** on the sheet (only `posePicker.close` dismisses it). The
  tools popover **does** still own a full-screen catcher, so a flow must close it (tap `camera.tools` again) before
  touching the camera chrome.
- The no-match card reads `No poses match “<term>”` + `Try a different pose name.` (the Search screen's `SearchResultsCopy`),
  **not** "No poses for …".

## Build 23 camera — the current surface (branch `fix/camera-review-b23`, `7fa7681`)

Read from that source, not guessed:

- **Preview**: full screen, the ratio frame is **full width**, and everything outside the photo frame is dimmed to
  **65 %** — the frame *is* the photo, so the guide, the scrims and the pinch/twist gestures are clipped to it.
- **Zoom**: one **continuous slider**, `camera.zoom.slider`, VoiceOver label "Zoom" and a value like `1.0×`. The
  lens-aware presets `camera.zoom.0.5x|1x|2x|3x` are **retired**.
- **Tools popover**: container `camera.tools.popover`, **four rows, no title, no Done**. Flash is three chips
  (`camera.tools.flash.off|auto|on`), the grid a switch (`camera.tools.grid`), timer chips
  (`camera.tools.timer.off|3s|10s`) and ratio chips (`camera.tools.ratio.3x4|1x1|9x16`). A setting applies on tap;
  the popover closes on its own control (a toggle) or on an outside tap.
- **Guide-adjust sheet**: `camera.guideAdjust` with `camera.guideAdjust.opacity`, `.scale`, `.flip`,
  `.lineColor.black|white` (that order, **white is the default**) and `.done`, plus a **Reset** row that restores the guide's
  transform only. It is opened from **the pose reference itself** (the guide is the
  control) and the camera stays live behind it. **Superseded by the design sync (`70d38cfe`): the sheet is opened by the
  eye (`camera.guideToggle`), the Reset row is gone and `camera.guideAdjust.showGuide` owns visibility — see §Design sync.**
- **Retired ids** (`CameraToolsLayout.retiredIdentifiers` + the zoom presets): `camera.tools.done`,
  `camera.tools.poseGuide`, `camera.tools.mirror`, `camera.tools.mirror.switch`, `camera.tools.opacity`,
  `camera.tools.scale`, `camera.tools.scale.reset`, `camera.tools.lineColor.black|white`, and every
  `camera.zoom.0.5x|1x|2x|3x`. Flows may only use them as **`assertNotVisible` guards**.
- **Pose sheet**: container `posePicker.sheet`; the picker's **All** scope asks the **server** the Search screen's
  own question (debounced ~350 ms), so its answer arrives after a request; a scope switch **keeps the query**; the
  Poses chip's value is the **selected pose name** ("None selected" when there is none).

Historical: the build-18 notes below described the strip era (Browse card, picker toggle, zoom pills); all of that is
gone and is recorded only so old evidence can still be read.

## Merged change — the inline pose strip is removed (camera lane `feat/camera-pose-popup`)
Status: **merged.** The inline strip is gone, the **Poses control always opens a slide-up sheet with search on top**, and
the **Ratio control changes the preview viewport** (3:4 / 1:1 / 9:16). The ids below were read from the merged source.

### Existing cases
- **Retired:** TC-CAM-012, TC-CAM-013, TC-CAM-019 (collapse / re-open / collapsed-state persistence) — inline pose strip
  removed; the Poses control always opens the sheet (feat/camera-pose-popup). Their flows were deleted in the same commit,
  so no row points at a missing file. Rows kept for history.
- **Re-point to the sheet:** TC-CAM-006, TC-CAM-014, TC-CAM-018, TC-CAM-021, TC-CAM-022, TC-CAM-033 (inline notes on those
  rows say exactly what to swap).

### New cases (new ids continue the sequence; no flow is written until the ids exist)
| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|

### Landed ids (no longer to be requested)

Everything that list asked for exists in build 23: the sheet container (`posePicker.sheet`), its close, search and
clear (`posePicker.close|search|searchClear`), the grid and state panel (`posePicker.grid|state`), pose rows
(`posePicker.row.<poseID>`), the All/Saved scope chips (`posePicker.scope.all|saved`), the Poses control
(`camera.choosePose`, value = the selected pose name), the ratio chips (`camera.tools.ratio.3x4|1x1|9x16`) and the
zoom (`camera.zoom.slider`, with a readable value).

## Out of scope for 1.1 (no flows; kept as acceptance targets)
- The paywall press opening an inline "Capture needs Premium / See plans / Not now" card — the paywall worker's area; the
  camera keeps opening the full paywall.

Timer, Ratio, guide Scale and guide mirror are **in scope** for 1.1 (owner decision, 20:50) and are covered by
TC-CAM-027/028/029/030/031/032; TC-CAM-027's earlier "held" wording is retired.

## Requests to Feature (via the QA lead)
Confirmed and landed at `b8878da`: `camera.close`, `camera.choosePose` (title pill → sheet), `camera.guideToggle`,
`camera.gallery`, `camera.flip`, `camera.zoom.slider`,
`camera.status`, `camera.permission`, `camera.tools` (top-right) + `camera.tools.popover` and its row/chip ids,
`posePicker.search|searchClear|grid|state|close`. Still open:

1. ~~`camera.zoom.<label>` needs a readable selected state~~ — **answered**: the pills are gone, `camera.zoom.slider`
   reports its factor as a value (`1.0×`). Maestro can read it but cannot drag to an exact factor, so *setting* 0.5× /
   2× / 3× and comparing the preview to the captured photo is a device step (checklist §7).
2. The permission panel's single action carries no identifier (`APEmptyStateView` is built without
   `actionIdentifier`), so a flow must match the label, which changes with the permission state. Please add
   `camera.permission.action` + a value ("allow" / "settings").
3. ~~Strip card ids embed the pose id~~ — **answered**: the strip is gone; the sheet's rows are
   `posePicker.row.<poseID>` and rows still expose "Use <name> pose", so a flow picks by label and asserts the id by
   pattern (`'posePicker\.row\..*'`). A specific pose id would have to come from a fixture.
4. `dock.gallery` — the dock tab item has a label but no identifier (already logged as `TODO(QA-261029-ID)` in
   TC-GAL-001/TC-EXT-003); Gallery flows start by tapping the "Gallery" text, which is also the title on the Gallery
   screen.
5. Optional: a tone word on `camera.status` (`accessibilityValue` = "Success"/"Error") so the F5 "glyph **and** word"
   pair is assertable without pixels.
6. Landed at `a03d03a`: `posePicker.scope` (container), `posePicker.scope.all` / `posePicker.scope.saved` (chips with a
   readable `Selected` value), and the Saved scope's own states `posePicker.saved.loading|signIn|error|empty`.
   **Retired in build 23** (moved to the sheet): `camera.tools.mirror` (row) + `camera.tools.mirror.switch` (value "Mirrored"/"Normal"), and
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
    `camera.guideAdjust.scale` (value = the percentage) and `camera.guideAdjust.flip` (value "Mirrored"/"Normal").
    TC-CAM-027/032 cannot be drafted until they exist — the state has to be a value, not only the `.isSelected` trait.
    **Partly answered at `70d38cfe`:** `camera.guideAdjust.scale` (value = the percentage) and
    `camera.guideAdjust.flip` (value "Mirrored"/"Normal") exist as asked, and the sheet's own visibility toggle
    `camera.guideAdjust.showGuide` landed with them — TC-CAM-032/041 are drafted against them. Timer and Ratio still
    carry their state per chip only (`camera.tools.timer.off|3s|10s`, `camera.tools.ratio.3x4|1x1|9x16`, value
    "Selected" on the chosen one), so TC-CAM-027 asserts the chips by id.
11. Timer countdown needs `camera.timer.countdown` (label = the remaining seconds) and `camera.timer.cancel`, so
    TC-CAM-028 can be a draft flow instead of a device-only case.
12. **Answered at `d001b80`:** the sheet opens from the strip's **Browse card** (`camera.choosePose`), the Poses control
    sits at the right end of the scale row, and `camera.tools.done` is retired (outside tap / VoiceOver escape dismiss).
    The six drafts were reworked accordingly and only need the 18 app to run.
13. Still open, now the only thing keeping three camera cases manual: **a readable selected state on the zoom pills**
    (`camera.zoom.<label>` carries `.isSelected` only). A `camera.tools.outside`-style stable tap target for the popover
    dismissal would also make TC-CAM-015/032's outside tap deterministic instead of a screen coordinate.
14. **`camera.guideAdjust.showGuide` is a `Toggle`, so its accessibility frame spans the whole row** while only the
    switch is touch-reactive (`[16,600][377,628]` for the row, switch at the trailing end — measured on 7CC9393C,
    main `9886cb34`). A centre tap therefore lands in the empty gap between the label and the switch and changes
    nothing, which is why TC-CAM-041's first run failed on a step whose product behaviour is correct. The flow now
    taps the switch (`point: "92%,50%"`, relative to the element). Two things would remove the coordinate: give the
    row the hit area it looks like it has (`.contentShape(Rectangle())` + a tap on the binding, i.e. tapping the
    **"Show guide"** label toggles — today it does nothing for a touch user), or expose the switch itself with its own
    id. This is a touch-target gap, not a VoiceOver one: activating the element through accessibility toggles fine.
