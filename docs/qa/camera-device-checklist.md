# On a real device — camera and paywall (product owner checklist)

Release 1.1 (build 17). The Simulator has no camera, so the camera sections below must be done on a physical iPhone with
the Dev build installed (`posing.camera.app`). Section 1 (paywall) needs a **production / TestFlight** build: a Release
build on a Simulator cannot resolve the real StoreKit products (see `docs/qa/prod-smoke` S-05 — the offering never loads
and the paywall falls back to "Plans are temporarily unavailable"), so the plan cards and their prices can only be
verified on device. Budget ~35 minutes. Record the screen (Control Centre → Screen Recording) for the whole run.

**Before you start**
- [ ] Close every other app; set brightness to ~70%; unlock rotation lock.
- [ ] Have one pose open at least once so a pose guide exists (Home → tap any card → wait for the photo) — only needed for the camera sections.
- [ ] You will need at least two poses for the strip, so also save a second pose if the catalogue is empty.
- [ ] The Gallery sections need photos: capture **three** (one that stays the newest), and ideally keep one older capture from another day
  so the date headers and the 30-day filter show something. Delete exactly one of them in section 10 — that is the point of the deletion checks.
- [ ] Note your device model + iOS version + build number (Settings → About) at the top of your notes.

## 1. Paywall on device (TestFlight)
Run this on the TestFlight (production) build — StoreKit products only resolve for a real TestFlight/App Store install.
- [ ] Install the TestFlight build and sign in with a **real** account.
- [ ] Open the paywall: tap the shutter while the gate is on, or go Settings → Premium.
- [ ] **Expected:** **both** the annual and the monthly plan cards render, each with a **localized price** for your store
  region and a purchase CTA. No "Plans are temporarily unavailable" message and no empty card.
- [ ] Do **not** buy anything — skip the purchase unless you explicitly choose to run a sandbox purchase.
- [ ] Tap **Restore purchases**.
- [ ] **Expected:** it responds (either a success state or a "nothing to restore" message); no hang, no crash, the
  paywall stays usable afterwards.

## 2. Collapsed / reopened pose strip (F12)
The camera opens **expanded**: a strip of poses plus one clear control that both hides and re-opens it. There is no
hidden gesture and no other way back. **Build 18:** that control sits at the right end of the **scale row** above the bar (same glyph, same word) — the
strip itself and the two states do not change.
1. From Home, tap the camera button in the bottom dock.
- [ ] **Expected:** in the rounded panel above the bottom control bar there is a horizontal strip of pose thumbnails with
  their names, and **one** control under it reading **Poses** with a **down** chevron (VoiceOver: "Hide pose picker",
  value "Expanded").
- [ ] **Expected:** the pose you are using carries a tick on its card.
2. Tap that **Poses** control.
- [ ] **Expected:** the strip disappears; the bottom bar is now only the last-photo thumbnail, the shutter and the
  flip-camera button. The same **Poses** control is still there with an **up** chevron (VoiceOver: "Show pose picker",
  value "Collapsed") — it never disappears while a pose picker is available.
- [ ] **Expected:** the zoom pills and the top bar (Close · pose title · eye · tools) stay exactly where they were.
3. Tap **Poses** again.
- [ ] **Expected:** the strip comes back above the control bar, in the same order, still ticking the same pose; nothing
  else moves.
4. Tap a different pose card in the strip.
- [ ] **Expected:** the guide switches to that pose immediately (no extra confirm), the tick moves to that card, and the
  pose name in the top bar changes to the new pose.
5. Leave the camera collapsed, close the camera, force-quit the app, reopen the camera.
- [ ] **Expected:** the camera remembers the last state (left it collapsed → opens collapsed; left it expanded → opens
  expanded). A fresh install starts expanded.
6. Turn Wi-Fi and mobile data off, then force-quit and reopen the camera.
- [ ] **Expected:** the strip states are honest, never a blank row: while it is still loading it shows placeholder cards;
  if the pose list could not load it reads "Couldn't load poses" with a **Try again** button; with no poses saved at all
  it reads "No poses yet". Turn the network back on and tap **Try again** → the strip fills.

