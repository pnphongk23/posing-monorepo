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
- An end-to-end run on the simulator against a local server with Postgres (`docker-compose.dev.yml`).
- Docs describe the implementation exactly: D5 dual auth, D7 `thumbnailUrl`, and the `POSE_MATERIALIZE_FAILED` code.

## Implementation Steps
1. Start Postgres from `docker-compose.dev.yml`, run `npm run dev` + `npm run worker` in `pose-extract-server`, and point the app at it through `AppConfig`.
2. Scenario A: sign in as A → Add Pose → the Jobs badge shows 1 → `Processing` → `Ready` → `View pose` opens the detail with the skeleton.
3. Scenario B: force a failure (invalid provider credentials in dev) → the job ends `Failed` → `Retry` → it is queued again.
4. Scenario C: delete and reinstall the app, then sign in as A → the same jobs are listed. Sign in as B → the list is empty.
5. Scenario D: hide a Ready row → it disappears, and the pose is still reachable through `GET /api/guides/:id`.
6. DB check: `SELECT source_image_base64 IS NULL, result_image_base64 IS NULL FROM extraction_jobs WHERE pose_id IS NOT NULL` → both true.
7. Docs: update `docs/harness/specs/technical-architecture.md` (worker materialization, dual auth) and
   `docs/harness/specs/data-contract.md` (new columns and retention) wherever they differ from the build. Re-run the openapi parse.
8. Mark `plans/260924-1738-feat-004-005-design-closure/shared-contract.md` next-plan prerequisites 1–3 as superseded by this plan (one line).

## Success Criteria
- [ ] Scenarios A–D pass, with screenshots and SQL output saved under `plans/260925-server-authoritative-jobs/reports/`.
- [ ] Every mission-level acceptance item in `plan.md` has linked evidence.

## Risk Assessment
- The provider is unavailable in dev → Scenario A needs a real provider run. If it is unavailable, report Scenario A as `Pending-validation`
  and do not claim it passed.
- The worker lacks the `R2_*` env locally → Scenario A fails at materialization with `POSE_MATERIALIZE_FAILED`. Set them before starting (Phase 2 wiring).
