# On a real device — camera and paywall (product owner checklist)

The Simulator has no camera, so the camera sections below must be done on a physical iPhone with the Dev build
installed (`posing.camera.app`). Section 1 (paywall) needs a **production / TestFlight** build: a Release build on a
Simulator cannot resolve the real StoreKit products (see `docs/qa/prod-smoke` S-05 — the offering never loads and the
paywall falls back to "Plans are temporarily unavailable"), so the plan cards and their prices can only be verified
on device. Budget ~20 minutes. Record the screen (Control Centre → Screen Recording) for the whole run.

**Before you start**
- [ ] Close every other app; set brightness to ~70%; unlock rotation lock.
- [ ] Have one pose open at least once so a pose guide exists (Home → tap any card → wait for the photo) — only needed for the camera sections.
- [ ] You will need at least two poses for the strip, so also save a second pose if the catalogue is empty.
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
hidden gesture and no other way back.
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
The whole top chrome is one row. The eye only exists once a pose is chosen.
1. Open the camera with no pose chosen.
- [ ] **Expected:** a round **Close** (×) on the left, the title "Choose a pose" with a down chevron beside it, **no eye**,
  and the **tools** control (three sliders) on the right.
2. Tap the title.
- [ ] **Expected:** the "Choose a pose" sheet opens (search field + pose grid) with a **Done** button; nothing else on the
  camera moves.
- [ ] Pick a pose.
- [ ] **Expected:** the sheet closes, the title becomes that pose's name, and an **eye** control appears between the title
  and the tools control.
3. Tap the eye.
- [ ] **Expected:** the guide disappears and the glyph becomes a crossed-out eye (VoiceOver: "Show pose guide", value
  "Hidden"). Tap it again → the guide returns in the same place, size and colour.
