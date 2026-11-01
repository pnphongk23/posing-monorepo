# BUG camera-18-06 — Gallery → Add pose shows the sign-in prompt while the user IS signed in

- **Reporter:** user on a real device, **build 18** (1.1 (18)).
- **Severity:** high — the Add pose flow is blocked for signed-in users; the app asks for a sign-in the user already has.
- **Steps (reproduce, signed in):**
  1. Sign in with a real account (Settings → Account, or any surface that accepts a session).
  2. Open the **Gallery** tab.
  3. Tap **Add pose (+)** in the Gallery header (`gallery.add-pose`).
- **Expected:** the **Add pose form** opens directly — the photo picker is the next step
  (`addPose.title` / `addPose.photoPicker`), and **no** sign-in prompt appears, because the user is signed in.
- **Actual:** a **sign-in prompt** appears on top instead of the form (the "Sign in" sheet — `signin.emailEntry` /
  `signin.apple` / `Continue with Apple`, its own `sign-in.retry` card on failure). The user has to sign in again, or cannot
  reach the form at all.
- **Second entry point:** the same action exists in the **photo detail tray** (`gallery.detail.addPose`) — it must open the
  form directly too, under the same signed-in condition.
- **Signed-out behaviour must stay:** signed out, the same two entries **should** ask for a sign-in — that half is
  TC-GAL-024 and is not a defect.
- **Ids to assert:** form present → `addPose.title` / `addPose.photoPicker`; prompt absent → `signin.emailEntry`,
  `signin.apple` (there is no container id on the prompt; `paywall.signin.sheet` belongs to the paywall's own sheet, not
  this one).
- **Flows (held for dev19, `docs/qa/redesign-drafts/gallery-camera/flows/`):**
  `TC-GAL-022-gallery-add-pose-signed-in.yaml` (header entry),
  `TC-GAL-023-photo-detail-add-pose-signed-in.yaml` (tray entry — needs a photo in the gallery, which the Simulator cannot
  produce, so it is seed/device-dependent), and `TC-GAL-024-gallery-add-pose-signed-out.yaml` (the prompt is expected).

## Status
- **Fix on main:** `4cde9d9` (fix(ios): stop the gallery Add pose entry prompting a signed-in user to sign in) — **not yet verified**: needs the dev19 run (and, for the capture/guide
  defects, the device run).
- **Evidence:** the screenshots/hierarchy dumps quoted above were captured under `/tmp/qa-cam-1.1-18/`, which the
  2026-11-01 reboot wiped. The path strings are kept as the historical record; from dev19 on, artefacts that must
  survive a reboot live in `docs/qa/redesign-drafts/gallery-camera/evidence/` (repo) instead of `/tmp`.
