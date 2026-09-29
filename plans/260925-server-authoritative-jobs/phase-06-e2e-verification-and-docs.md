---
phase: 6
title: "End-to-end verification + docs sync"
status: pending
priority: P2
effort: "3h"
dependencies: [2, 3, 5]
---

# Phase 6: End-to-end verification + docs sync

## Overview
Prove that the whole flow works across server and app, and reconcile the docs with what was actually built.

## Requirements
- All end-to-end runs target the shared development environment directly; do not substitute a local API for dev E2E.
- Web verification for `pose-extract-server` and `admin-ui` runs in Docker using the repository development stack (`docker-compose.dev.yml`).
- After all Docker web checks pass, deploy to dev in this exact order: `admin-ui` → `pose-extract-server`; verify health before proceeding to the next deploy.
- Run the complete iOS unit and integration test suite, then exercise the mobile UI and API flow against dev on a simulator with Maestro. Use an E2E runner configured as `codex/gpt-6-luna` (configured `lead` profile: `full-access`, `high`).
- Docs describe the implementation exactly: D5 dual auth, D7 `thumbnailUrl`, and the `POSE_MATERIALIZE_FAILED` code.

## Implementation Steps
1. Start the web development stack with `npm run docker:dev`. Run the full `pose-extract-server` test and lint suites inside its container (`npm test`, `npm run lint`). Run the admin proxy tests with `node --test src/lib/poseExtractExtractPoseProxy.test.mjs` and run admin-ui lint/build inside its container. Record commands and results.
2. If every Docker web check passes, deploy `admin-ui` to dev first. Verify its health, then deploy `pose-extract-server` to dev and verify API health. Record environment, deployed revisions, order, and health results. Stop on a failed deploy or health check and report the blocker immediately to Code Vương through the General Lead.
3. Run the complete iOS unit and integration suite on the Dev scheme with `xcodebuild test` on an available iOS simulator. Record the selected simulator and full test result.
4. Build and install the app configured with the dev API URL. Use Maestro with an explicit simulator UDID to run device E2E directly against dev; do not route E2E through the local Docker API. Capture the run header, flow result, screenshots, and failure artifacts.
5. Scenario A: sign in as A → Add Pose → the Jobs badge shows 1 → `Processing` → `Ready` → `View pose` opens the detail with the skeleton.
6. Scenario B: produce one isolated failed job using a dev-safe test mechanism (do not replace shared dev provider credentials) → the job ends `Failed` → `Retry` → it is queued again. If no safe mechanism exists, report this scenario as `Pending-validation` and immediately escalate the blocker to Code Vương.
7. Scenario C: delete and reinstall the app, then sign in as A → the same jobs are listed. Sign in as B → the list is empty.
8. Scenario D: hide a Ready row → it disappears, and the pose is still reachable through `GET /api/guides/:id`.
9. DB check against dev: `SELECT source_image_base64 IS NULL, result_image_base64 IS NULL FROM extraction_jobs WHERE pose_id IS NOT NULL` → both true.
10. Docs: update `docs/harness/specs/technical-architecture.md` (worker materialization, dual auth) and
    `docs/harness/specs/data-contract.md` (new columns and retention) wherever they differ from the build. Re-run the openapi parse.
11. Mark `plans/260924-1738-feat-004-005-design-closure/shared-contract.md` next-plan prerequisites 1–3 as superseded by this plan (one line).

## Success Criteria
- [ ] All Web checks pass in Docker; dev deploys pass in the required order and health checks are recorded.
- [ ] The full iOS unit/integration suite passes; Maestro scenarios A–D pass against dev, with screenshots and SQL output saved under `plans/260925-server-authoritative-jobs/reports/`.
- [ ] Every mission-level acceptance item in `plan.md` has linked evidence.
- [ ] Any blocker is escalated immediately to Code Vương; unresolved checks remain `Pending-validation` and are not claimed as passed.

## Risk Assessment
- The provider is unavailable in dev → Scenario A needs a real provider run. If it is unavailable, report Scenario A as `Pending-validation`
  and do not claim it passed.
- The worker lacks the `R2_*` env locally → Scenario A fails at materialization with `POSE_MATERIALIZE_FAILED`. Set them before starting (Phase 2 wiring).
