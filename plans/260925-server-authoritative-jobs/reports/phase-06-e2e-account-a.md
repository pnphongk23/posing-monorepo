# Phase 6 Account A mobile dev E2E

**Status:** Failed before job acceptance — sign-in rejected
**Scope:** One Account A sign-in and one pose extraction job against the deployed dev service.
**Device:** `AIPose-Parity-iPhone13` — `4C1D6E55-2C31-4BD7-9881-F86F21CC53C8` (iOS 26.1)

## Run result

The Dev simulator build succeeded and `maestro check-syntax` returned `OK`. The single Maestro run failed at the wait for `addPose.photoPicker` after the sign-in submit. Its run header matched the device above. The app displayed `Sign-in failed` / `Incorrect email or password.`; the signed-in add-pose form never appeared.

No photo was selected and `addPose.submitButton` was never tapped, so **zero extraction jobs were accepted**. There is no processing-to-ready sequence, pose detail, or skeleton media result to report. The run was not retried.

## Evidence

Runtime artifacts are under `reports/maestro-account-a/2026-09-27_074600/`; sanitized Maestro output is `reports/maestro-account-a/raw-output.txt` (SHA-256 `db492494ec6213c80704a931369cd2530f0b8be15da65e54c4d5080f35e4c9da`). The masked failure screenshot is `screenshot-❌-1790470112448-(phase-06-extraction-account-a.yaml).png` (SHA-256 `8aff2a13a7d8e222803014da15618a9bbeb1c840931f964e7e776181d83dd259`). The optional `Skip` warning screenshot is `screenshot-⚠️-1790469979873-(phase-06-extraction-account-a.yaml).png` (SHA-256 `910f61f239849835898a75b2230b1e7500ba3489ae032b6ffc92991f0e61e04f`). The command trace was scrubbed after review; text artifacts were scanned for credential patterns. The initial optional `Skip` onboarding tap was warned because onboarding was absent; the simulator opened directly to Poses.

The failure screenshot showed an empty password control after rejection. The app sign-in model retains its password on a rejected request, so the exact cause is unresolved: secure-field entry may not have bound, or the dev service rejected the supplied credentials. The generic auth response does not distinguish these cases.

## Acceptance

- Not met: sign-in did not complete.
- Not met: no job was accepted; no status transition observed.
- Not met: pose detail and skeleton media were not reached.
- Met: explicit simulator run, build and syntax check; run header, result, screenshots, and failure artifacts reviewed and sanitized for credential leakage.