## 3. Top bar: Close · pose title · eye · tools
**Build 17** (the build on your phone now): the whole top chrome is one row — Close on the left, the pose title with a down
chevron, the eye once a pose is chosen, and the tools control on the right.
1. Open the camera with no pose chosen.
- [ ] **Expected (17):** a round **Close** (×) on the left, the title "Choose a pose" with a down chevron beside it, **no eye**,
  and the **tools** control (three sliders) on the right.
2. Tap the title.
- [ ] **Expected (17):** the "Choose a pose" sheet opens (search field + pose grid) with a **Done** button; nothing else on
  the camera moves.
- [ ] Pick a pose.
- [ ] **Expected (17):** the sheet closes, the title becomes that pose's name, and an **eye** control appears between the title
  and the tools control.

**Build 18 — the top bar has no pose pill any more.**
- [ ] **Build 18:** look at the top bar.
- [ ] **Expected:** no "Choose a pose" pill — only **X** (`camera.close`) on the left and the **tools** button on the right,
  plus the **eye** once a pose is chosen. Nothing in the bar says "Choose a pose".
- [ ] **Build 18:** pick a different pose.
- [ ] **Expected:** the pose picker is reached from the **strip's last card, "Browse"** (magnifier icon, VoiceOver "Browse all
  poses"): the Poses control at the right end of the scale row expands the strip, **Browse** opens the full sheet (search +
  **All / Saved**), picking a card switches the guide and closes the sheet. Nothing else in the top bar grew a pill.

3. Tap the eye.
- [ ] **Expected:** the guide disappears and the glyph becomes a crossed-out eye (VoiceOver: "Show pose guide", value
  "Hidden"). Tap it again → the guide returns in the same place, size and colour.
