# On a real device — camera, gallery and paywall · release 1.1 (build 20)

The Simulator has no camera, so everything below has to be done on a physical iPhone with the **1.1 (20)** build installed.
Section 1 (paywall) needs the **TestFlight** build: a Release build on a Simulator cannot resolve the real StoreKit
products, so plan cards and prices can only be checked on a real install. Budget ~35 minutes and record the screen
(Control Centre → Screen Recording) for the whole run. Every step is one action and one result line — if a result line is
not what you see, stop and report that step number.

**Before you start**
- [ ] Close every other app; brightness ~70 %; rotation lock off.
- [ ] Open one pose at least once (Home → tap any card → wait for the photo) so a pose guide exists.
- [ ] Save a second pose, so the pose strip has something to switch to.
- [ ] Capture two or three photos — sections 6, 7, 8 and 12 check what lands in the **saved file**, and section 12 deletes one.
- [ ] Write down your model + iOS version + build number (Settings → About) at the top of your notes.
- [ ] **Launch the app with a non-English device language and a non-US region** (Settings → General → Language & Region:
  pick any other language and a region outside the US), then open it.
- [ ] **Expected:** the app **launches and stays up**, the Poses home renders and stays on screen — a plain sanity check,
  leave it running for a minute before switching back.
- [ ] Note for QA (not the product owner): if a launch ever dies, **check `log show` for
  "termination reported by launchd (2, 15, 15)" before filing a crash** — that is SIGTERM, not an app fault (a killed or
  timed-out `simctl launch --console` / `--console-pty` host process produces exactly this). Never launch through
  `simctl launch --console-pty` without keeping its host process alive for the whole session.

## 1. Paywall on device — paywall C, 1.1 (20) (TestFlight)
A Simulator cannot resolve real StoreKit products, so this section is the only place the real prices can be read. Cases:
TC-PAY-017/018/019 (and TC-PAY-014 for Restore) in `docs/qa/test-cases/paywall-purchase.md`.
- [ ] Install the **TestFlight 1.1 (20)** build and sign in with a real account.
- [ ] Open the paywall: tap the shutter while the gate is on, or Settings → Premium.
- [ ] **Expected:** the paywall opens with the **yearly card first and already selected**, and the monthly card under it —
  no "Plans are temporarily unavailable", no empty card, no spinner left behind (TC-PAY-018).
- [ ] Read both cards.
- [ ] **Expected:** each shows the store's **real localized price and period** for your region; the yearly card adds a
  **per-month breakdown**, and the saving badge is **computed from the two prices** (so it changes with the offering — a
  fixed "Save 33 %" on every store would be wrong). Nothing hardcoded, no invented discount (TC-PAY-018).
- [ ] Read the disclosure and the legal row without scrolling past them.
- [ ] **Expected:** all five mandatory points sit on this one surface — **price**, **billing period**, **auto-renews until
  cancelled**, **how to cancel** (Apple ID settings) — and **Terms of Use** and **Privacy Policy** both open when tapped
  (TC-PAY-019). If any one is missing or unreadable, that alone blocks shipping.
- [ ] Tap **Restore purchases** (do **not** buy unless you deliberately run a sandbox purchase).
- [ ] **Expected:** it answers — a previous real purchase restores access, otherwise it says there is nothing to restore —
  and the paywall stays usable (TC-PAY-014).
- [ ] On an **iPhone SE** (or the smallest screen you have), set Dynamic Type to **AX5** and open the paywall, then scroll it.
- [ ] **Expected:** plan cards, per-month line, saving badge, disclosure and the legal row (**Restore · Terms · Privacy**) are
  **all reachable by scrolling**, nothing is clipped or hidden under the pinned purchase button, and the **X** stays
  reachable (TC-PAY-017).
- [ ] Switch the device to **dark mode** and read the same screen.
- [ ] **Expected:** every price, the saving badge and the disclosure stay legible against the surface — no grey-on-grey
  small print, no badge that disappears (TC-PAY-017).
- [ ] **Purchase-failure path — needs a sandbox account** (sign in to a Sandbox tester in Settings → App Store, or use a
  TestFlight build's sandbox purchase): open the paywall, start a purchase and let it **fail** (cancel the sheet, or use a
  sandbox card that is declined).
- [ ] **Expected:** the failure is a settled state, not a dead screen — `paywall.status` says the purchase didn't go through,
  the plan card carries a **working retry** (`paywall.retry`) that starts a fresh store attempt, and **no premium is
  granted** (the shutter still opens the paywall) (TC-PAY-012).
