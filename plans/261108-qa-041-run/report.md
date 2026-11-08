# qa-041-run — the build-23 camera suite on main 9886cb34 (build 25)

Goal: run TC-CAM-041 ×2, TC-CAM-032 and the build-23 camera suite against `main` @ `9886cb34`, opening the
guide sheet **only** through the visible eye (`camera.guideToggle`). Branch `qa/b23-prep`. Owner `9a1c304`,
2026-11-08.

Environment: Dev build of `main` `9886cb34` (`xcodebuild -scheme Dev -destination id=7CC9393C… -derivedDataPath
/tmp/dd-shared build` → BUILD SUCCEEDED, `simctl install` → `CFBundleVersion = 25`), simulator
`7CC9393C-88FC-4AE6-88D3-AC68A2E266B7` (iOS 26.1), `maestro` 2.2.0, one Maestro run at a time.

## Results

| Case | Result | Detail |
|---|---|---|
| TC-CAM-041 | **FAIL → PASS ×2** | Run 1 failed at `assertNotVisible camera.poseGuide` right after tapping `camera.guideAdjust.showGuide`. Root cause: the flow, not the app (see below). After the selector fix: two consecutive runs exit 0 (68 steps `COMPLETED` each), including the black colour, mirror, Done, reopen and relaunch-persistence steps. |
| TC-CAM-032 | **PASS** | exit 0. Flip value flips Normal ⇄ Mirrored, `camera.tools.mirror*` stay retired, guide survives. |
| TC-CAM-014 | **FAIL → PASS** | Failed at the same show-guide step (same selector defect). After the fix: exit 0. |
| TC-CAM-037 | **FAIL → PASS** | Failed at `.*None selected.*` on `camera.choosePose`; stale after design sync. After the fix it then exposed a second defect (`${output.pickedName}` = `"undefined"`). Both fixed; exit 0. |
| suite "dev23" (22 `TC-CAM-*` flows) | **20/22 pass first pass → 22/22 after the fixes** | See the table below. |

Suite detail (first pass, build 25, in flow-name order):

```
PASS TC-CAM-001  PASS TC-CAM-004  PASS TC-CAM-006  PASS TC-CAM-007  PASS TC-CAM-009
PASS TC-CAM-011  FAIL TC-CAM-014  PASS TC-CAM-015  PASS TC-CAM-016  PASS TC-CAM-018
PASS TC-CAM-021  PASS TC-CAM-022  PASS TC-CAM-024  PASS TC-CAM-027  PASS TC-CAM-032
PASS TC-CAM-033  PASS TC-CAM-036  FAIL TC-CAM-037  PASS TC-CAM-038  PASS TC-CAM-039
PASS TC-CAM-040  PASS TC-CAM-041
```

`PASS` = the flow finished with every step `COMPLETED` and run.sh wrote its screenshot; `FAIL` = a named
assertion failed (quoted above). The only `SKIPPED` lines are `runFlow when … camera.shutter is not visible`
guards, whose condition is false on the normal path — not skipped coverage.

## Why run 1 of TC-CAM-041 failed — the toggle's hit target

`camera.guideAdjust.showGuide` is a SwiftUI `Toggle`, so its accessibility element spans the **whole row**
(`bounds [16,600][377,628]` from `maestro hierarchy`); only the switch at the trailing end is touch-reactive.
Maestro taps an element's geometric centre, which lands in the empty gap between the "Show guide" label and the
switch, so the binding never fired and the guide stayed drawn. The product behaviour is correct, and a probe flow
that tapped `point: "92%,50%"` (the switch) hid `camera.poseGuide` immediately — that probe is why the fix is a
selector change rather than a bug report. `TC-CAM-014` taps the same toggle and carried the same defect.

Both flows now tap the switch. The coordinate is relative to the element, so it survives width changes; it is
still a coordinate, and `camera-guide.md` request 14 records the two ways to remove it (row hit area, or a switch
id).

## Why TC-CAM-037 failed — a stale value, then a stale clipboard

1. It asserted the Poses chip's value was `"None selected"`. On `9886cb34`
   (`CameraFeature.swift:1874-1876`) the no-pose value is `"Choose a pose"` (the label already said that), so the
   string `"None selected"` only survives for a pose with an empty name. Design sync moved it.
2. With that fixed, the flow failed later: `copyTextFrom` on the row's VoiceOver label (`.*Use .* pose.*`) leaves
   `maestro.copiedText` undefined, because the row's `text` attribute is empty and the pose name lives only in the
   accessibility label — so `${output.pickedName}` resolved to the literal string `"undefined"`. The name is no
   longer pinned (no fixture supplies a known pose id); the chip is asserted by the state the case documents.

## Evidence

- Flow screenshots: `reports/*.png` (TC-CAM-041, TC-CAM-032, TC-CAM-014, TC-CAM-037).
- Suite run log: kept at `/tmp/qa-suite-cam.log` during the run (not committed — regenerable).
- `maestro/check-traceability.sh` green (69 flows); all 69 flow files parse as YAML.

## Notes for the next lane

- The guide sheet's top-chrome entry (`camera.guideToggle` → "Adjust guide") works on build 25, including the
  relaunch-persistence path; `camera.guideAdjust.open` and `camera.guideAdjust.reset` stay retired (guarded).
- Camera flows write `takeScreenshot` files into `mobile/iosApp/maestro/` because `run.sh` cd's there. Seventeen
  stray PNGs from this run were removed; clean up after any suite run.
- Still device-only (unchanged): the legacy-colour upgrade to white, exact zoom factors, permission-panel copy
  variants — see `docs/qa/camera-device-checklist.md`.