4. Tap the tools control (three sliders).
- [ ] **Expected:** a **Camera tools** panel opens **under the top bar, on the right** — not a bottom sheet, no dimmed
  background, no drag handle. It has a title row "Camera tools" with a **Done** button, then the rows: **Flash**,
  **Grid**, **Timer** (Off · 3s · 10s), **Ratio** (3:4 · 9:16 · 1:1), a "Pose guide" section with an eye row reading
  **Shown**/**Hidden**, **Opacity** with a "%" value and a slider, **Scale** (a second slider — the guide grows and
  shrinks about its centre), a **mirror** toggle for the guide, and **Line colour** with **Black** | **White** — the
  chosen colour carries a tick, not just a fill.
- [ ] Change **Timer**, **Ratio**, **Scale** and the guide **mirror** once each, then reopen the panel.
- [ ] **Expected:** every row still reads the value you set (in words, not just a different colour), the guide visibly grows
  / flips when you move Scale / mirror, and reopening the camera keeps all four.
- [ ] **Mirror is the guide only.** With the guide mirrored, check the live preview and then take one photo.
- [ ] **Expected:** only the pose **overlay** flips; the camera image behind it, and the saved photo, are exactly as they
  were — the Mirror row never mirrors your capture. (Front-camera capture mirroring is a different thing, §12.3.)

**Build 18 — the popover starts at Flash, and settings apply immediately.**
- [ ] **Build 18:** open the tools popover.
- [ ] **Expected:** it opens on its **first control (Flash)** — there is **no title row and no Done button** at all. Change
  **Flash**, **Grid**, **Mirror**, **Timer**, **Ratio** and **Scale** one at a time.
- [ ] **Expected:** each change takes effect **immediately** behind the popover (grid drawn, guide flipped / resized, the
  timer / ratio value showing in its row) — there is nothing to confirm and no save step.
- [ ] **Build 18:** tap outside the popover, then re-open it and repeat with the VoiceOver escape gesture.
- [ ] **Expected:** an outside tap dismisses it; the two-finger-scrub escape dismisses it too. No dark scrim is left behind,
  the camera stays usable, and re-opening lands on Flash again.

5. Tap anywhere outside the panel.
- [ ] **Expected:** it closes with no dark scrim left behind. **Done** also closes it (17 only — see the build 18 block). Turn
  **Grid** on → the framing grid is drawn over the preview; the panel stays open.
6. Set the text size to a large one (Settings → Accessibility → Display & Text Size → Larger Text), then reopen the
  camera with a pose chosen.
- [ ] **Expected:** the top bar grows, the pose name wraps onto a second line instead of being cut off, and the tools panel
  still opens **below** the bar — nothing overlaps, nothing is clipped.

## 4. Pose guide: placing it, drawing it, and keeping it while collapsed
- [ ] With a pose guide on screen, pinch to scale it, twist to rotate it and drag it somewhere else on the preview.
- [ ] **Expected:** the guide follows your fingers 1:1 and stays within sane bounds; the top bar, the strip and the bar
  underneath do not move while you do it.
- [ ] Open the tools panel and drag the opacity slider, then pick the other line colour.
- [ ] **Expected:** the guide updates live behind the panel (opacity and colour), the panel stays open, and the chosen
  colour shows a tick (not only a different fill).
- [ ] Collapse the strip with the **Poses** control.
- [ ] **Expected:** the guide stays exactly where it was — same size, position, opacity and colour; it does not blink, jump
  or disappear. Collapsing the strip is not the same thing as hiding the guide.
- [ ] Reopen the strip.
- [ ] **Expected:** the same guide is still there and still matches the last pose you picked.
- [ ] Open the tools panel and change the opacity slider and the line colour once, then collapse and reopen the strip.
- [ ] **Expected:** your opacity/colour choice is kept through the collapse (the rows still read the same "%" and the same
  ticked colour, and the guide is drawn with it).

## 5. Shutter and the capture snackbar
- [ ] Point at something with people in it and tap the shutter once.
- [ ] **Expected:** the shutter shows a spinner while the photo is being written and the strip / flip / tools are visibly
  unavailable; the preview comes back by itself, and a snackbar appears at the **bottom, directly above the control
  bar** — it never covers the shutter bar and never sits mid-screen. A status such as "Saving photo…" while the write is
  in flight is the board's behaviour (TC-CAM-026) — if the build shows nothing at all during the write, report it.
- [ ] **Expected:** the snackbar pairs a tone glyph with the words — a **check** for a save — and if Photos access was
  granted the text reads "Saved"; if it was not granted it reads "Saved to gallery. Allow Photos access to also save to
  your library."
- [ ] Tap **View** on the snackbar from that save.
- [ ] **Expected:** you land in the Gallery with the newest photo on screen.
- [ ] Capture again, wait ~5 seconds, then capture once more and tap the snackbar itself.
- [ ] **Expected:** left alone it goes away after a few seconds; tapping it dismisses it immediately; a new capture
  replaces the old text instead of stacking a second snackbar.
- [ ] Set **Timer → 3s** in the tools panel, then tap the shutter.
- [ ] **Expected:** a countdown (3 · 2 · 1) runs over the preview and the photo is taken at zero — not immediately.
- [ ] Repeat it and tap the countdown's cancel control before it reaches zero.
- [ ] **Expected:** the countdown stops, the shutter returns to normal, and **no** new photo appears in the Gallery.

## 6. Zoom is three pills, not one cycling button
- [ ] Look just above the strip (above the shutter bar when collapsed).
- [ ] **Expected:** a pill row **1x · 2x · 3x**; the current zoom is the highlighted pill (VoiceOver adds "selected").
- [ ] Tap **2x**.
- [ ] **Expected:** the preview zooms immediately on that tap; 2x becomes the highlighted pill (no cycling through 3x).
- [ ] Force-quit, reopen the camera.
- [ ] **Expected:** 2x is still the highlighted zoom.

**Build 18 — compact lens-aware zoom, the Poses control in that row, and a translucent bar.**
- [ ] **Build 18:** look at the zoom row and the bar it sits in.
- [ ] **Expected:** the zoom choices are **0.5x · 1x · 2x** (lens-aware — a phone whose lens cannot do 0.5x simply does not
  offer it; every phone offers 1x and 2x), each **compact (about 32–36 pt visible) with no background container**, still at
  least a 44 pt touch target, and the selected level is clearly visible without the container doing the work.
- [ ] **Expected:** the **⌃ Poses** button sits at the **right end of that same scale row**; the bottom bar itself is only
  thumbnail · shutter · flip.
- [ ] **Build 18:** point the camera at a **bright** scene (a white wall or a window) and read every control in the bottom
  bar.
- [ ] **Expected:** the bar is 50 % transparent over the preview and **all its text stays legible** — zoom labels, the Poses
  label, and the shutter / thumbnail / flip glyphs are clearly visible, not washed out by the bright background.
- [ ] **Build 18:** repeat over a **dark** scene (a shadowed corner or a dark object).
- [ ] **Expected:** still legible — no control disappears into the preview in either direction, and each control still taps
  on the first try (the translucent bar must not swallow touches).

## 7. Flip camera
- [ ] Tap the flip-camera button.
- [ ] **Expected:** the preview switches between the back and front camera within a second; the pose guide stays drawn in
  the same place; the shutter still works on the new camera.

## 8. Camera permission — the shared panel, and recovery via Settings
Two paths: the app has never asked for the camera, and the permission was refused. Reset between them when needed
(iOS Settings → the app → Camera).
1. On a clean install (the camera has never been asked for), open the camera.
- [ ] **Expected:** no viewfinder; one centred panel over a dark scrim — a camera glyph in a soft circle, the title
  "Camera access is off", the line "AI Pose needs the camera to show the pose guide. Turn it on in Settings.", and
  **exactly one** button: **Allow Camera**. No crash, no blank black screen.
- [ ] **Expected:** the pose strip and the **Poses** control are gone (with no camera there is nothing to place a pose
  on); the shutter and the flip control stay on the bar, and flip / zoom / tools are greyed out.
- [ ] Tap **Allow Camera**.
- [ ] **Expected:** the iOS camera prompt appears; allowing it brings the viewfinder up without leaving the screen, and the
  strip and the **Poses** control appear.
2. Switch Camera off for this app in iOS Settings, then reopen the camera.
- [ ] **Expected:** the same panel, but its one button now reads **Open Settings** (not "Allow Camera").
- [ ] Tap **Open Settings**.
- [ ] **Expected:** iOS Settings opens on this app's page. Turn Camera **on** there, then return to the app.
- [ ] **Expected:** the viewfinder comes alive on return (or after re-opening the camera) without reinstalling; capture
  then works.

## 9. Gallery — grid, ordering, filters (F10)
- [ ] After a capture, go to the Gallery tab.
- [ ] **Expected:** the new photo is the **first** item, under today's date header; the grid is exactly **3 columns**; there is no list/dense toggle and no photo-count text.
- [ ] **Expected:** the header shows only the Add pose (+) button (and nothing else).
- [ ] Repeat with three captures in a row.
- [ ] **Expected:** the newest is always first, each appears exactly once, and the grid never switches to 1 or 2 columns.
- [ ] Tap each filter chip in turn: **All · Today · 7 days · 30 days**.
- [ ] **Expected:** the grid narrows to that window and is regrouped by day; the chip you tapped reads as the active one; no
  count text appears anywhere. A window with no photos says "No photos in this filter" and offers **no** camera action
  (the All filter does).
- [ ] Read the section headers above the rows.
- [ ] **Expected:** one header per day, "Today"/"Yesterday" for recent days and a date like "Oct 28" otherwise, with no
  "n photos" count beside it.
- [ ] Set a large text size (Settings → Accessibility → Display & Text Size → Larger Text) and reopen Gallery.
- [ ] **Expected:** the grid is still 3 columns, the filter chips each take their own row, and the headers grow without
  clipping.
- [ ] Turn Wi-Fi and mobile data off and reopen Gallery (Add pose has to be available, i.e. the extract flag on).
- [ ] **Expected:** one offline banner **under the header, above the filter chips** — "You're offline. Add pose needs a
  connection." / "Your photos are on this device and still open normally." It says the *banner* is the only thing that
  needs the network: the grid is still there, every photo still opens, and nothing claims the photos failed. With Add
  pose hidden (extract flag off) no banner appears at all.

## 10. Photo detail — view, caption, swipe, share, save, delete, back
- [ ] Tap the newest photo in the grid.
- [ ] **Expected:** it opens full screen with a one-row header: Back on the left, **"Photo"** as the title, and a "…"
  options control on the right. The photo (not a grey box) fills the frame, and **no** "1 of 12" count line appears
  anywhere.
- [ ] Read the caption block directly under the photo.
- [ ] **Expected:** the pose name on its own line (omitted for a capture without a name), then one line like
  "Today · 11:08 · 1.2 MB" — a real local time and the real file size, with the size simply missing when the file cannot
  be read. No invented numbers, no count.
- [ ] Swipe left, then right.
- [ ] **Expected:** each swipe shows the next/previous photo, and the caption follows it (name, time, size); page dots
  appear only when there is more than one photo.
- [ ] Tap **Share**, wait, then dismiss the system sheet.
- [ ] **Expected:** the tray action shows "Preparing…" first, then the system share sheet with the photo; dismissing it
  returns to the same photo and the tray is usable again.
- [ ] Tap **Save** (Photos access granted).
- [ ] **Expected:** a snackbar directly above the action tray confirms the save; with Photos access denied the same
  snackbar explains it instead of failing silently.
- [ ] Tap **Delete**, then **Cancel**; then Delete → tap the dimmed background.
- [ ] **Expected:** both keep the photo and close the centred dialog ("Delete this photo?" / "It will be removed from this
  device. This can't be undone." with "Delete photo" first and "Cancel" under it).
- [ ] Look at the action tray.
- [ ] **Expected:** four actions in one row — **Share · Save · Add pose · Delete** — and no star/favourite anywhere (there
  is no star in the caption either). If Add pose has no destination in this build it is absent rather than dead.
- [ ] Tap **Add pose**.
- [ ] **Expected:** the Add pose entry opens from this photo; coming back leaves the photo and its caption unchanged.
- [ ] Tap the "…" options control → **Delete photo**.
- [ ] **Expected:** the same dialog opens from the menu; confirming **Delete photo** closes the viewer, the photo is gone
  from the grid, and it does not come back after a relaunch.
- [ ] Open another photo and tap **Back**.
- [ ] **Expected:** you are back on the grid where you left it (same scroll), dock usable.

## 11. Close camera returns to the previous screen
- [ ] Open a pose detail → "Use this pose" → camera → tap Close.
- [ ] **Expected:** you are back on **that same pose detail** (same pose name, "Use this pose" visible), not on Home.
- [ ] From Home, open the camera from the dock → Close.
- [ ] **Expected:** back on Home with the pose catalogue visible, camera gone.
- [ ] In the camera, tap the last-photo thumbnail on the bottom bar.
- [ ] **Expected:** you land in Gallery with the newest photo in view. Going back to the camera with the dock camera button and then tapping Close returns to **Home** (the camera only returns to a pose detail when it was opened from one).

## 12. What lands in the saved photo — ratio, zoom, front-camera mirror, guide scale (TC-CAM-029/030/031/032)
These four checks read the **photo file**, not the screen, so they are device-only. They prove the preview and the saved
image agree.
1. Ratio.
- [ ] In the tools panel set **Ratio → 1:1**, frame a scene with obvious edges, capture, and open the photo in Gallery,
  then in Photos.
- [ ] **Expected:** the preview was masked to a square and the saved photo **is** square — the crop is real, with no black
  bars baked into the image and no stretching. The Gallery cell shows it square too.
- [ ] Repeat with **9:16** (tall) and **3:4** (portrait).
- [ ] **Expected:** each saved photo matches the framing you saw when you pressed the shutter.
2. Zoom.
- [ ] Set **2x**, capture, then set **1x** and capture the same scene.
- [ ] **Expected:** the 2x photo is visibly tighter than the 1x one — the saved result uses the zoom the preview showed, it
  does not silently fall back to 1x.
3. Front camera.
- [ ] Switch to the front camera, hold something with text in view, capture, and read the saved photo.
- [ ] **Expected:** the photo is upright, mirrored the way the preview showed it, and the pose guide is **not** baked into
  the image.
4. Guide Scale and Mirror (screen only — these never touch the saved photo).
- [ ] With a pose guide on screen, move **Scale**, then toggle the guide's **Mirror** row.
- [ ] **Expected:** the guide grows/shrinks about its centre and flips horizontally; the camera preview and the saved
  photo are untouched; the Mirror row reads **Normal**/**Mirrored** in words and both settings survive closing and
  reopening the camera.