- [ ] Tap **Try again** (`paywall.retry`) and watch the screen.
- [ ] **Expected:** the **real App Store sheet is presented again** for a second attempt (the Test Store does not re-show it
  in the same session, which is why the Simulator flow does not assert it), the paywall stays usable behind it, and nothing
  is charged until that sheet is confirmed (TC-PAY-012).
- [ ] Note for QA: this case is **BLOCKED (env) on the Simulator** — a simulator build shows no purchasable offering, so the
  failure path can only be walked here (TC-PAY-012 lives in `docs/qa/test-cases/paywall-purchase.md`).

## 2. Camera chrome — what changed in 23
- [ ] Open the camera from the dock and read the **top row**.
- [ ] **Expected:** a round **X** on the left, the **tools** button on the right, and (once a pose is chosen) an **eye** —
  there is no "Choose a pose" pill any more.
- [ ] Read the **preview**. It is full screen: the ratio frame spans the screen's width and everything outside the photo
  is dimmed (about 65 %), so what you see inside the frame is what the photo will contain.
- [ ] Read the row just above the bottom bar.
- [ ] **Expected:** one **continuous zoom slider** on the left (its value is a factor like `1.0×`; the old 0.5x/1x/2x
  pills are gone) and one **Poses** control at the right end of that row.
- [ ] Count the **Poses** controls.
- [ ] **Expected:** exactly **one**, at the right end of the zoom row — if a second one appears above the shutter, report
  it (it was a defect in the first 1.1 (18) dev builds).
- [ ] Look at the bottom bar itself.
- [ ] **Expected:** exactly three things — the last-photo thumbnail, the shutter and the flip-camera button — on a bar that
  is **see-through** (50 %) over the preview.
- [ ] Point the camera at a **bright** scene (a white wall or a window) and read every label in that bar.
- [ ] **Expected:** the bar is see-through and every label and glyph stays clearly legible — nothing washes out.
- [ ] Repeat over a **dark** scene (a shaded corner).
- [ ] **Expected:** still legible in the other direction, and each control still responds on the first tap.
- [ ] Tap the **tools** button.
- [ ] **Expected:** the panel opens **on its first row, Flash** — there is **no title row and no Done button**.
- [ ] Change **Flash**, then **Grid**, then **Timer**, then **Ratio** without closing the panel.
- [ ] **Expected:** each change takes effect immediately behind the panel (flash value, grid drawn, the new value shown in
  its own row) — nothing to confirm, nothing to save.
- [ ] Tap the preview well outside the panel; then re-open it and dismiss it with the two-finger scrub (VoiceOver escape).
- [ ] **Expected:** both dismiss it, no dark scrim is left behind, and re-opening lands on Flash again.

- [ ] Drag the **zoom** control to **0.5×**, then **2×**, then **3×** (a factor the lens cannot serve is simply not
  reachable — note which ones your iPhone offers).
- [ ] **Expected:** the slider reaches each factor it offers, the preview zooms with it, and a photo taken at that zoom
  **matches the preview** — same framing, no jump between what was framed and what was saved.
- [ ] Capture once at **3:4** and once at **9:16**, then open each photo in **Gallery**.
- [ ] **Expected:** each photo is **not rotated** and shows exactly what the preview framed — the crop matches the
  on-screen frame, the edges line up, and the **pose guide and the scrims are not baked into the photo**.

## 3. Picking a pose (the Browse card replaced the pill)
- [ ] Check the pose strip is expanded (rounded panel above the bar with pose thumbnails).
- [ ] **Expected:** the strip ends with a **Browse** card (magnifier icon, the word "Browse").
- [ ] Tap **Browse**.
- [ ] **Expected:** the "Choose a pose" sheet opens with a search field, **All / Saved** chips and a **Done** button.
- [ ] Switch **All → Saved → All**.
- [ ] **Expected:** the sheet re-filters in place, the active chip shows a tick, and the sheet never closes by itself.
- [ ] Type two nonsense letters into the search field, then tap the field's ✕.
- [ ] **Expected:** a "No poses match …" panel replaces the grid; clearing the search brings the grid straight back.
- [ ] Pick a pose from the sheet.
- [ ] **Expected:** the sheet closes, the guide switches to that pose and the pose name is no longer in the top bar (the
  guide itself and the eye are the only pose indicators now).
- [ ] Tap a **different card in the strip**.
- [ ] **Expected:** the guide switches immediately, the tick moves to that card, nothing else moves.
- [ ] Collapse the strip with **⌃ Poses**, then re-open it.
- [ ] **Expected:** collapsed = thumbnail · shutter · flip only, with the Poses button still there; re-opening restores the
  strip. Force-quit and reopen the camera → it comes back in the state you left.