4. Tap the tools control (three sliders).
- [ ] **Expected:** a **Camera tools** panel opens **under the top bar, on the right** — not a bottom sheet, no dimmed
  background, no drag handle. It has a title row "Camera tools" with a **Done** button, then the rows: **Flash**,
  **Grid**, a "Pose guide" section with an eye row reading **Shown**/**Hidden**, **Opacity** with a "%" value and a
  slider, and **Line colour** with **Black** | **White** — the chosen colour carries a tick, not just a fill.
5. Tap anywhere outside the panel.
- [ ] **Expected:** it closes with no dark scrim left behind. **Done** also closes it. Turn **Grid** on → the framing grid
  is drawn over the preview; the panel stays open.
6. Set the text size to a large one (Settings → Accessibility → Display & Text Size → Larger Text), then reopen the
  camera with a pose chosen.
- [ ] **Expected:** the top bar grows, the pose name wraps onto a second line instead of being cut off, and the tools panel
  still opens **below** the bar — nothing overlaps, nothing is clipped.

## 4. Pose guide drawn and kept while collapsed
- [ ] With a pose guide on screen (line drawing over the preview), collapse the strip with the **Poses** control.
- [ ] **Expected:** the guide stays exactly where it was — same size, position, opacity and colour; it does not blink, jump
  or disappear. Collapsing the strip is not the same thing as hiding the guide.
- [ ] Reopen the strip.
- [ ] **Expected:** the same guide is still there and still matches the last pose you picked.
- [ ] Open the tools panel and change the opacity slider and the line colour once, then collapse and reopen the strip.
- [ ] **Expected:** your opacity/colour choice is kept through the collapse (the rows still read the same "%" and the same
  ticked colour, and the guide is drawn with it).

## 5. Shutter and the capture snackbar
- [ ] Point at something with people in it and tap the shutter once.
- [ ] **Expected:** the shutter shows a spinner while the photo is being written, the preview comes back by itself, and a
  snackbar appears at the **bottom, directly above the control bar** — it never covers the shutter bar and never sits
  mid-screen.
- [ ] **Expected:** the snackbar pairs a tone glyph with the words — a **check** for a save — and if Photos access was
  granted the text reads "Saved"; if it was not granted it reads "Saved to gallery. Allow Photos access to also save to
  your library."
- [ ] Tap **View** on the snackbar from that save.
- [ ] **Expected:** you land in the Gallery with the newest photo on screen.
- [ ] Capture again, wait ~5 seconds, then capture once more and tap the snackbar itself.
- [ ] **Expected:** left alone it goes away after a few seconds; tapping it dismisses it immediately; a new capture
  replaces the old text instead of stacking a second snackbar.

## 6. Zoom is three pills, not one cycling button
- [ ] Look just above the strip (above the shutter bar when collapsed).
- [ ] **Expected:** a pill row **1x · 2x · 3x**; the current zoom is the highlighted pill (VoiceOver adds "selected").
- [ ] Tap **2x**.
- [ ] **Expected:** the preview zooms immediately on that tap; 2x becomes the highlighted pill (no cycling through 3x).
- [ ] Force-quit, reopen the camera.
- [ ] **Expected:** 2x is still the highlighted zoom.

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

## 9. Photo saved to Gallery — grid, ordering, opening (F10)
- [ ] After a capture, go to the Gallery tab.
- [ ] **Expected:** the new photo is the **first** item, under today's date header; the grid is exactly **3 columns**; there is no list/dense toggle and no photo-count text.
- [ ] **Expected:** the header shows only the Add pose (+) button (and nothing else).
- [ ] Tap the new photo.
- [ ] **Expected:** it opens full screen immediately, shows the photo (not a grey box), and swiping to the next photo works.
- [ ] Repeat with three captures in a row.
- [ ] **Expected:** the newest is always first, each appears exactly once, and the grid never switches to 1 or 2 columns.

## 10. Close camera returns to the previous screen
- [ ] Open a pose detail → "Use this pose" → camera → tap Close.
- [ ] **Expected:** you are back on **that same pose detail** (same pose name, "Use this pose" visible), not on Home.
- [ ] From Home, open the camera from the dock → Close.
- [ ] **Expected:** back on Home with the pose catalogue visible, camera gone.
- [ ] In the camera, tap the last-photo thumbnail on the bottom bar.
- [ ] **Expected:** you land in Gallery with the newest photo in view. Going back to the camera with the dock camera button and then tapping Close returns to **Home** (the camera only returns to a pose detail when it was opened from one).

## 11. One-line verdict
- [ ] Everything above passed → reply "device pass" (add "paywall ok" for section 1 if you ran it).
- [ ] Something failed → reply with: the check number, what you saw, the screen recording, and the device/iOS/build line from the top of your notes.

Notes for QA triage (not for the product owner): automated equivalents live in
`mobile/iosApp/iosAppTests/Features/CameraFeatureTests.swift` (`CameraChromeTests`: the collapse/expand contract, the
collapsed state's persistence, the strip's content per picker state, the shared 72 pt permission panel, and the snackbar
pinned above the control bar on a rendered bitmap) and `docs/qa/test-cases/camera-guide.md` (TC-CAM-012/013 — the ids
they were waiting on now ship: `camera.pickerStripToggle` (glyph/label/value per state), `camera.poseStrip` +
`camera.poseStrip.card.<pose id>` + `camera.poseStrip.retry`) / `capture-gallery.md` (TC-GAL-002 manual).
Other ids the new chrome gives flows: `camera.close`, `camera.choosePose` (the pose title, opens the sheet),
`camera.guideToggle` (eye, only with a guide), `camera.tools` + `camera.tools.done`, `camera.zoom.1x|2x|3x`,
`camera.status` (snackbar), `camera.permission` (the panel; the shutter, gallery thumbnail and flip keep their old
`camera.shutter` / `camera.gallery` / `camera.flip`). Section numbers shifted with the redesign: the top bar is a new
section 3 and the zoom pills a new section 6, so flip moved from 5 to 7 (the snackbar is still 5) — map any older device
note to the new number before filing it.
The paywall section's simulator equivalent is `docs/qa/prod-smoke/flows/S-05b-paywall-signed-in.yaml`, which is
BLOCKED-BY-ENV for the price assertion (S-05b) — that is exactly why section 1 is manual and on device.
