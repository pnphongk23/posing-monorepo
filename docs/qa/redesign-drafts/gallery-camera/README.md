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
| TC-CAM-022 | `flows/TC-CAM-022-picker-scope-chips.yaml` | a build to run it on (ids landed `a03d03a`: `posePicker.scope` + `.all`/`.saved`, each chip reports a value `Selected`) |
| TC-CAM-023 | `flows/TC-CAM-023-saved-scope-empty.yaml` | a build + a **signed-in account with zero saved poses**; the empty panel is wrapped in a `runFlow: when`, so the flow only asserts it when the account really is empty |
| TC-CAM-024 | `flows/TC-CAM-024-permission-not-now.yaml` | a build to run it on (ids landed `a03d03a`: `camera.permission`, `camera.permission.notNow`); relies on `permissions: camera: deny` producing `.denied` |
| TC-CAM-032 | `flows/TC-CAM-032-guide-mirror.yaml` | a build to run it on (ids landed `da61534`: row `camera.tools.mirror`, switch `camera.tools.mirror.switch` with value "Mirrored"/"Normal") |
| TC-CAM-033 | `flows/TC-CAM-033-saved-scope-signed-out.yaml` | a build to run it on, signed out (clean launch, no credentials): `posePicker.saved.signIn` landed `a03d03a` |
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

## Run plan for the 1.1 builds (lead-confirmed shas)
The Dev **1.1 (17)** Simulator app is built from `a03d03a`. A draft is promoted into `maestro/flows/` only when every id
it names exists in the source at that sha (verified with `git grep` on the tree, dynamic ids checked as templates).

**Build-18 camera changes landed at `d001b80` — the hold is released.** Verified in that source: `camera.tools.done` is
retired (popover starts at Flash, no title, instant apply, outside tap / VoiceOver escape dismisses), `camera.choosePose`
survives as the strip's **Browse card** (opens the picker sheet, only while the strip is expanded),
`camera.pickerStripToggle` sits at the right end of the scale row, and zoom is lens-aware (`camera.zoom.0.5x|1x|2x`; the
Simulator offers 1x/2x only). Every affected draft was reworked in the same pass (Done → outside tap, strip-expanded
Browse) and only needs the **18** app to run.

| Draft | Build 17 (`a03d03a`) | Why |
|---|---|---|
| TC-CAM-006, 012, 013, 016, 018, 019, 024 · TC-GAL-010 | **promote + run** | every id is in `b8878da` / `a03d03a` / `4ac4ddc` **and** none of them touches `camera.choosePose` / `camera.tools.done` |
| TC-CAM-014, 015, 021, 022, 023, 032, 033 | reworked, **run on the 18 app** | they use the build-18 interaction: Browse card instead of the pill, outside tap instead of Done |
| TC-CAM-027 (timer + ratio rows) | run on the 18 app | ids landed `117b8bb`, not in 17 |
| TC-CAM-032 (guide mirror) | **run on 18** | `da61534` (Mirror) is not in `a03d03a` |
| TC-CAM-023 (Saved scope empty) | stays a draft | needs a signed-in account with an empty saved collection; the assertion is guarded, so a credential-free run proves nothing |
| TC-CAM-027 / 028 / 034 (Timer, Ratio, guide Scale) | run on 18 | ids not landed yet |
| TC-GAL-018 / 019 / 021 | device run | need photos in the database + an offline seam |

The Simulator has **no camera feed**: the camera flows assert chrome, ids, labels and state words (which is exactly what
this build's redesign changed). Anything that needs a captured frame — ratio crop, zoom at capture, front-camera
mirroring, the capture snackbar — is device-checklist work (§5, §12).

## Run log — 1.1 (17), build at `a03d03a`, lane-2 CF871F97, 2026-11-01 00:3x
Promoted and run (all **PASS**): TC-CAM-006, 012, 013, 016, 018, 019, 024 + TC-GAL-010 — 8 flows, screenshots in
`/tmp/qa-cam-1.1-17/shots/` (kept under `/tmp/qa-*` per the lane-2 disk rule). TC-CAM-016 failed on its first attempt at the relaunch step with "app crashed or stopped"; there is **no
`posing.camera.app` crash report**, and a SpringBoard crash lands at the same minute (00:30:52) — an environment hiccup, not
the app: the rerun passed end to end. Everything else on this build (camera chrome, picker scopes, not-now, gallery empty/
filter states) behaved as the cases expect.

Still drafts: TC-CAM-014, 015, 021, 022, 023, 032, 033 (held — they tap `camera.choosePose` / `camera.tools.done`, both
removed in build 18) and the device-only cases (Gallery caption/offline/tray, Timer/Ratio/Scale, saved-image checks).

## Run log — 1.1 (18), dev18, lane-2 CF871F97, 2026-11-01 02:4x–03:1x
Promoted and run 21 flows (12 live + 9 new): **PASS** TC-CAM-006/007/009/012/013/015/016/018/019/024/027 + TC-GAL-001 +
TC-GAL-010; **FAIL** TC-CAM-001/004/011/014/021/022/033 (one app bug: no reachable entry to the picker sheet) and
TC-CAM-032 (clipped pose-guide rows). TC-CAM-016 and TC-CAM-018 each failed once and passed on the single rerun (flaky
zustand of the shared sim, no app crash report). Bugs filed in `bug-notes/` (4 files). Evidence:
`/tmp/qa-cam-1.1-18/shots/` + the probe screenshots and hierarchy dumps beside it.

## Fix status for the six filed defects (verification pending dev19)
| Bug | Fix on main | Verifies with |
|---|---|---|
| camera-18-01 duplicate Poses control | `7153c95` | TC-CAM-012/019 (and the checklist "exactly one Poses" step) |
| camera-18-02 picker sheet unreachable | `17fdd9f` | TC-CAM-001/004/011/014/021/022/033 |
| camera-18-03 Timer/Ratio option ids | `22c9c83` | TC-CAM-027 (back on ids) |
| camera-18-04 popover guide rows clipped | `2bf15e7` | TC-CAM-032 (+ TC-CAM-003/034 on device) |
| camera-18-05 front capture flipped | `48c1222` | TC-CAM-035 (device) |
| camera-18-06 Gallery Add pose sign-in prompt | `4cde9d9` | TC-GAL-022/023 (drafts), TC-GAL-024 (signed-out stays) |

**Evidence policy (after the 2026-11-01 reboot wiped `/tmp`):** screenshots and hierarchy dumps for future runs go to
`docs/qa/redesign-drafts/gallery-camera/evidence/<build>/` in the repo; the older `/tmp/qa-cam-1.1-18/` paths quoted in the
bug notes and the 1.1 (18) run log are historical only and no longer resolve.

## Waiting on ids (cases written, no draft yet)
Guide **mirror** is in committed source (`da61534`) and is drafted (`TC-CAM-032-guide-mirror.yaml`). Timer, Ratio and
guide **Scale** are in scope for 1.1 but still unlanded, so these cases have no draft:

| Case | Needs |
|---|---|
| TC-CAM-027 (Timer + Ratio rows) | `camera.tools.timer`, `camera.tools.ratio` + a readable value per row |
| TC-CAM-028 (countdown + cancel) | `camera.timer.countdown`, `camera.timer.cancel` — the countdown UI may render without a feed, so this one is intended to become a draft flow |
| TC-CAM-034 (guide Scale) | `camera.tools.scale` + a readable value |

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
