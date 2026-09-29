# Scenario D — Account A simulator session diagnosis

## DECISIONS

BLOCKED on establishing the in-app identity. Protected credentials authenticate as tester003; authenticated `/api/account/me` matches owner `b605c5e6-9b06-4f56-8b1e-0073d98c5068`, and the owner-scoped API lists job `998de1bb-a5a3-4d4d-8fbf-b98f2f429798` (`succeeded`) for pose `8f9e6d4f-8276-4e0a-95d3-4c3f24619800`. The app’s Jobs → Finish view is blank. The current UI does not show another account, so I did not sign out; I could not attach to the Simulator window to reach the app sign-in/account screen.

## EVIDENCE

- Dev admin/API health: HTTP 200/200; protected env mode 600.
- Exact route/actions: existing simulator on Jobs → Finish → All results; attempted to activate Simulator; CUA returned `cgWindowNotFound`; captured current screen with `simctl` and read hierarchy with `maestro hierarchy --compact`.
- API identity/candidate: PASS. In-app tester003 identity: UNVERIFIED. Candidate row in app: ABSENT.
- Maestro test: 0 invocations. No sign-in/out, job mutation, app reset, or backend mutation.
- Artifacts: `diagnosis.txt`, `current-ui.png`, `SHA256SUMS.txt`. Screenshot shows blank Jobs results and no credentials/email; text scan clean; hashes verified.

## RISKS

The missing UI row could reflect an app session mismatch or sync/display defect; available evidence cannot distinguish them without app UI access. No hide was performed.

## NEXT ACTION

Lead to provide an accessible Simulator UI session or authorize a supported interaction path for in-app identity verification.
