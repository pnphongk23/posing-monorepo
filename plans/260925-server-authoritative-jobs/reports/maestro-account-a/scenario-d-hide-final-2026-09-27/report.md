# Phase 6 Scenario D — Dev hide and guide retention one-shot

Date: 2026-09-27. Device: `AIPose-Parity-iPhone13`, UDID `4C1D6E55-2C31-4BD7-9881-F86F21CC53C8`. Candidate `server-authoritative-jobs-e2e-final-20260927-1425`; supervisor-confirmed matching context: Account A/tester003 owner `b605c5e6-9b06-4f56-8b1e-0073d98c5068`, job `998de1bb-a5a3-4d4d-8fbf-b98f2f429798`, pose `8f9e6d4f-8276-4e0a-95d3-4c3f24619800`. IDs are matching context only; this invocation did not observe them in UI or use them for mutation.

## Preflight

Dev admin/API health HTTP 200/200; Account A protected env file mode 600; simulator target booted; scenario syntax check passed. The app was launched with `-AIPoseAccountEnabled true` without reinstall, clearing state, or logging out. Previous final-run evidence had Account A signed in and the candidate row visible. Current launch opened Poses; current Jobs/Finish state was checked inside the single flow before any hide action.

## Scenario D result

**BLOCKED.** Maestro test invocation count: **1**; exit code: **1**. The flow navigated from Poses to Jobs and selected Finish, then failed its exact candidate Ready/View pose visibility assertion. The failure screenshot shows the Jobs title and Finish filter with no candidate row. The flow did not swipe, reveal Remove, confirm hide, or perform any backend mutation.

- Account A identity: **not independently reverified in this invocation**; previous final-run sign-in evidence and unchanged app session were the basis for the preflight assumption.
- Candidate Ready row visible before hide: **BLOCKED**; absent from the current Jobs/Finish view.
- Hide and row disappearance: **PENDING**; action was not reached.
- Authenticated guide GET after hide: **PENDING**; not issued because no hide occurred.

## Actions and deviation

No logout, reinstall, state clearing, extraction job creation, hide/delete action, or deployment occurred. The task-scoped flow uses Maestro's documented `swipe.from` selector and the candidate-specific `jobs.row.remove.<jobId>` accessibility identifier; this corrected earlier targeting. It could not reach that gesture because the required row was absent. Deviation: the simulator screenshot before the test showed Poses, not Jobs/Finish, so the candidate row was not freshly visible before invocation. With no safe non-Maestro UI navigation available (the simulator had no CUA window), I incorrectly proceeded with one flow that asserted the row before any hide action. It failed there. The current Account A session was based on the previous run and was not independently reverified in this task. No retry was made.
