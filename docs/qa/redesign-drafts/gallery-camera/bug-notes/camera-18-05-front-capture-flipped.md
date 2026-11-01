# BUG camera-18-05 — front-camera captures are saved FLIPPED relative to the preview

- **Reporter:** user on a real device, **build 18** (1.1 (18)).
- **Severity:** high — the saved photo does not match what the user framed; for a selfie the mirrored preview is the whole
  point, so the result reads as "wrong way round" text, hair parting and hand dominance.
- **Steps (reproduce):**
  1. Open the camera and switch to the **front camera**.
  2. Hold an obviously asymmetric subject — a word on a sheet, or one hand raised on one side (`HELLO` written on paper
     works well: the first letter must sit on the same side in the preview and in the result).
  3. Note the preview: a selfie-style **mirrored** view (you see yourself as in a mirror).
  4. Tap the shutter, then open the photo in **Gallery** and, with Photos access on, in **Photos**.
- **Expected (WYSIWYG):** the saved photo is the image the preview showed — same left/right orientation, same readable text
  direction, no vertical flip. The same rule must hold when the photo is saved to Photos as well as in-app.
- **Actual:** the saved image is **flipped** relative to the preview — the subject's handedness and any text appear reversed
  from what the preview showed (reported by the user; the device checklist now carries the exact comparison).
- **Not affected / must stay unchanged:** **rear-camera** captures — the same asymmetric subject shot on the back camera must
  keep its real-world orientation; the fix must not mirror the rear path.
- **Device checklist item:** §8 "Mirror — two different checks", the front-camera half (compare preview vs Gallery vs
  Photos, then repeat on the rear camera).
- **Test case:** `docs/qa/test-cases/camera-guide.md` **TC-CAM-035** (device-only; no Simulator capture exists, so no Maestro
  flow). The regression should carry a unit/rendering test — Feature to name it; the natural seam is the capture pipeline's
  image-orientation step (front vs rear), asserted on a known asymmetric fixture instead of a device.
- **Note:** this is a *capture* defect. It is unrelated to the tools' **Mirror** row (`camera.tools.mirror.switch`), which
  flips the pose guide overlay only — see the checklist §8 wording and camera-18-04.
