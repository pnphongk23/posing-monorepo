# Phase 6 Account A Dev E2E — 2026-09-27

**Status:** Blocked before submission.

## Decision

The single UI sign-in attempt succeeded: the Dev app opened the authenticated Add Pose form. One Maestro flow then ran on `AIPose-Parity-iPhone13` (iOS 26.1, UDID `4C1D6E55-2C31-4BD7-9881-F86F21CC53C8`). The flow does not clear app state and contains no credentials.

Maestro confirmed the Add Pose photo picker was available, opened it, then failed its pre-submit assertion that the named test image was visible. The flow stopped there. It never selected an image, filled the pose fields, or tapped Submit. This run accepted no extraction job.

## Evidence

- `flow.yaml` — sanitized no-reset flow; SHA-256 `1b9d993311de158853078ef0048679660dd7f18a4c214406fa1232a08b932267`.
- `raw-output.txt` — email and credential-assignment patterns redacted; SHA-256 `055ac2bb89e3e97bbfd2eee665a4b0a4fc25ea37af75699dfc8fecf207d4cd22`.
- Maestro exit code: `1`; failure: named test image was not visible in the picker.
- No processing, ready, owner-scoped job, pose detail, or media evidence exists for this run. The failure screenshot was not retained.

## Risks and next action

The picker result does not distinguish an unavailable fixture from a permission prompt or a different displayed label. No further app inspection or retry was made. A transient accessibility result exposed the account identifier in tool output; the password remained masked, and neither value is present in the saved flow or sanitized log.

**CLARIFICATION_NEEDED:** Confirm that the named test image is available in this simulator’s photo library (or provide its exact picker label) before authorizing any new run.
