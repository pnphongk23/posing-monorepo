# Phase 6 Account A corrected mobile dev E2E

**Status:** `BLOCKED_NEEDS_LEAD` — corrected sign-in attempt rejected
**Device:** `AIPose-Parity-iPhone13` — `4C1D6E55-2C31-4BD7-9881-F86F21CC53C8` (iOS 26.1)
**Target:** Deployed dev API using the installed Dev build's default configuration

## Correction and checks

The prior run reached the sign-in screen but its password entry did not bind through `SecureField`. This flow switches to Show mode before entering the runtime-injected password, then hides it before submission. If the auth error appears, the failure branch erases both email and password before taking its evidence screenshot. The credential values are not stored in this file or the flow.

`maestro check-syntax scripts/maestro/phase-06-extraction-account-a.yaml`: **OK**. The installed Dev simulator build from the prior Phase 6 attempt was reused unchanged.

## Run result

The single corrected Maestro run used the explicit simulator and runtime-only secret injection. It entered Show mode before password entry and hid the password before tapping Sign in. The app still showed `Sign-in failed` / `Incorrect email or password.`. The flow's failure branch erased both fields and captured the cleared state before the final `addPose.photoPicker` assertion failed.

No photo was selected and `addPose.submitButton` was never tapped: **no extraction job was accepted**. No processing/ready sequence, guide detail, or skeleton media was observed. Per packet, no second auth attempt or run followed.

## Runtime evidence and candidate identity

Evidence is under `reports/maestro-account-a/retry-2026-09-27/`; sanitized output is `raw-output.txt` (SHA-256 `3e4c40d5e5b89e903b2f5970307b3080793e9e55d9b2baf02df549d97c5b55a7`). The flow's explicit cleared-state screenshot is `screenshots/00-signin-rejected-cleared.png` (SHA-256 `598171b2ecc36ca19e1b772fc3474ae0f8903760a2365cf69905781497d4a358`). Maestro's final failure screenshot is `2026-09-27_080711/screenshot-❌-1790471294100-(phase-06-extraction-account-a.yaml).png` (SHA-256 `b94128589cbc391f9a13fbe127f0bd974089671e0dac079df7a71e4c0fd67dea`); its warning screenshot is `2026-09-27_080711/screenshot-⚠️-1790471247827-(phase-06-extraction-account-a.yaml).png` (SHA-256 `fccb87b5fedf8661affac5bb9390830737db11584d5084b0a15e5f8064286bc1`). All three were visually checked and show no credential values. The command trace contained the runtime inputs and was scrubbed; all text artifacts were scanned after scrubbing.

Manifest inputs (paths under repo root, path plus SHA-256, sorted by path; this report is excluded to avoid self-reference):

- `scripts/maestro/phase-06-extraction-account-a.yaml` — `c34663502be18daf0edbadcbe2326834266edd927ffff901fe3c130b38e87f01`
- `plans/260925-server-authoritative-jobs/reports/maestro-account-a/retry-2026-09-27/2026-09-27_080711/ai-(phase-06-extraction-account-a).json` — `2b066f1d77f3b00b06ec1dde2151ae22b86a82353253187cb480947f87a8e79a`
- `plans/260925-server-authoritative-jobs/reports/maestro-account-a/retry-2026-09-27/2026-09-27_080711/ai-report-phase-06-extraction-account-a.html` — `e8f0f21d225b7a98d72b506954df9e5402551f0ace7096095e6458d9bc39fa13`
- `plans/260925-server-authoritative-jobs/reports/maestro-account-a/retry-2026-09-27/2026-09-27_080711/commands-(phase-06-extraction-account-a.yaml).json` — `8b067ee3976e15f4635dfbd1fbaaca5a5df12e821d132c3a709fefe1c1c08059`
- `plans/260925-server-authoritative-jobs/reports/maestro-account-a/retry-2026-09-27/2026-09-27_080711/screenshot-⚠️-1790471247827-(phase-06-extraction-account-a.yaml).png` — `fccb87b5fedf8661affac5bb9390830737db11584d5084b0a15e5f8064286bc1`
- `plans/260925-server-authoritative-jobs/reports/maestro-account-a/retry-2026-09-27/2026-09-27_080711/screenshot-❌-1790471294100-(phase-06-extraction-account-a.yaml).png` — `b94128589cbc391f9a13fbe127f0bd974089671e0dac079df7a71e4c0fd67dea`
- `plans/260925-server-authoritative-jobs/reports/maestro-account-a/retry-2026-09-27/raw-output.txt` — `3e4c40d5e5b89e903b2f5970307b3080793e9e55d9b2baf02df549d97c5b55a7`
- `plans/260925-server-authoritative-jobs/reports/maestro-account-a/retry-2026-09-27/screenshots/00-signin-rejected-cleared.png` — `598171b2ecc36ca19e1b772fc3474ae0f8903760a2365cf69905781497d4a358`

Aggregate manifest SHA-256: `06fa742e14c3ffeec90b2e38575a276a8511abf8837d641a782913d84cc252f1`.

Lead evidence check: all 8 listed file hashes match current files. The aggregate above was recomputed using the same convention as the validated Phase 4–5 candidate: SHA-256 of path-sorted lines `<file-sha256><two spaces><repo-relative-path>\n`. The Worker handback aggregate (`21495a6f…`) did not reproduce from the listed inputs and is superseded by this verified value.

## Blocker

The corrected UI input path ran, but the dev service still returned the generic invalid-credentials response. A later read-only [Supabase auth audit](phase-06-auth-audit.md) found the Account A identity confirmed in the target project and a same-email record in another project; the credential used by the run is not verified for the target project. No further sign-in attempt was made.

## Next action

Lead to resolve the Account A auth result before authorizing any further E2E attempt. This worker made no additional sign-in or job submission after the rejection.
