# Phase 6 Scenarios C/D — explicit Maestro env — Dev

Date: 2026-09-27. Device: `AIPose-Parity-iPhone13`, UDID `4C1D6E55-2C31-4BD7-9881-F86F21CC53C8`. Candidate pose name from the accepted Scenario A evidence: `server-authoritative-jobs-e2e-final-20260927-1425`. No job or pose ID was observed.

## Scenario C — account isolation after reinstall

**BLOCKED.** Invocation count 1; exit 1. Preflight passed: Dev admin/API HTTP 200, both protected files mode 600, Maestro syntax OK, explicit simulator booted. The planned uninstall/reinstall and Debug launch with `-AIPoseAccountEnabled true` completed. The flow signed in Account A (`Sign out` assertion passed), opened Jobs/Finish, then failed because the candidate Ready row was not visible. The screenshot shows “No jobs yet.” Account A persistence criterion: **FAIL** (pose absent after reinstall). Account B tester002 empty-list criterion: **PENDING** (not reached; flow stopped on the failed assertion). No retry.

## Scenario D — hide retention

**BLOCKED.** Invocation count 1; exit 1. Preflight passed: Dev admin/API HTTP 200, protected files mode 600, syntax OK, simulator booted, debug launch succeeded. Account A sign-in completed (`Sign out` assertion passed). The flow opened Jobs/Finish and failed because the candidate Ready row was not visible; screenshot shows “No jobs yet.” Ready row disappearance: **PENDING** (row was absent before hide). Authenticated `GET /api/guides/:id` after hide: **PENDING** (no hide occurred, so no GET was issued). No retry.

## Actions, invocation inputs, and sanitation

C performed only the plan-required simulator app uninstall/reinstall plus sign-in/navigation. D performed sign-out/sign-in and read-only Jobs navigation. Neither run hid a job, mutated pose/job data, deployed, or used local Docker. The Maestro CLI received explicit `-e` mappings for `A_TEST_EMAIL`, `A_TEST_PASSWORD`, `B_TEST_EMAIL`, `B_TEST_PASSWORD` (C) and `MAESTRO_A_TEST_EMAIL`, `MAESTRO_A_TEST_PASSWORD` (D); values were sourced from mode-600 protected files with shell tracing disabled and are not recorded here. Failure screenshots were visually inspected and contain only the generic Jobs empty state. Text artifacts were scanned against protected credential values and email/token patterns; scan result recorded in handback. Hash manifest covers every file here except itself.
