# Phase 6 Scenarios C/D retry — Dev evidence

Date: 2026-09-27. Target: Dev; simulator `AIPose-Parity-iPhone13` (`4C1D6E55-2C31-4BD7-9881-F86F21CC53C8`). Candidate referenced by the packet: `server-authoritative-jobs-e2e-final-20260927-1425`. No job/pose ID was observed in these runs.

## Scenario C — account isolation after reinstall

Status: BLOCKED. Maestro invocation count: 1; exit code: 1. Dev admin/API health were HTTP 200, env files mode 600, syntax passed. The planned app uninstall/reinstall and launch with `-AIPoseAccountEnabled true` completed. The flow failed at the `Sign out` assertion on the email sign-in screen; the screenshot displayed `undefined` in the email field and an invalid-email message. The invocation used ordinary shell variable names not exposed to Maestro; no valid Account A login or Jobs assertion occurred. Account A persistence and Account B empty-list criteria are unverified. Do not retry.

Evidence: `scenario-c-preflight.txt`, `scenario-c-raw-output.txt`, `scenario-c-exit-code.txt`, `scenario-c-failure-undefined-env.png`, `scenario-c.yaml`.

## Scenario D — hide retention

Status: BLOCKED. Maestro invocation count: 1; exit code: 1. Dev admin/API health were HTTP 200, env files mode 600, syntax passed, and the debug account-UI launch argument succeeded. The protected pre-hide API lookup received auth/jobs HTTP 200 but failed to resolve the candidate; details were withheld. Maestro reached a generic empty Jobs screen and failed the exact Ready-row visibility assertion. No hide/remove action was performed. The row-disappears criterion and authenticated guide GET after hide are unverified. Do not retry.

Evidence: `scenario-d-preflight.txt`, `scenario-d-api-discovery.txt`, `scenario-d-raw-output.txt`, `scenario-d-exit-code.txt`, `scenario-d-empty-jobs.png`, `scenario-d.yaml`.

## Actions and sanitation

No backend mutation, hide, delete, or deployment occurred. Scenario C performed only the plan-required simulator app reinstall; Scenario D performed read-only account/job API discovery and displayed the empty Jobs screen. Both protected env files were removed after both single invocations completed; their values are absent from this report and evidence. Screenshots were visually inspected for displayed email/token data. Text evidence was scanned against the protected credential values, email patterns, and token-like patterns; no matches were found. Hash manifest covers every file in this folder except itself.
