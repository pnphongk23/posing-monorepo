# Scenario D — Account feature enabled attempt

## DECISIONS

BLOCKED before in-app sign-in and candidate-row verification. The one Maestro invocation exited 1 at `tapOn: Open Account`; the Account UI was not exposed in Settings despite the requested `launchApp.arguments` map `{AIPoseAccountEnabled: true}`. No retry was made.

## EVIDENCE

- Dev admin/API health: HTTP 200/200; Account A env mode 600.
- Simulator app: `posing.camera.app`, `AIPoseEnvironment=DEV`, version 1.0 build 14; UDID `4C1D6E55-2C31-4BD7-9881-F86F21CC53C8`.
- Authenticated API preflight matched tester003, owner `b605c5e6-9b06-4f56-8b1e-0073d98c5068`, job `998de1bb-a5a3-4d4d-8fbf-b98f2f429798` (`succeeded`), and pose `8f9e6d4f-8276-4e0a-95d3-4c3f24619800`.
- Launch used `stopApp:true`, `clearState:false`, `arguments: { AIPoseAccountEnabled: true }`. Flow syntax passed. Maestro test count: 1; exit 1.
- UI route: Poses → Settings; `Open Account` tap failed. Account A app identity and Jobs/Finish row: NOT VERIFIED. Hide: not performed. Post-hide guide GET: not run.
- Source diagnostic: `AppConfig.swift` places the account override under `#if DEBUG` and checks for argv token `-AIPoseAccountEnabled` followed by `true`. The plist confirms `DEV` but not Debug vs Release; the requested argument map did not expose Account. Root cause (build configuration vs argument translation) is unresolved; no product edits or retry were made.
- Artifacts: `scenario-d.yaml`, `preflight.txt`, `api-preflight.txt`, `maestro-output.txt`, `preflight-screen.png`, `maestro-artifacts/2026-09-27_162310/screenshot-❌-1790501018036-(scenario-d.yaml).png`, `SHA256SUMS.txt`.
- Screenshots visually checked; credential scan clean; hashes verified. Debug command/AI artifacts and private raw log removed. No app data clear, sign-out, job creation, hide, or backend mutation.

## RISKS

Candidate API ownership is proven, but this run cannot validate row rendering or hide retention because the app Account UI did not open. The expected argument key/value shape needs reconciliation with the app gate before any new run.

## NEXT ACTION

Lead to reconcile the Maestro launch-argument map with the Dev app gate and authorize a new bounded attempt. This run's one-shot limit is consumed.
