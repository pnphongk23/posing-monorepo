# Phase 6 Scenarios C and D — 2026-09-27

## Decisions

`BLOCKED_NEEDS_LEAD`. Each scenario used its single permitted Maestro invocation and failed before login. Neither scenario was retried. Both protected credential files were removed after the runs ended.

## Candidate identity

Prior Scenario A pose: `server-authoritative-jobs-e2e-final-20260927-1425`, workspace `wks_2e69547344ec0a0b`. The prior accepted evidence did not show a job ID; none is claimed here.

## Criteria

- C — Account A sees Scenario A pose in Jobs after reinstall: **BLOCKED**; flow stopped at missing `Open Account` in Settings before login/list verification.
- C — Account B `tester002` sees empty owner-scoped Jobs list: **BLOCKED**; the Dev candidate exposes no Account screen to switch identities.
- D — Account A hides Ready row and it disappears: **BLOCKED**; flow stopped at missing `Back` before entering Jobs.
- D — authenticated `GET /api/guides/:id` returns the retained pose after hide: **BLOCKED**; hide was not reached, and the protected Account A jobs lookup did not yield the candidate pose ID. No guide GET was made.

## Evidence

For both invocations, Dev admin/API health was HTTP 200/200, Maestro syntax passed, protected env-file modes were 600, and the explicit `AIPose-Parity-iPhone13` UDID was booted. C count **1**, exit **1**; sanitized error: `Element not found: Open Account`. D count **1**, exit **1**; sanitized error: `Element not found: Back`. See per-scenario preflight, sanitized output, and exit-code files. The C failure screenshot shows the Settings screen without an Account entry. No acceptance screenshots were produced.

The Account A API discovery attempt returned a generic failure; response details were withheld. No local Docker route was used. Both protected env files and both temporary run directories were removed.

## Risks and next action

The current Dev simulator candidate does not expose the planned Account navigation path, and the D flow's initial Back selector was absent. Lead should resolve the supported account-switch path/build and provide a verified pose-ID discovery path before authorizing new one-shot attempts.
