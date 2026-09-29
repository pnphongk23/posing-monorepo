# Phase 6 Scenarios C/D — final bounded Dev evidence

Date: 2026-09-27. Target device: `AIPose-Parity-iPhone13`, UDID `4C1D6E55-2C31-4BD7-9881-F86F21CC53C8`. Dev admin/API health were HTTP 200 before each invocation; protected Account A/B files were mode 600; syntax checks passed. Maestro received explicit `-e` mappings from the protected files with shell tracing disabled.

## Candidate identity

The candidate is `server-authoritative-jobs-e2e-final-20260927-1425`. Supervisor-confirmed read-only correlation identifies Account A as tester003, owner UUID `b605c5e6-9b06-4f56-8b1e-0073d98c5068`, job UUID `998de1bb-a5a3-4d4d-8fbf-b98f2f429798`, and pose UUID `8f9e6d4f-8276-4e0a-95d3-4c3f24619800`. These IDs provide read-only matching context; the UI flow asserted the unique candidate name and Ready state. No UUID was visible in the UI or used for mutation.

## Scenario C — reinstall persistence and account isolation

**PASS.** One Maestro invocation; exit 0. After the plan-required simulator app uninstall/reinstall and launch with `-AIPoseAccountEnabled true`, the flow signed in as Account A, selected Jobs/Finish, and the exact candidate name with Ready/View pose was visible. It signed out, authenticated as approved Account B tester002, and asserted the Processing and Finish Jobs views were empty and the candidate row absent. The two corresponding screenshots are included.

- Account A candidate remains listed after reinstall: **PASS**.
- Account B tester002 owner-scoped Jobs list is empty: **PASS**.

No retry.

## Scenario D — hide retention

**BLOCKED.** One Maestro invocation; exit 1. The flow signed in as Account A and asserted the exact candidate Ready row visible; the pre-hide screenshot is included. It swiped left and attempted the flow’s `Remove` control, but that selector was not found. The failure screenshot shows the row still present. No hide/remove mutation occurred.

- Account A candidate Ready row visible before hide: **PASS**.
- Hide row and verify disappearance: **BLOCKED**; the `Remove` selector was not found after swipe and the row remained visible.
- Authenticated guide GET after hide: **PENDING**; it was not issued because hide did not occur.

No retry.

## Actions and sanitation

C performed only the requested app reinstall and sign-in/navigation. D performed sign-out/sign-in, Jobs navigation, and a non-mutating swipe before the failed selector. No pose/job mutation, deployment, or local Docker use occurred. Screenshots were visually inspected; all show Jobs content and no email/token values. Text evidence was scanned against protected values and email/token patterns; scan results are recorded in handback. The hash manifest covers all files here except itself.

Credential scan: exact protected-value matches 0; email patterns 0; token patterns 0. Four screenshots visually inspected.
