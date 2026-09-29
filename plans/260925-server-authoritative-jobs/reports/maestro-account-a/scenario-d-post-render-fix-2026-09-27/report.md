# Scenario D — post-render-fix hide attempt

## DECISIONS

BLOCKED before Account A authentication and candidate-row verification. The single Maestro invocation exited 1 at `tapOn: Open Account`. It had navigated from Poses to Settings, where the captured Dev app screen does not expose `Open Account`. The flow stopped there; no hide action occurred and no retry was made.

## EVIDENCE

- Dev admin/API health: HTTP 200/200; protected Account A env mode 600.
- Installed simulator app: bundle `posing.camera.app`, `AIPoseEnvironment=DEV`, version 1.0, build 14; UDID `4C1D6E55-2C31-4BD7-9881-F86F21CC53C8`.
- Protected-credential API preflight: sign-in/account/jobs HTTP 200; tester003 label, owner `b605c5e6-9b06-4f56-8b1e-0073d98c5068`, candidate job `998de1bb-a5a3-4d4d-8fbf-b98f2f429798`, and pose `8f9e6d4f-8276-4e0a-95d3-4c3f24619800` matched; status `succeeded`.
- App route: Poses → Settings → `Open Account` tap failed. Candidate row pre-hide: NOT REACHED/UNVERIFIED; no claim that it was absent or visible.
- Maestro syntax check passed. Invocation count: 1; exit code: 1. Account A was not reauthenticated in this invocation. Hide: not performed. Guide GET: not run.
- Artifacts: `scenario-d.yaml`, `preflight.txt`, `maestro-output.txt`, `preflight-screen.png`, `maestro-artifacts/2026-09-27_161846/screenshot-❌-1790500750331-(scenario-d.yaml).png`, `SHA256SUMS.txt`.
- Screenshots visually checked; text credential/email scan clean; manifest verified. Debug JSON/HTML and private raw log were removed.
- No app reinstall/data clear, sign-out, job creation, hide, or backend mutation.

## RISKS

The app build is identified as Dev, but this run did not verify its in-app Account A session or Jobs row. The missing Account entry may require the debug launch argument `-AIPoseAccountEnabled true`; this was not passed in this invocation and is not proven to be the sole blocker. The row-rendering fix was not validated.

## NEXT ACTION

Lead to confirm the supported launch configuration that exposes Account in the installed Dev app. This one-shot invocation is consumed; a new run requires separate authorization.
