# Phase 6 — Dev E2E and docs evidence

**Status:** `Pending-validation` — Scenario A's extraction flow, Scenarios C–D, and DB retention passed; Scenario B remains pending per the approved fallback. The Scenario A Jobs badge count assertion remains unverified.

## Environment gate

The Backend Lead's deployment report records Docker checks passing (pose-extract-server 245/245,
lint clean; admin-ui proxy test and lint/build clean), followed by the required Railway deploy order:
admin-ui revision `99e0530a-d8a5-42ac-822c-9560d79856ac`, then pose-extract-server revision
`2bbe92fb-ddcc-4ecf-b64f-5bed73dd5f00`. The sole Railway `production` environment is the dev target
confirmed for this mission. Current independent health probes returned:

- `GET https://admin-ui-production-a20c.up.railway.app/admin` — HTTP 200.
- `GET https://pose-extract-server-production.up.railway.app/api/health` — HTTP 200,
  `status=ok`, `version=1.0.0`.

Source: [phase-01-03-dev-deploy.md](phase-01-03-dev-deploy.md).

### 2026-09-27 read-only recheck

- `GET /admin` — HTTP 200.
- `GET /api/health` — HTTP 200, `status=ok`, `version=1.0.0`.
- Unauthenticated `GET /api/me/extract-jobs` — HTTP 401, `UNAUTHORIZED`.
- No account data or provider settings were changed by these probes.

## iOS prerequisite

The validated Dev simulator suite and candidate are recorded in
[ios-phases-04-05-acceptance.md](ios-phases-04-05-acceptance.md). The current suite, including the
Jobs hide-control/list-rendering changes and regression tests, passed **317/317 with 0 failures** on
`AIPose-Parity-iPhone13`; see [phase-06-hide-action-fix.md](phase-06-hide-action-fix.md) and
`ios-hide-control-test-evidence/raw-test-output.txt`.

## Scenario A — authenticated extraction

One authenticated Dev Maestro run completed on 2026-09-27. It submitted one pose and captured
Processing, Ready, the owner-scoped Finish row, and pose detail with rendered skeleton/media. The
flow asserted the exact unique pose name, Ready status, and View pose action. It did not assert the
plan's Jobs badge count of 1, no job ID was visible, and the run did not record the authenticated
account identity. Later read-only DB/API correlation confirms the candidate is owned by tester003.
Evidence and verified hashes: [final run report](maestro-account-a/authenticated-dev-final-2026-09-27_1425/report.md)
and [artifact manifest](maestro-account-a/authenticated-dev-final-2026-09-27_1425/SHA256SUMS.txt).
The run used deployed Dev endpoints, made one Maestro invocation, removed its temporary protected
environment file, and did not target local Docker.

## Remaining validation and blockers

Scenario B remains `Pending-validation`: no isolated dev-safe mechanism to produce and retry a
terminal failed job was evidenced. Per the plan fallback, shared provider credentials will not be
changed; this blocker was escalated to Code Vương, who approved leaving the scenario pending.
The account mismatch is resolved: a read-only supervisor DB/auth correlation identifies the
Scenario A pose/job as owned by tester003 (owner UUID `b605c5e6-9b06-4f56-8b1e-0073d98c5068`);
tester001 has no jobs, and tester002 is the approved empty Account B. The candidate job is
`998de1bb-a5a3-4d4d-8fbf-b98f2f429798`, pose `8f9e6d4f-8276-4e0a-95d3-4c3f24619800`.
Supervisor reports authenticated jobs/guide GETs return the candidate and HTTP 200 for tester003,
and an empty jobs list for tester002. A non-secret local preflight confirmed the protected env
bindings. Scenario C passed: Account A's exact Ready row persisted after reinstall, and Account B's
Processing and Finish views were empty. See the [C/D report](maestro-account-a/scenarios-c-d-final-2026-09-27/report.md)
and [artifact manifest](maestro-account-a/scenarios-c-d-final-2026-09-27/SHA256SUMS.txt).

The Jobs hide control has since been migrated to a SwiftUI `List` with native swipe actions and a
row Remove accessibility action/identifier. The full Dev suite passed **317/317**; evidence is in
[phase-06-hide-action-fix.md](phase-06-hide-action-fix.md). The D attempts before the latest list
rendering fix stopped before hide. The first ran one Maestro invocation but the candidate Ready row was absent in
Jobs/Finish, and Account A identity was not independently verified. In a second read-only
preflight, authenticated API checks matched tester003 and the candidate owner/job/pose, but the
simulator Jobs/Finish still showed no candidate row; Maestro invocations were zero. No hide or
guide GET occurred in either attempt. See the [first D report]
(maestro-account-a/scenario-d-hide-final-2026-09-27/report.md) and the [identity-preflight report]
(maestro-account-a/scenario-d-hide-account-a-verified-2026-09-27/report.md), with its verified
manifest. The root cause was confirmed in `JobsScreen`: its `List` containing `ForEach(rows)` was
nested under the `rows.isEmpty` branch. This is fixed and covered by a stub-injected rendering test.
The current full Dev suite passes 317/317. After correcting the Debug account launch token, the
final Scenario D run passed in one Maestro invocation. Account A tester003 saw the exact existing
Ready row, hid it using its job-specific Remove control, and the row disappeared while other rows
remained. An authenticated guide GET returned HTTP 200 with matching pose and owner. See the
[Scenario D report](maestro-account-a/scenario-d-debug-account-token-2026-09-27/report.md) and
[verified artifact manifest](maestro-account-a/scenario-d-debug-account-token-2026-09-27/SHA256SUMS.txt)
(SHA-256 `ba7092c25722946d18b221f5f7f509060871219d010fb0552e2d415efd4fc89d`). The before/after
screenshots visibly show the target Ready row removed and the other Ready/Failed rows preserved.
No commit, push, deploy, job creation, or local Docker E2E occurred. The iOS review-cycle cap
remains respected; no third Reviewer lane was created.

The Dev retention query artifact [db-retention-query-output.txt](db-retention-query-output.txt)
records `all_source_cleared=true` and `all_result_cleared=true` across 3 materialized pose jobs.
Its SHA-256 is `bdb7e64760327bff0dd2b7d3e3af2763ee1cf9dbdf78358be658056cc146694a`. Overall Phase 6
remains `Pending-validation`: Scenario B follows the approved fallback, and the Scenario A Jobs
badge count of 1 was not asserted in its run.

## Docs and contract parse

- Updated `docs/harness/specs/technical-architecture.md` with D5 auth boundaries, ownership
  derivation, and successful R2 media materialization/retention behavior.
- Updated `docs/harness/specs/data-contract.md` with the extraction job image payload/MIME columns,
  nullable state, retention rule, and public thumbnail locator.
- Marked predecessor plan prerequisites 1–3 superseded in
  `plans/260924-1738-feat-004-005-design-closure/shared-contract.md`.
- Parsed `docs/harness/specs/api/openapi.yaml` with `js-yaml`: OpenAPI 3.1.0, 23 paths; parse passed.
- Cursor pagination beyond 50 jobs remains deferred, as agreed in review.

## Boundary

No commit or push was made. Dev E2E did not target local Docker. This report does not claim overall
mission completion; Phase 6 remains pending on the approved Scenario B fallback and the Scenario A
Jobs badge count assertion.