- [ ] With a pose chosen, find the **Adjust guide** control in the top chrome and tap it.
- [ ] **Expected:** the guide-adjust sheet opens from that **visible** control (it must never require tapping the pose
  reference itself) and offers opacity, scale, line colour, the **Mirror** row and a **Reset** row, with **Done** to close.
- [ ] Change the line colour to yellow, flip the guide, then close and reopen the sheet.
- [ ] **Expected:** both changes are still there; **Reset** restores the guide's size (100 %) and leaves the colour and
  mirror choice alone.

## 4. Pose guide — placing it, and its rows in the panel
- [ ] With a guide on screen, pinch, twist and drag it.
- [ ] **Expected:** the guide follows your fingers 1:1 and stays within the preview; the bars do not move.
- [ ] Tap the **eye** in the top bar, then tap it again.
- [ ] **Expected:** the guide hides (crossed-out eye, "Show pose guide") and returns in the same place, size and colour.
- [ ] Open the tools panel and scroll inside it until the pose-guide section is on screen.
- [ ] **Expected:** the rows are all reachable by scrolling the panel if they sit below its edge — a row you cannot bring into
  view (or one that only reacts when you tap somewhere else) is a defect to report.
- [ ] Read its rows.
- [ ] **Expected:** Pose guide (Shown/Hidden), **Mirror**, **Opacity** with a %, **Scale** with a % and a **Reset**, and
  **Line colour Black | White** with a tick on the chosen colour.
- [ ] Toggle **Mirror**, then drag **Scale**, then tap **Reset**, then switch **Line colour**.
- [ ] **Expected:** the guide flips horizontally, grows/shrinks about its centre, snaps back on Reset, and redraws in the
  new colour — each change visible immediately behind the panel.
- [ ] Collapse the strip, then re-open it.
- [ ] **Expected:** the guide is untouched by the collapse — same size, position, flip, colour and opacity.

## 5. Timer — countdown and cancel
- [ ] In the tools panel set **Timer → 3s** and tap the shutter once.
- [ ] **Expected:** a countdown number with "Get ready" and a **Cancel** appears above the zoom row, and the photo is taken
  when it reaches zero — not when you pressed.
- [ ] Repeat with **Timer → 10s**, then tap **Cancel** before it reaches zero.
- [ ] **Expected:** the countdown stops, the camera returns to ready, and **no** new photo appears in the Gallery.
- [ ] Set **Timer → Off** and tap the shutter.
- [ ] **Expected:** the photo is taken instantly, with no countdown.

## 6. Ratio — the preview frame and the crop in the saved file
Build 20+: choosing a ratio **also reshapes the live preview viewport**, so check both halves — the frame you see and the
file you get. (Planned follow-up: the camera lane's pose-popup branch keeps this behaviour but sources the ratio from a
sheet — ids `TBD on build`, see `camera-guide.md` "Planned change".)
- [ ] Set **Ratio → 1:1** and look at the preview without capturing.
- [ ] **Expected (preview frame):** the live image is **square and masked** to that shape — no stretched faces, no letterbox
  bars inside a still-portrait frame — and the pose guide is not cropped or squashed by the change.
- [ ] Repeat for **9:16** and **3:4** and confirm the frame changes shape each time, then set **3:4** again.
- [ ] **Expected:** each ratio visibly changes the viewport; the choice survives leaving and reopening the camera.
The saved file is the second half of this section.
1. **1:1 (square).**
- [ ] Set **Ratio → 1:1**, frame a scene with obvious edges, capture.
- [ ] **Expected:** the preview was masked to a square and the saved photo **is** square — open the Gallery photo and its
  corners are cut, with no black bars baked in and no stretching.
- [ ] Grant Photos access, tap **Save** in the photo detail, then in Photos open the photo → **ⓘ**.
- [ ] **Expected:** the dimensions are a **square** (two equal numbers, e.g. 3024 × 3024 — your lens may differ; the shape
  is what matters).
2. **3:4 (portrait, the default).**
- [ ] Set **Ratio → 3:4**, capture the same scene, read the saved photo the same way.
- [ ] **Expected:** taller than wide (e.g. 3024 × 4032), the Gallery cell matches, and it is visibly less tall than the
  9:16 photo below.
