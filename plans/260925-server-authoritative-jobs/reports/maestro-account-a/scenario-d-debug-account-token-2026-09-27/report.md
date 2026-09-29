# Scenario D — Debug Account token, hide, and guide retention

## DECISIONS

PASS. One Maestro invocation (exit 0) launched the Dev app with `clearState:false`, `stopApp:true`, and argument key `-AIPoseAccountEnabled` / string value `true`. The Account UI opened; the existing session was signed out when the UI exposed Sign out, then the flow signed in with protected Account A credentials and asserted Signed in + Sign out before navigating to Jobs.

## EVIDENCE

- Dev health: admin/API HTTP 200/200. Account A env mode 600. Simulator: AIPose-Parity-iPhone13 `4C1D6E55-2C31-4BD7-9881-F86F21CC53C8`; installed app `posing.camera.app`, AIPoseEnvironment DEV, version 1.0 build 14.
- Authenticated API preflight matched tester003, owner `b605c5e6-9b06-4f56-8b1e-0073d98c5068`, job `998de1bb-a5a3-4d4d-8fbf-b98f2f429798`, pose `8f9e6d4f-8276-4e0a-95d3-4c3f24619800`, and expected pose name.
- Jobs/Finish Ready row: PASS before hide. The flow asserted `server-authoritative-jobs-e2e-final-20260927-1425, Ready, View pose`; after swipe it asserted the job-specific Remove ID `jobs.row.remove.998de1bb-a5a3-4d4d-8fbf-b98f2f429798`, confirmed Remove, and asserted the row absent. Other rows remained.
- Authenticated post-hide guide GET: HTTP 200; pose ID, owner UUID, and expected name all matched.
- Maestro syntax: PASS. Invocation count: 1; exit: 0. No job creation, app-data clear/reinstall, or backend mutation beyond hiding the candidate.
- Artifacts: `scenario-d.yaml`, `preflight.txt`, `api-preflight.txt`, `guide-get.txt`, `maestro-output.txt`, `preflight-screen.png`, `maestro-artifacts/screenshots/01-ready-before-hide.png`, `02-remove-target.png`, `03-hidden.png`, `SHA256SUMS.txt`.
- Screenshots visually checked; credential/email scans clean; manifest hashes verified. Debug JSON/HTML and private raw output were removed after sanitization.

## RISKS

The Ready row label truncates visually and a second similar row remains; job-specific Remove accessibility ID and API job/pose correlation identify the hidden target. No unrelated row was hidden.

## NEXT ACTION

Lead to record Scenario D as passed with the attached evidence.
