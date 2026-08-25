---
schema_version: 1
title: Runtime Pose Domain Migration delivery
relationships:
  specs: []
  decisions: []
  plans: []
  reports: []
  rules: []
  features: []
type: report
id: REP-009
status: completed
delivered: 2026-08-23
---

# REP-009 — Runtime Pose Domain Migration

- **Plan:** `260823-0215-runtime-pose-domain-migration`
- **Status:** verification rerun complete; reviewer handoff pending because change-detection validation is blocked by the local runner.
- **Scope:** Mobile Kotlin/Compose, SQLDelight, Pose-Extract backend, Admin Web, OpenAPI, harness.

## Canonical contract

One Pose entity uses stable UUID `poseId`, required `ownerAccountId`, status `local`/`published`, and required `original`, `skeleton`, and `thumbnail` media roles. Extraction starts with 202 and creates the Pose with 201 only after success. CommunityPose is a published read projection.

## Current evidence

- Evidence batch timestamp: `2026-08-23T04:04:47Z` (UTC).
- Backend: `npm test` — exit 0; 21 test files passed, 109 tests passed. `npm run lint` — exit 0 (`tsc --noEmit -p tsconfig.json`).
- Mobile: `./gradlew :composeApp:allTests :shared:iosSimulatorArm64Test :composeApp:linkDebugFrameworkIosArm64 --no-daemon` — exit 0; `BUILD SUCCESSFUL`, 33 actionable tasks. This single command is the rerun of all three required gates after poll-test correction.
- Admin Web: `npm run lint` — exit 0, 0 errors and 5 existing `@next/next/no-img-element` warnings. `npm run build` — exit 0; Next.js 16.2.3 compiled successfully and generated 13 static pages/routes.
- Harness: `ckh validate --all` — exit 0, `Harness validation passed`. `git diff --check` — exit 0, no output.
- OpenAPI v0.5.0 and canonical docs confirm `202 Accepted` starts an `ExtractionJob`, polling uses `GET /api/extract-jobs/{jobId}`, and Pose materialization completes with `201 Created`. The new Admin polling proxy is limited to that Phase 1 contract; no Phase 2–6 feature was added.

## Admin symbol/file ledger

| File / symbol | Change | Upstream impact |
|---|---|---|
| `web/admin-ui/src/app/admin/community/page.js` — `submitForm`, `fetchPoses`, `savePose`, `deletePose` | Canonical `poseId`, `skeletonUrl`, `local`/`published`; two-step extraction polling then Pose creation with owner UUID | `submitForm`: LOW, 0 dependants; `fetchPoses`: LOW, 4 direct dependants in Community module |
| `web/admin-ui/src/app/api/admin/community/poses/route.js` — `POST` handler | Accepts canonical JSON intake after successful extraction while retaining multipart compatibility | Route handler is an HTTP entrypoint; no indexed upstream symbol resolved |
| `web/admin-ui/src/app/api/admin/extract-jobs/[jobId]/route.js` — `GET` handler | Thin status proxy for the documented extraction job polling contract | Route handler is an HTTP entrypoint; no indexed upstream symbol resolved |

## Scope conclusion

Canonical runtime migration is complete for the approved Team A scope. Deprecated mobile adapters remain isolated for fixture/transport compatibility and are not a Phase 2–6 feature. Physical iPhone, Android, Team B, and later product phases remain excluded.
