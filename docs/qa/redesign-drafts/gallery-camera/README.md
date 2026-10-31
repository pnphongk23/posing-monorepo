# Build 17 (release 1.1) redesign — Gallery / photo detail + Camera drafts

Draft Maestro flows for the redesigned cases in [camera-guide.md](../../test-cases/camera-guide.md) and
[capture-gallery.md](../../test-cases/capture-gallery.md). They are NOT in `mobile/iosApp/maestro/flows/`, so the
traceability checker ignores them, and **nothing here has been run on a simulator yet**.

The camera ids these flows use are now **committed** (`b8878da`, `feat(ios): camera redesign with a collapsed picker
strip`) — verified against the source at that sha: `camera.close`, `camera.choosePose`, `camera.guideToggle`,
`camera.gallery`, `camera.flip`, `camera.pickerStripToggle`, `camera.poseStrip`, `camera.poseStrip.retry`,
`camera.poseStrip.card.<poseId>`, `camera.zoom.<1x|2x|3x>`, `camera.status`, `camera.permission`, `camera.tools` +
`camera.tools.*` + `camera.tools.done`, `camera.shutter`, `camera.poseGuide`, and `posePicker.search|searchClear|grid|
state|close`. What is left is a **runnable build** (`/tmp/ai-pose-lane2-app-1.1/dev17/posing.app` — release **1.1 (17)**, not 1.2;
the path is confirmed by the QA lead) and a green run on lane 2 before any of them is promoted.

Promotion checklist (same as `../jobs-add-pose/README.md`): flip the doc row from `pending —` to
`automated: <file>`, keep `tags: [<TC-ID>, …]`, rewrite the `runFlow` paths from
`../../../../mobile/iosApp/maestro/subflows/…` to `../subflows/…`, run it green on lane 2, then commit flow + doc with
one explicit pathspec.

| Case | Draft | Blocked on |
|---|---|---|
| TC-CAM-006 | `flows/TC-CAM-006-permission-panel.yaml` | a build to run it on. Only the *refused* branch is expressible on the Simulator (Maestro writes the TCC answer, so `.notDetermined` — and the "Allow Camera" button — is unreachable); the panel's action has no id (request 2), so it matches "Open Settings" by text |
| TC-CAM-012 | `flows/TC-CAM-012-collapse-and-reopen-strip.yaml` | a build to run it on. Asserts the strip's presence *and* the control's state label ("Hide pose picker" ↔ "Show pose picker") |
| TC-CAM-013 | `flows/TC-CAM-013-guide-kept-while-collapsed.yaml` | a build to run it on. Proves the guide is still drawn through the collapse; *which* pose is CAM-007/CAM-011's job |
| TC-CAM-014 | `flows/TC-CAM-014-topbar-eye-and-title.yaml` | a build to run it on. Also asserts the eye's label flips to "Show pose guide" and that the title pill opens the sheet |
| TC-CAM-015 | `flows/TC-CAM-015-tools-panel-done.yaml` | a build to run it on |
| TC-CAM-016 | `flows/TC-CAM-016-zoom-pills.yaml` | a build to run it on; **half the case stays manual** — `camera.zoom.<label>` carries `.isSelected` but no accessibilityValue, so a flow cannot read which pill is current (request 1) |
| TC-CAM-018 | `flows/TC-CAM-018-permission-hides-strip.yaml` | a build to run it on; needs `permissions: camera: deny`, whose effect on `CameraPermissionState` must be confirmed on the first run |
| TC-CAM-019 | `flows/TC-CAM-019-collapse-survives-relaunch.yaml` | a build to run it on |
| TC-CAM-021 | `flows/TC-CAM-021-picker-search-no-match.yaml` | a build to run it on; needs the live catalogue (it waits for `posePicker.grid` first), so it is network-dependent like the other catalogue flows |
| TC-GAL-010 | `flows/TC-GAL-010-filter-empty-state.yaml` | a build to run it on (ids committed long before, no fixture needed — an empty gallery is the state under test) |

Gallery ids landed at `4ac4ddc` (`gallery.offline.banner`, `gallery.detail.caption`, `gallery.detail.addPose`, tray keeps
`share/save/delete`). None of them yields a flow yet: the caption and the tray need a photo in the database, and the
offline banner rides `NWPathMonitor`, which Maestro cannot drive. Those two cases (TC-GAL-018/019) and the tray action
(TC-GAL-021) are proven by `GalleryFeatureTests` plus the device run, and would become flows with the fixture + offline
seam asked for in `capture-gallery.md` "Requests to Feature" #1/#7.

Boards used: `/tmp/ds-261030/export-c/05-camera-collapsed.png`, `05-camera-collapsed-dark.png`,
`07-gallery-grid-ax3.png`, `07-gallery-grid-dark.png`, plus `FEEDBACK-261031.md` (F3, F4, F5, F10, F12).

## Waiting on ids (cases written, no draft yet)
Timer, Ratio, guide Scale and guide mirror are **in scope for 1.1** (owner decision, 20:50) but are not in committed
source, so these cases have no draft:

| Case | Needs |
|---|---|
| TC-CAM-027 (Timer + Ratio rows) | `camera.tools.timer`, `camera.tools.ratio` + a readable value per row |
| TC-CAM-028 (countdown + cancel) | `camera.timer.countdown`, `camera.timer.cancel` — the countdown UI may render without a feed, so this one is intended to become a draft flow |
| TC-CAM-032 (guide Scale + mirror) | `camera.tools.scale`, `camera.tools.mirror` + readable values |

TC-CAM-029/030/031 (saved-image crop, zoom and front-camera mirroring) can never be a flow — there is no capture on the
Simulator — and live in [docs/qa/camera-device-checklist.md](../../camera-device-checklist.md) §12.

Device-only cases (capture snackbar, the first-run "Allow Camera" branch, real photos) are not drafted here: they are
walked through in [docs/qa/camera-device-checklist.md](../../camera-device-checklist.md) and cannot be a Simulator flow
without the fixture seams listed in each doc's "Requests to Feature".

Run one against the lane-2 simulator once the QA lead names the build:

```
maestro --device <CF871F97 udid> test -e APP_ID=posing.camera.app \
  docs/qa/redesign-drafts/gallery-camera/flows/TC-GAL-010-filter-empty-state.yaml
```