3. **9:16 (tall).**
- [ ] Set **Ratio → 9:16**, capture, read the saved photo.
- [ ] **Expected:** clearly the tallest of the three (e.g. 2268 × 4032), no letterboxing, and the Gallery cell matches.
- [ ] Set **Ratio** back to **3:4** when you are done.

## 7. Zoom — 0.5x / 1x / 2x
- [ ] Read the zoom row.
- [ ] **Expected:** **0.5x · 1x · 2x** (a phone whose lens cannot do 0.5x shows only 1x · 2x), with the current level clearly
  marked; nothing is a background box.
- [ ] Tap **2x**, capture, then tap **1x** and capture the same scene.
- [ ] **Expected:** the preview zooms instantly on each tap and the 2x photo is visibly tighter than the 1x one — the saved
  file uses the zoom you saw, it does not fall back to 1x.
- [ ] Force-quit, reopen the camera.
- [ ] **Expected:** the zoom you left is still the marked one.

## 8. Mirror — two different checks, do both
The **Mirror** row flips the pose guide only. A front-camera **photo** is a separate, automatic behaviour.
- [ ] In the tools panel turn **Mirror** on, then capture one photo and open it.
- [ ] **Expected (guide only):** only the pose **overlay** flipped — the camera preview and the saved photo are unchanged,
  and the guide is not baked into the photo at all.
- [ ] Switch to the **front camera** and hold something obviously asymmetric — write `HELLO` on paper, or raise one hand
  on one side — so the first letter / your hand sits on a definite side of the frame.
- [ ] Look at the preview and note which side that is (the selfie preview shows you mirrored, like a mirror).
- [ ] Capture, then open the photo in **Gallery**, and in **Photos** as well if Photos access is on.
- [ ] **Expected (front camera, what-you-see-is-what-you-get):** the **saved photo has the same orientation as the
  preview** — the word reads the same way round and your hand is on the same side in the preview, in Gallery and in
  Photos. Nothing is flipped vertically, and the in-app copy and the Photos copy agree with each other.
- [ ] Switch back to the **rear camera** and shoot the same subject.
- [ ] **Expected (rear camera unchanged):** the saved photo keeps the real-world orientation — this is the control case, and
  the front-camera fix must not mirror it.
- [ ] Turn **Mirror** off (or **Reset** the guide) before you finish.

## 9. Shutter and the capture snackbar
- [ ] Tap the shutter on something with people in it.
- [ ] **Expected:** the shutter shows a spinner while the photo is written, the preview returns by itself, and a snackbar
  appears at the bottom **directly above the control bar** — never over the shutter, never mid-screen.
- [ ] Read the snackbar.
- [ ] **Expected:** a tone glyph beside the words — a **check** with "Saved" when Photos access is granted, otherwise "Saved
  to gallery. Allow Photos access to also save to your library."
- [ ] Tap **View**.
- [ ] **Expected:** you land in the Gallery on the newest photo.
- [ ] Capture again, wait ~5 seconds; then capture once more and tap the snackbar itself.
- [ ] **Expected:** it goes away by itself, tapping dismisses it immediately, and a new capture replaces the old text instead
  of stacking a second snackbar.

## 10. Camera permission panel — and getting back
- [ ] Remove camera access for this app (iOS Settings → the app → Camera), then open the camera.
- [ ] **Expected:** no viewfinder; one centred panel — camera glyph, "Camera access is off", "AI Pose needs the camera to
  show the pose guide. Turn it on in Settings.", one primary button (**Open Settings** after a refusal, **Allow Camera**
  when the app has never asked) and a secondary **Not now**.
- [ ] **Expected:** the pose strip and the Poses button are gone (no camera = nothing to place a pose on); shutter and flip
  remain, flip / zoom / tools are greyed out.
- [ ] Tap **Not now**.
- [ ] **Expected:** the camera closes and you are back where you opened it — not parked on a dead screen.
- [ ] Re-open the camera, tap **Open Settings**, switch Camera on there, come back.
- [ ] **Expected:** the viewfinder comes alive without reinstalling, and capture works again.

## 11. Gallery — grid, filters, offline
- [ ] Open the Gallery tab.
- [ ] **Expected:** the newest photo is first under today's date header, the grid is exactly **3 columns**, and the header
  shows only the **Add pose (+)** button — no list/dense toggle, no photo count.
- [ ] Tap each filter chip: **All · Today · 7 days · 30 days**.
- [ ] **Expected:** the grid narrows to that window and regroups by day; a window with nothing says "No photos in this
  filter" and offers no camera action (All does).