- [ ] Capture one photo with the guide mirrored, and open it.
- [ ] **Expected:** the guide is not in the photo at all (it is an overlay), and the photo is not mirrored by this control.

## 13. One-line verdict
- [ ] Everything above passed → reply "device pass" (add "paywall ok" for section 1 if you ran it).
- [ ] Something failed → reply with: the check number, what you saw, the screen recording, and the device/iOS/build line from the top of your notes.

Notes for QA triage (not for the product owner): automated equivalents live in
`mobile/iosApp/iosAppTests/Features/CameraFeatureTests.swift` (`CameraChromeTests`: the collapse/expand contract, the
collapsed state's persistence, the strip's content per picker state, the shared 72 pt permission panel, and the snackbar
pinned above the control bar on a rendered bitmap) and
`mobile/iosApp/iosAppTests/Features/GalleryFeatureTests.swift` (grid geometry, date sections, state panels, delete
success/failure, share preparation, AX layout) with `docs/qa/test-cases/camera-guide.md` (TC-CAM-012…032) and
`docs/qa/test-cases/capture-gallery.md` (TC-GAL-002…021).
Camera ids the new chrome gives flows (committed at `b8878da`): `camera.close`, `camera.choosePose`
(the pose title, opens the sheet), `camera.guideToggle` (eye, only with a guide), `camera.tools` + `camera.tools.done`,
`camera.zoom.1x|2x|3x`, `camera.status` (snackbar), `camera.permission` (the panel), `camera.pickerStripToggle`
(glyph/label/value per state), `camera.poseStrip` + `camera.poseStrip.card.<pose id>` + `camera.poseStrip.retry`; the
shutter, the gallery thumbnail and flip keep `camera.shutter` / `camera.gallery` / `camera.flip`.
Gallery ids (committed): `gallery.title`, `gallery.add-pose`, `gallery.filter.all|today|week|month`,
`gallery.empty.openCamera` + `.openCameraButton`, `gallery.empty.filter`, `gallery.error` + `.retry`,
`gallery.detail.back|title|options|share|save|delete|addPose`, `gallery.detail.caption` (one combined element),
`gallery.detail.deleteConfirm` (+ `.delete` / `.cancel`), `gallery.detail.failed` + `.failedRetry`,
`gallery.offline.banner` (all landed at `4ac4ddc`).
Not yet in the build (do not report as failures until Feature lands them; the cases exist and are named here so the two
artifacts stay in step): the pose sheet's **All / Saved** scope chips + "No saved poses yet" (TC-CAM-022/023), the picker's
**offline** banner and marked not-downloaded poses (TC-CAM-025), and the newly in-scope
**Timer / Ratio / guide Scale / guide mirror** controls (TC-CAM-027/028/029/030/031/032 — sections 3, 5 and 12 above are
written for the build that has them). Landed and checkable now (`4ac4ddc`): the Gallery offline banner (TC-GAL-018) and
the photo-detail caption block + Add pose tray action (TC-GAL-019/021). Out of scope for 1.1 only: the Gallery Star
action + Starred filter (TC-GAL-020, cut — no model).
Section numbers shifted with the redesign: the top bar is section 3, the zoom pills section 6, the Gallery is section 9,
photo detail is the new section 10, Close moved 8 → 11 and the saved-photo checks are the new section 12 (verdict is 13).
Map any older device note to the new number before filing it.
The paywall section's simulator equivalent is `docs/qa/prod-smoke/flows/S-05b-paywall-signed-in.yaml`, which is
BLOCKED-BY-ENV for the price assertion (S-05b) — that is exactly why section 1 is manual and on device.
