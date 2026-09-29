# Scenario D — explicit Account A session and hide

## DECISIONS

One Maestro invocation ran and failed at the pre-hide candidate row assertion. The flow entered Account, conditionally signed out the prior test session because `Sign out` was visible, then entered Account A credentials from the protected file. The app showed `Signed in` and `Sign out`; the flow proceeded to Jobs → Finish. The exact candidate Ready row was absent, so Maestro stopped before swipe, remove, or confirmation.

## EVIDENCE

- Dev admin/API health: HTTP 200/200; protected env mode 600; simulator `4C1D6E55-2C31-4BD7-9881-F86F21CC53C8`; syntax check passed.
- Authenticated API preflight verified tester003 label, owner `b605c5e6-9b06-4f56-8b1e-0073d98c5068`, job `998de1bb-a5a3-4d4d-8fbf-b98f2f429798` (`succeeded`), pose `8f9e6d4f-8276-4e0a-95d3-4c3f24619800`, and UI label `server-authoritative-jobs-e2e-final-20260927-1425`.
- In-app identity: explicit Account A credential entry succeeded; signed-in state asserted before Jobs navigation. Account screen does not display email/owner UUID.
- Jobs → Finish candidate Ready row: FAIL (not visible). Maestro invocation count: 1. Hide: not performed. Post-hide guide GET: not run.
- Sanitized artifacts: `scenario-d.yaml`, `preflight.txt`, `maestro-output.txt`, `maestro-artifacts/2026-09-27_160523/screenshot-❌-1790499971102-(scenario-d.yaml).png`, `SHA256SUMS.txt`.
- Screenshot visually checked. Debug command/AI artifacts and private raw log were removed to avoid retaining expanded inputs. Credential/email text scan clean; manifest hashes verified.
- No job creation, app reinstall, state clear, hide, or backend data mutation.

## RISKS

The API lists the candidate for the verified owner while the explicitly signed-in app shows an empty Finish list. This establishes an API/UI discrepancy but does not identify its root cause. Numeric Maestro process exit code was not retained; the log records the exact failed assertion. No retry was made.

## NEXT ACTION

Lead to investigate the app Jobs/Finish refresh or list mapping before authorizing another hide attempt. The one-shot limit for this run is consumed.
