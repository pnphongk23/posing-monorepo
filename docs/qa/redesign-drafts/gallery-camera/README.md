# Build 17 redesign — Gallery / photo detail + Camera drafts

Draft Maestro flows for the redesigned cases in [camera-guide.md](../../test-cases/camera-guide.md) and
[capture-gallery.md](../../test-cases/capture-gallery.md). They are NOT in `mobile/iosApp/maestro/flows/`, so the
traceability checker ignores them, and **nothing here has been run on a simulator yet** (the QA lead names the build
first).

They are here for two different reasons:

- **Camera cases** — every id they use (`camera.pickerStripToggle`, `camera.poseStrip`, `camera.guideToggle`,
  `camera.tools.done`, `camera.zoom.*`, `camera.permission`, `camera.status`) exists only in the redesign patch
  (`/tmp/b-camera-parked.patch`), which is not committed yet. A flow that names an uncommitted id must not land in
  `maestro/flows/`.
- **TC-GAL-010** — its ids *are* committed (`gallery.filter.*`, `gallery.empty.filter`), but the case stays a draft
  until a flow has run green on the lane-2 simulator.

Promotion checklist (same as `../jobs-add-pose/README.md`): flip the doc row from `pending —` to
`automated: <file>`, keep `tags: [<TC-ID>, …]`, rewrite the `runFlow` paths from
`../../../../mobile/iosApp/maestro/subflows/…` to `../subflows/…`, run it green on lane 2, then commit flow + doc with
one explicit pathspec.

| Case | Draft | Blocked on |
|---|---|---|
| TC-CAM-006 | `flows/TC-CAM-006-permission-panel.yaml` | `camera.permission` + the panel's action id (request 2); only the *refused* branch is expressible on the Simulator |
| TC-CAM-012 | `flows/TC-CAM-012-collapse-and-reopen-strip.yaml` | `camera.pickerStripToggle`, `camera.poseStrip` |
| TC-CAM-013 | `flows/TC-CAM-013-guide-kept-while-collapsed.yaml` | the same ids; pose identity reuses the `camera.poseGuide` value idiom of TC-CAM-007 |
| TC-CAM-014 | `flows/TC-CAM-014-topbar-eye-and-title.yaml` | `camera.guideToggle` (the rest exists: `camera.close`, `camera.choosePose`, `camera.tools`) |
| TC-CAM-015 | `flows/TC-CAM-015-tools-panel-done.yaml` | `camera.tools.done` (+ `camera.tools.opacity` for the pose rows) |
| TC-CAM-016 | `flows/TC-CAM-016-zoom-pills.yaml` | `camera.zoom.<label>` exists in the patch but carries no readable selected value, so half the case stays manual (request 1) |
| TC-CAM-018 | `flows/TC-CAM-018-permission-hides-strip.yaml` | `camera.permission` + `camera.pickerStripToggle`; needs `permissions: camera: deny` (Maestro can force it) |
| TC-CAM-019 | `flows/TC-CAM-019-collapse-survives-relaunch.yaml` | `camera.pickerStripToggle`, `camera.poseStrip` |
| TC-GAL-010 | `flows/TC-GAL-010-filter-empty-state.yaml` | nothing — ids committed; promote as soon as a build is named |

Boards used: `/tmp/ds-261030/export-c/05-camera-collapsed.png`, `05-camera-collapsed-dark.png`,
`07-gallery-grid-ax3.png`, `07-gallery-grid-dark.png`, plus `FEEDBACK-261031.md` (F3, F4, F5, F10, F12).

Device-only cases (capture snackbar, permission recovery through iOS Settings, real photos) are not drafted here: they
are walked through in [docs/qa/camera-device-checklist.md](../../camera-device-checklist.md) and cannot be a Simulator
flow without the fixture seams listed in each doc's "Requests to Feature".

Run one against the lane-2 simulator once the QA lead names the build:

```
maestro --device <CF871F97 udid> test -e APP_ID=posing.camera.app \
  docs/qa/redesign-drafts/gallery-camera/flows/TC-GAL-010-filter-empty-state.yaml
```