- [ ] Read the date headers.
- [ ] **Expected:** one header per day — "Today" / "Yesterday", otherwise a short date — never "n photos".
- [ ] Turn Wi-Fi and mobile data off and reopen the Gallery.
- [ ] **Expected:** one banner under the header — "You're offline. Add pose needs a connection." / "Your photos are on this
  device and still open normally." — while the photos still open normally. (With Add pose unavailable no banner appears.)
- [ ] Set a large text size (Settings → Accessibility → Display & Text Size) and reopen the Gallery.
- [ ] **Expected:** the grid stays 3 columns, the filter chips each take a row, and the headers grow without clipping.

## 12. Photo detail — caption, share, save, delete
- [ ] Tap the newest photo.
- [ ] **Expected:** it opens full frame with **Back**, the title **"Photo"** and a **…** options control on one row; no
  "1 of 12" line anywhere.
- [ ] Read the block under the photo.
- [ ] **Expected:** the pose name on its own line (missing for an unnamed capture) and one meta line like
  "Today · 11:08 · 1.2 MB" — real time, real size, no invented numbers.
- [ ] Swipe left and right.
- [ ] **Expected:** the next/previous photo shows and the caption follows it; page dots appear only when there is more than
  one photo.
- [ ] Read the action tray.
- [ ] **Expected:** four actions — **Share · Save · Add pose · Delete** — and no star/favourite anywhere.
- [ ] Tap **Share**, then dismiss the system sheet; tap **Save**.
- [ ] **Expected:** Share shows "Preparing…" then the system sheet and returns to the same photo; Save confirms in a snackbar
  above the tray (with Photos access denied the same snackbar explains it instead of failing silently).
- [ ] Tap **Delete** → **Cancel**; then Delete → tap the dimmed background; then **…** → **Delete photo**.
- [ ] **Expected:** the first two keep the photo, the menu opens the same centred dialog ("Delete this photo?"), and
  confirming removes it from the grid for good.
- [ ] Tap **Add pose** in the tray.
- [ ] **Expected:** the Add pose entry opens from this photo and coming back leaves the photo and caption as they were.
- [ ] Open another photo and tap **Back**.
- [ ] **Expected:** back on the grid where you left it, dock usable.

## 13. Close returns where you came from
- [ ] Open a pose detail → "Use this pose" → camera → tap **X**.
- [ ] **Expected:** you are back on **that same pose detail** (same pose name, "Use this pose" visible), not on Home.
- [ ] Open the camera from the dock → **X**.
- [ ] **Expected:** back on Home with the catalogue visible.
- [ ] In the camera, tap the **last-photo thumbnail** in the bottom bar.
- [ ] **Expected:** the Gallery opens on the newest photo; the dock camera then closes back to **Home** (the camera only
  returns to a pose detail when it was opened from one).

## 14. Verdict
- [ ] Everything above passed → reply "**device pass 1.1 (18)**" (add "paywall ok" if you ran section 1).
- [ ] Something failed → reply with **the section number, what you saw instead, the screen recording, and your device /
  iOS / build line**.

If you are on an **older build**, several things look different and are expected: before 23 the preview was not full
screen and the zoom was a row of 0.5x/1x/2x pills; before 21 the guide's controls sat in the tools popover. This page
describes **build 23** — check the build number in Settings → About before reporting a difference.

Notes for QA triage (not for the product owner): the camera chrome in build 23 is verified in source at `7fa7681`.
Retired — never assert them: `camera.tools.done`, `camera.tools.poseGuide`, `camera.tools.mirror`,
`camera.tools.mirror.switch`, `camera.tools.opacity`, `camera.tools.scale`, `camera.tools.lineColor.black|white` and
every `camera.zoom.0.5x|1x|2x|3x`. In their place: zoom is the continuous `camera.zoom.slider` (value like `1.0×`); the
tools popover is `camera.tools.popover` with flash chips `camera.tools.flash.off|auto|on`, the grid switch, timer chips
`camera.tools.timer.off|3s|10s` and ratio chips `camera.tools.ratio.3x4|1x1|9x16` (no title, no Done; closes on its own
control or an outside tap); the guide's controls live in the `camera.guideAdjust` sheet — opened by tapping the pose
reference itself — with `camera.guideAdjust.opacity|scale|flip|done` and `.lineColor.pink|black|yellow|green`. The
preview is full screen with a full-width ratio frame, everything outside the frame dimmed to 65 %, and the guide,
scrims and gestures clipped to it. `camera.choosePose` is still the Poses chip and its value is the selected pose name
(or "None selected"); the strip and `camera.pickerStripToggle` are retired.
