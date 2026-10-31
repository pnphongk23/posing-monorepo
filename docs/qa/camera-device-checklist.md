# Camera on a real device — product owner checklist

The Simulator has no camera, so everything below must be done on a physical iPhone with the Dev build installed
(`posing.camera.app`). Budget ~15 minutes. Record the screen (Control Centre → Screen Recording) for the whole run.

**Before you start**
- [ ] Close every other app; set brightness to ~70%; unlock rotation lock.
- [ ] Have one pose open at least once so a pose guide exists (Home → tap any card → wait for the photo).
- [ ] Note your device model + iOS version + build number (Settings → About) at the top of your notes.

## 1. Collapsed / reopened pose strip (F12)
1. From Home, tap the camera button in the bottom dock. The camera opens **expanded**.
- [ ] **Expected:** a horizontal strip of pose thumbnails sits above the bottom control bar, and a "Poses" control shows a **down** chevron with the label "Hide pose picker".
2. Tap that "Poses" control.
- [ ] **Expected:** the strip disappears; only the last-photo thumbnail, the shutter and the flip-camera button remain on the bottom bar; the same "Poses" control is still there with an **up** chevron and the label "Show pose picker".
3. Tap "Poses" again.
- [ ] **Expected:** the strip comes back above the control bar, in the same order, and nothing else moves.
4. Force-quit the app, reopen it, open the camera again.
- [ ] **Expected:** the camera remembers the last state (if you left it collapsed, it opens collapsed).

## 2. Pose guide drawn and kept while collapsed
- [ ] With a pose guide on screen (line drawing over the preview), collapse the strip.
- [ ] **Expected:** the guide stays exactly where it was — same size, position, opacity and colour; it does not blink, jump or disappear.
- [ ] Reopen the strip.
- [ ] **Expected:** the same guide is still there and still matches the last pose you picked.
- [ ] Move the opacity slider and change the line colour once, then collapse and reopen.
- [ ] **Expected:** your opacity/colour choice is kept through the collapse.

## 3. Shutter and capture snackbar
- [ ] Point at something with people in it and tap the shutter once.
- [ ] **Expected:** the screen freezes for a moment, a captured image is saved, and a short message appears at the **bottom, directly above the control bar** — it never covers the shutter and never sits mid-screen.
- [ ] **Expected:** if Photos access was granted the message reads "Saved"; if it was not granted it reads "Saved to gallery. Allow Photos access to also save to your library."
- [ ] Wait ~3 seconds without touching anything.
- [ ] **Expected:** the message disappears by itself. (Tapping it also dismisses it.)

## 4. Flip camera
- [ ] Tap the flip-camera button.
- [ ] **Expected:** the preview switches between the back and front camera within a second; the pose guide stays drawn in the same place; the shutter still works on the new camera.

## 5. Camera permission denied — and recovery via Settings
Do this on a fresh install, or reset it first (iOS Settings → the app → Camera → off is enough).
- [ ] Open the camera with permission off.
- [ ] **Expected:** no viewfinder; a panel titled "Camera access is off" with an "Open Settings" button and a short explanation. No crash, no blank black screen.
- [ ] Tap "Open Settings".
- [ ] **Expected:** iOS Settings opens on this app's page.
- [ ] Turn Camera **on** there, then return to the app.
- [ ] **Expected:** the viewfinder comes alive on return (or after re-opening the camera) without reinstalling; capture then works.

## 6. Photo saved to Gallery — grid, ordering, opening (F10)
- [ ] After a capture, go to the Gallery tab.
- [ ] **Expected:** the new photo is the **first** item, under today's date header; the grid is exactly **3 columns**; there is no list/dense toggle and no photo-count text.
- [ ] **Expected:** the header shows only the Add pose (+) button (and nothing else).
- [ ] Tap the new photo.
- [ ] **Expected:** it opens full screen immediately, shows the photo (not a grey box), and swiping to the next photo works.
- [ ] Repeat with three captures in a row.
- [ ] **Expected:** the newest is always first, each appears exactly once, and the grid never switches to 1 or 2 columns.

## 7. Close camera returns to the previous screen
- [ ] Open a pose detail → "Use this pose" → camera → tap Close.
- [ ] **Expected:** you are back on **that same pose detail** (same pose name, "Use this pose" visible), not on Home.
- [ ] From Home, open the camera from the dock → Close.
- [ ] **Expected:** back on Home with the pose catalogue visible, camera gone.
- [ ] In the camera, tap the last-photo thumbnail on the bottom bar.
- [ ] **Expected:** you land in Gallery with the newest photo in view. Going back to the camera with the dock camera button and then tapping Close returns to **Home** (the camera only returns to a pose detail when it was opened from one).

## 8. One-line verdict
- [ ] Everything above passed → reply "camera device pass".
- [ ] Something failed → reply with: the check number, what you saw, the screen recording, and the device/iOS/build line from the top of your notes.

Notes for QA triage (not for the product owner): automated equivalents live in
`mobile/iosApp/iosAppTests/Features/CameraFeatureTests.swift` (`CameraChromeTests`) and
`docs/qa/test-cases/camera-guide.md` (TC-CAM-012/013 pending ids) / `capture-gallery.md` (TC-GAL-002 manual).
