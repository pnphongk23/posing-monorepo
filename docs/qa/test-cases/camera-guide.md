# Camera and pose guide (FEAT-005/012)

Redesign reference: F12 (collapsed strip + one re-open control), F4 (one shared state panel), F5 (bottom snackbar),
owner feedback of 2026-10-31. The camera chrome (top bar, strip, zoom pills, snackbar, permission panel) is
`CameraFeature.swift`; the device-only half of this table is mirrored in `docs/qa/camera-device-checklist.md` §2–§8.

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-CAM-001 | P0 | Clean install, network, camera allowed | 1. Launch. 2. Open first card, scroll until "Use this pose" is visible. 3. Tap "Use this pose" | The camera opens on the chosen pose: top bar Close · the pose name · the eye · tools, the pose strip above the control bar, and the guide drawn by the same pose | automated: TC-CAM-001-use-pose-opens-camera.yaml — ids re-verified at `d001b80` (`camera.choosePose` is now the strip's Browse card) |
| TC-CAM-002 | P1 | Camera, guide on | Pinch, twist and drag the guide | Guide scales/rotates/moves with the fingers; stays within sane bounds; the top bar, strip and rail do not move | manual (device: checklist §4) |
| TC-CAM-003 | P1 | Camera, pose chosen | Open tools, move the opacity slider, pick the other line colour | Guide opacity/colour update live behind the panel; the panel stays open; the chosen colour carries a tick, not just a fill | manual (device: checklist §4) |
| TC-CAM-004 | P0 | Clean install, camera allowed | 1. Launch. 2. Tap dock camera. 3. Open camera tools, tap grid toggle. 4. Tap the pose title | Grid is drawn over the preview and the panel stays open; the title opens the "Choose a pose" sheet with a search field and the pose grid | automated: TC-CAM-004-grid-and-picker.yaml — ids re-verified at `d001b80`; the popover has no Done, the grid tap keeps it open and the Browse card opens the sheet |
| TC-CAM-005 | P1 | Picker sheet open | Search for a pose, pick it | Sheet closes; the guide switches to that pose; the top-bar title becomes that pose's name; no name card overlays the viewfinder | manual (device: checklist §3; search mechanics are TC-CAM-021). The sheet opens from the strip's Browse card (`camera.choosePose`) since `d001b80` |
| TC-CAM-006 | P1 | Camera never asked / refused | Open the camera | One centred panel over a scrim — camera glyph, "Camera access is off", the panel copy, exactly one action: "Allow Camera" when never asked, "Open Settings" after a refusal; no viewfinder, no crash, no second button | automated: TC-CAM-006-permission-panel.yaml Re-pointed for `feat/camera-pose-popup`: the Poses chip (`camera.choosePose`) and the sheet are absent, instead of the old `camera.poseStrip`. |
| TC-CAM-007 | P1 | Clean install, network | 1. Open first card, tap Use this pose. 2. Relaunch the app. 3. Tap dock camera with no pose chosen | Camera opens with the LAST used pose guide (`camera.poseGuide` text = pose id) | automated: TC-CAM-007-last-pose-after-relaunch.yaml |
| TC-CAM-008 | P2 | Device with front camera | Tap switch camera | Preview flips; guide persists; the shutter still works on the new camera | manual (device: checklist §8) |
| TC-CAM-009 | P0 | Clean install | 1. Launch. 2. Tap dock camera. 3. Tap Close camera | Back on Home (catalogue), camera gone | automated: TC-CAM-009-camera-from-home-closes-to-home.yaml |
| TC-CAM-010 | P1 | Remembered pose was deleted, made private or unsaved | Tap dock camera | Camera opens with no pose and no error; paywall gate still runs for the remembered pose | manual (needs a pose removed behind the app's back) |
| TC-CAM-011 | P1 | As CAM-007, camera open with the remembered pose | Open the pose picker, pick another pose | Guide switches to the picked pose, not the remembered one | automated: TC-CAM-011-explicit-pose-beats-remembered.yaml — ids re-verified at `d001b80` (`camera.choosePose` = strip Browse card) |
| TC-CAM-012 | P0 | Clean install, camera allowed | 1. Tap dock camera (strip expanded). 2. Tap the "Poses" control. 3. Tap it again | Collapsed: strip gone, only thumbnail · shutter · flip on the bar, and the same "Poses" control remains (up chevron, "Show pose picker"). Reopened: the strip is back above the bar, same order, everything else unmoved | **retired** — inline pose strip removed; the Poses control always opens the sheet (feat/camera-pose-popup). The flow was deleted with the product, so nothing points at a missing file. |
| TC-CAM-013 | P1 | Camera with a pose guide drawn | Collapse the strip, then re-open it | The guide stays drawn the whole time — `camera.poseGuide` keeps the same pose id through the collapse and after reopening, and collapsing never hides the guide | **retired** — inline pose strip removed; the Poses control always opens the sheet (feat/camera-pose-popup). The flow was deleted with the product, so nothing points at a missing file. |
| TC-CAM-014 | P0 | Clean install, camera allowed | 1. Tap dock camera with no pose. 2. Read the top bar. 3. Open the sheet from the strip's **Browse** card, pick a pose. 4. Read the top bar again | One row with **no pose pill**: Close on the left, tools on the right, and **no eye** while no pose is chosen. After a pose is picked an **eye** appears and reports "Shown"/"Hidden" (label "Hide pose guide" / "Show pose guide"); the top bar never re-grows a "Choose a pose" pill | automated: TC-CAM-014-topbar-eye-and-title.yaml Re-pointed for `feat/camera-pose-popup`: the picker opens from the Poses chip on the scale row and a row is picked by its "Use <name> pose" label; no strip and no Browse card. |
| TC-CAM-015 | P1 | Camera, pose chosen | 1. Tap tools. 2. Read the popover's first row. 3. Tap outside the popover. 4. Re-open it | Popover opens under the top bar on the right, **starting at the Flash row — no title row, no Done button** (no sheet, no scrim, no handle), with rows Flash · Grid · Pose guide · Opacity · Scale · Mirror · Line colour. Every change applies immediately; the outside tap closes it and leaves no scrim; VoiceOver's escape gesture does the same | automated: TC-CAM-015-tools-panel-done.yaml |
| TC-CAM-016 | P0 | Camera, expanded or collapsed | 1. Read the zoom row. 2. Tap the second pill. 3. Relaunch and reopen the camera | The zoom pills are **lens-aware: 0.5x · 1x · 2x**, and a preset the lens cannot serve is not offered at all (`camera.zoom.0.5x|1x|2x`); the current level reads as selected, tapping a pill zooms the preview at once (no cycling), and the choice survives a relaunch. On the Simulator the range falls back to 1…2x, so only **1x and 2x** appear there; 0.5x is a device check (checklist §7). What the *saved* photo shows at that zoom is TC-CAM-030 | automated: TC-CAM-016-zoom-pills.yaml |
| TC-CAM-017 | P1 | Device camera, capture allowed | Capture once with Photos access granted, then once with it denied | Snackbar at the bottom directly above the control bar, tone glyph + words ("Saved" / "Saved to gallery. Allow Photos access to also save to your library."), a View shortcut on a successful save, self-dismiss after a few seconds, tap dismisses | manual (device: checklist §9; the Simulator has no capture) |
| TC-CAM-018 | P1 | Camera refused in iOS Settings | Open the camera and read the bottom bar | The strip and the "Poses" control are gone (nothing to place a pose on); shutter and flip remain; flip / zoom / tools are greyed out; the permission panel is the only action | automated: TC-CAM-018-permission-hides-strip.yaml Re-pointed for `feat/camera-pose-popup`: asserts the Poses chip and the sheet are unavailable instead of `camera.poseStrip` / `camera.pickerStripToggle`. |
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
| TC-CAM-032 | P1 | Camera, pose chosen | Open the tools panel's pose-guide section and toggle **Mirror** | A **Mirror** row with a switch (label "Mirror pose guide", value **Mirrored** / **Normal**) flips the **pose guide overlay only** — the camera preview and the saved photo are untouched — applies live, and survives a relaunch. It is a *different* control from front-camera capture mirroring (TC-CAM-031); never assert one with the other | automated: TC-CAM-032-guide-mirror.yaml |
| TC-CAM-034 | P1 | Camera, pose chosen | Open the tools panel's pose-guide section and move **Scale** | A **Scale** slider resizes the guide about its centre (live, behind the panel), reads its percentage in words, is independent of the pinch gesture's own scale, and survives a relaunch | pending — ids not settled yet (BOARD.md lists the capture/guide controls after Mirror as TBD); request: `camera.tools.scale` + a readable value (Requests 10) |
| TC-CAM-035 | P0 | Device with a front camera | 1. Front camera, hold an asymmetric subject (`HELLO` on paper / one hand raised). 2. Note which side it is on in the preview. 3. Capture, then open the photo in Gallery and in Photos. 4. Repeat on the rear camera | The **saved photo matches the preview**: same left/right orientation, the word reads the same way round, the hand stays on the same side — in Gallery and in Photos alike, never flipped vertically. The rear camera keeps its real-world orientation (the fix must not mirror the back path) | manual (device: checklist §8; no capture on the Simulator, so no flow — bug note `docs/qa/redesign-drafts/gallery-camera/bug-notes/camera-18-05-front-capture-flipped.md`. The regression should carry a unit/rendering test on an asymmetric fixture: Feature to name it) |
| TC-CAM-036 | P0 | Camera, no pose; then a second pass with a pose applied | 1. Cold launch → dock camera → tap **Poses**. 2. Close the sheet. 3. Open a pose detail → "Use this pose" → tap **Poses** again | Both taps open the same sheet — asserted on the sheet's own container (`posePicker.sheet`), which is what closes too — search on top, scopes under it, results below, at least one row carrying `posePicker.row.<poseID>`, including when a pose is already applied (the chip reads "Change pose" then, same id). Closing leaves no sheet (`posePicker.sheet` gone) and a camera whose guide and chrome are unchanged | automated: TC-CAM-036-picker-sheet-opens-from-poses.yaml |
| TC-CAM-037 | P0 | Camera, sheet open with the catalogue loaded | Pick a pose row | The guide switches to that pose and the sheet closes by itself — no Done step, and `posePicker.sheet` is gone; the shutter is usable immediately and the chip now reads "Change pose" | automated: TC-CAM-037-picker-pick-applies-and-closes.yaml |
| TC-CAM-038 | P1 | Camera, sheet open on the full list | Type a term no pose matches, then clear it | The sheet answers with the **Search screen's own words** — "No poses match “term”" and "Try a different pose name." — in the shared card, the grid is gone while the card shows while the sheet itself stays open (`posePicker.sheet`), and clearing restores the grid — rows (`posePicker.row.<poseID>`) included — without refetching | automated: TC-CAM-038-picker-search-parity.yaml |
| TC-CAM-039 | P0 | Camera, tools popover reachable | Open tools, pick **1:1**, then **9:16**, then back to **3:4** | All three ratio chips exist and read as words; choosing one reshapes the preview frame and persists. The frame change is visual, so the flow captures `tools-popover-ratio-chips`, `camera-1x1`, `camera-9x16`, `camera-3x4`; the saved-file crop stays TC-CAM-029 (device) | automated: TC-CAM-039-ratio-preview-frame.yaml |
| TC-CAM-040 | P1 | Camera permission refused | Open the camera and try to reach the pose picker | With no camera the **Poses chip is not offered at all**, so no empty sheet can be opened — asserted on the container (`posePicker.sheet` absent), not only on its children; the permission panel (with "Not now") is the only action and the bar keeps its escape routes | automated: TC-CAM-040-refused-camera-opens-no-sheet.yaml |

Note: since `camera.poseGuide` exists (absent when no guide is drawn), CAM-007/011 and DET-007 prove *which* pose is
drawn, and CAM-001/CAM-013 prove that a guide is drawn at all. `camera.pickerStripToggle` pairs a glyph with a label
("Hide pose picker" / "Show pose picker") and a value ("Expanded" / "Collapsed") for VoiceOver.

## Pose-popup branch (`feat/camera-pose-popup`, f0bd7a2) — ids verified in that source
- **Kept:** `camera.choosePose` is now the **Poses chip** on the zoom/scale row (label "Poses", VoiceOver
  "Choose a pose" / "Change pose", value **"None selected"** or the **selected pose name** — build 23 reports the name
  there, not the word "Selected") and is the sheet's **only** entry;
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

## Build 18 camera changes — RELEASED at `d001b80` (superseded the earlier HOLD list)
Verified in source at `d001b80`:
- `camera.tools.done` is **retired** (the only mention left is `CameraToolsLayout.retiredDoneIdentifier`, a
  unit-test constant). The popover opens on the **Flash row**, has no title row, every control applies immediately, and
  it is dismissed by an **outside tap** or VoiceOver's escape.
- `camera.choosePose` **survives** — it is now the strip's **Browse card** ("Browse", label "Browse all poses"), drawn
  only while the strip is expanded, and it opens the full picker sheet (search + All/Saved scopes).
- `camera.pickerStripToggle` sits at the **right end of the scale row** (same id, same glyph/label pair).
- Zoom is **lens-aware**: ids are `camera.zoom.0.5x|1x|2x`, and a preset the lens cannot serve is not offered. The
  Simulator has no capture device, so it falls back to the 1…2x range and offers **1x and 2x only**; 0.5x is device-only.

Every flow and draft below was reworked in the same pass (Done → outside tap; the Browse card needs the strip expanded):
TC-CAM-001/004/011 keep their flows, TC-CAM-014/015/021/022/023/032/033 are now drafts against these ids and are run on
the 18 app. Their automation cells say so.


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

### Ids to request from the camera lane (all `id TBD on build`)
slide-up sheet container · sheet close/dismiss control · sheet search field (+ its clear control) · sheet result grid /
list · a pose row inside the sheet · the "No poses match" panel · the **Poses** control (does it keep
`camera.pickerStripToggle`, or is there a new id?) · the All/Saved scope chips inside the sheet (keep
`posePicker.scope.all|saved`?) · the **Ratio** control and its options (keep `camera.tools.ratio.3x4|1x1|9x16`?) ·
whether `camera.poseStrip` / `camera.poseStrip.card.<id>` / `camera.poseStrip.retry` disappear entirely (that decides
whether the strip's ids are retired or re-used). Also: does the sheet still carry `posePicker.search` and
`posePicker.state`, or are they renamed? That single answer decides whether TC-CAM-021 keeps its flow or gets a rewrite.

## Flow hazards to watch (found while triaging dev20)
- **TC-CAM-004** failed on dev20 at `posePicker.search` for a **stale premise**, not an app bug: build 18+ draws
  `cameraToolsPopup` as the last child of the camera's root ZStack with a **full-screen** `Color.clear` tap catcher, so a tap
  on the strip's Browse card while the popover is open only dismisses the popover. The flow now dismisses the popover
  (outside tap + assert) before opening the sheet and waits for `posePicker.search` instead of asserting it instantly.
- **`inputText` and the software keyboard** — a Magento step that types (`inputText`) needs a software keyboard; a Simulator
  with **Connect Hardware Keyboard** on shows none, and XCTest's `typeText` can then look stalled. This is a **hazard to
  watch, not a confirmed defect**: dev20 ran **TC-CAM-021 to a PASS** with its `inputText`. If a batch does stall there, turn
  the hardware keyboard off before filing anything. TC-CAM-021 also keeps a fast-fail `assertVisible: posePicker.search`
  before the tap so a missing sheet fails in seconds.
- **TC-CAM-033** (signed-out Saved scope) failed on dev20 pass 5 at `posePicker.scope.saved` for a **flow** reason, not
  an app one: the chips are unconditional in the sheet (`handle → header → scopeChips → searchField → content`), and the
  flow tapped one the moment the grid appeared — while the sheet was still animating in. It now asserts the
  `posePicker.scope` container and `extendedWaitUntil`s each chip (15 s) before tapping. Note it is **not** e2e-tagged and
  needs no credentials; a run that skips it as "needs E2E_EMAIL" is mis-classifying it.
- **Real-camera cases have no flow at all** (device-only by design): TC-CAM-002, 003, 005, 008, 017, 026, 029, 030, 031,
  035. Nothing in `maestro/flows/` taps the shutter expecting a saved photo; the only shutter taps in the suite are the
  paywall lane's TC-PAY-001/002, which assert gate behaviour.

## Fix status (all six camera defects have a fix on main, none verified yet)
`7153c95` duplicate Poses control · `17fdd9f` Browse card leads the strip (the 7 red flows) · `22c9c83` Timer/Ratio option
ids · `2bf15e7` popover safe area (the clipped guide rows, TC-CAM-032) · `48c1222` front-lens capture saved as previewed
(TC-CAM-035) · `4cde9d9` Gallery Add pose no longer prompts a signed-in user (TC-GAL-022/023). Verification is the dev19 run
(and the device run for the capture/orientation items); nothing below is marked fixed on the strength of the commit alone.

## Run on 1.1 (18) — red flows are an app defect, not a flow defect
dev18 run (2026-11-01, lane-2): **7 flows are red for one app bug** — the Browse card that replaced the top pill is off
screen and absent from the accessibility tree, so the pose picker sheet has no reachable entry point
(`docs/qa/redesign-drafts/gallery-camera/bug-notes/camera-18-02-picker-sheet-entry-unreachable.md`): TC-CAM-001, 004, 011,
014, 021, 022, 033. TC-CAM-032 is red for the clipped pose-guide section
(`…/camera-18-04-popover-guide-rows-clipped.md`). Two more defects have no flow attached: the duplicate Poses control
(`…/camera-18-01-…`) and the missing per-option Timer/Ratio ids (`…/camera-18-03-…`, worked around in TC-CAM-027 by
tapping the option words). Green on 18: TC-CAM-006/007/009/012/013/015/016/018/019/024/027, TC-GAL-001, TC-GAL-010.

## F4 state coverage for the camera (loading / empty / error / offline)
| State | Where it is proven |
|---|---|
| permission (never asked / refused) | TC-CAM-006 (draft flow, refused branch) + TC-CAM-018 (draft flow) + device checklist §10 for the first-run prompt |
| picker loading | unit: `CameraPickerStatePanel` selection per picker state (`testStatePanelSelectionPerPickerState`) |
| picker empty catalogue | unit: same mapping + TC-CAM-021's no-match half (flow) |
| picker no match (search) | TC-CAM-021 (draft flow) |
| picker error | unit: `CameraStatePanel.picker` → `.pickerFailed` (shared panel + Retry); no flow — the catalogue failure cannot be forced from Maestro (see Requests) |
| picker offline | TC-CAM-025 (new) |
| strip loading / failed / empty | TC-CAM-020 (unit mapping) + device checklist §3 |
| capture in flight (busy) | TC-CAM-026 (device) |

## Re-baseline when the build lands (existing cases whose expected outcome may change)
- **TC-CAM-017** — the shipped success copy is **"Saved"**; the board says **"Photo saved"**. The camera copy slice is in
  progress, so this case (and checklist §9) must be re-recorded against whatever ships, and the "View" shortcut re-checked
  with it.
- **TC-CAM-021** — if the All/Saved scope chips land in the same sheet, the search case grows a scope dimension: the
  no-match copy may become scope-specific ("No saved poses match …"), so the expected text needs re-recording.
- **TC-CAM-005** — the sheet gains scope chips; "search for a pose and pick it" then has two entry paths, and the case
  must say which scope it runs in.
- **TC-CAM-020** — strip copy/state mapping is stable, but the strip's empty wording ("No poses yet") is shared with the
  picker's saved-empty copy ("No saved poses yet"); if those are unified, the row changes.
- **TC-CAM-016** — **re-baselined at `d001b80`**: the pills are 0.5x / 1x / 2x and lens-aware (`camera.zoom.0.5x|1x|2x`),
  so the old 1x · 2x · 3x wording is retired; the flow asserts 1x/2x because the Simulator offers no 0.5x preset.
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
12. **Answered at `d001b80`:** the sheet opens from the strip's **Browse card** (`camera.choosePose`), the Poses control
    sits at the right end of the scale row, and `camera.tools.done` is retired (outside tap / VoiceOver escape dismiss).
    The six drafts were reworked accordingly and only need the 18 app to run.
13. Still open, now the only thing keeping three camera cases manual: **a readable selected state on the zoom pills**
    (`camera.zoom.<label>` carries `.isSelected` only). A `camera.tools.outside`-style stable tap target for the popover
    dismissal would also make TC-CAM-015/032's outside tap deterministic instead of a screen coordinate.
