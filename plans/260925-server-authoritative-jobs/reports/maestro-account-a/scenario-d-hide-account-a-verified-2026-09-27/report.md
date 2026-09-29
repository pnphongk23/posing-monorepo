# Scenario D — Account A hide and guide retention

## DECISIONS

BLOCKED before Maestro. Authenticated Dev API preflight verified tester003, owner `b605c5e6-9b06-4f56-8b1e-0073d98c5068`, candidate job `998de1bb-a5a3-4d4d-8fbf-b98f2f429798` (`succeeded`), and pose `8f9e6d4f-8276-4e0a-95d3-4c3f24619800`. The required Ready row was not visible in simulator Jobs → Finish, so the stop condition applies.

## EVIDENCE

- Dev admin/API health: HTTP 200 / HTTP 200.
- Simulator UDID: `4C1D6E55-2C31-4BD7-9881-F86F21CC53C8`.
- Candidate correlation: API PASS; simulator Ready row BLOCKED (not visible in captured screen).
- Maestro invocations: 0. Hide: not performed. Post-hide guide GET: not performed because no hide occurred.
- Screenshot: `preflight-screen.png`; sanitized (shows no account credentials or email).
- Preflight record: `preflight.txt`.
- SHA256 manifest: `SHA256SUMS.txt`.
- No app state reset, sign-out, hide mutation, or other backend mutation was performed.

## RISKS

The simulator list does not establish whether its current session is tester003; no identity switch was attempted. UI row absence may reflect app session or list refresh state. No claim is made that the guide-retention criterion passed.

## NEXT ACTION

Lead to decide whether to authorize a fresh UI identity/session preflight or another bounded attempt. This run did not consume a Maestro invocation.
