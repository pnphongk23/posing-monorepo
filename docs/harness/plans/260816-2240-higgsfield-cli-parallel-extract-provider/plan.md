---
title: Higgsfield CLI parallel extract provider
description: Add Higgsfield CLI as a parallel extract provider behind PoseExtractorProvider factory, route canonical extract through async ExtractionJob worker polling, expose FEAT-009 admin provider toggle (invoked via Admin Web) with Docker/Railway credential operations.
status: in_progress
# Corrected from completed (manual recovery): WI-06 is blocked and no delivery report is linked,
# so 'completed' was inconsistent. See Plan 260823-0045 validation gate.
approval:
  status: approved
  required_by: Repository Maintainer
  decided: 2026-08-17
priority: P2
effort: L
branch: codex/higgsfield-cli-parallel-extract-provider
tags:
  - extract
  - higgsfield
  - worker
  - provider
  - admin
  - docker
  - railway
blockedBy: []
blocks: []
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[api-catalogue]]"
  decisions:
    - "[[DEC-001-extraction-provider-selection-policy|DEC-001]]"
  plans: []
  reports: []
  rules: []
  features:
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
    - "[[FEAT-007-operate-pose-content-from-admin-web|FEAT-007]]"
    - "[[FEAT-009-configure-extraction-provider|FEAT-009]]"
  source_paths:
    - docs/harness/plans/260816-2240-higgsfield-cli-parallel-extract-provider/design.md
    - docs/harness/specs/api-contract.md
    - web/services/pose-extract-server/src/worker/job-processor.ts
    - web/services/pose-extract-server/src/worker/worker-main.ts
    - web/services/pose-extract-server/src/worker/gemini-browser-client.ts
    - web/services/pose-extract-server/src/routes/extractPoseRoutes.ts
    - web/services/pose-extract-server/src/services/geminiService.ts
    - web/services/pose-extract-server/src/db/extractionJobStore.ts
    - web/services/pose-extract-server/src/db/schema.sql
    - web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts
    - web/services/pose-extract-server/src/routes/jobStatusRoutes.ts
    - web/services/pose-extract-server/src/routes/adminRoutes.ts
    - web/services/pose-extract-server/Dockerfile
    - web/admin-ui/src/app/admin/keys/page.js
    - web/admin-ui/src/lib/poseExtractAdminServer.js
    - web/services/pose-extract-server/plans/260510-1810-sub2api-provider-strategy-pattern/phase-01-research-interface-design.md
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt
created: 2026-08-16T22:40:00+07:00
createdBy: Harness CLI
---

# Higgsfield CLI parallel extract provider

## Overview

Introduce a second pose-extraction engine — **Higgsfield CLI** (`kling_omni_image`
default model, spawn-per-job) — alongside the existing **Gemini native REST** path, unified
behind a `PoseExtractorProvider` factory. Canonical extract for mobile and admin
moves to **async `ExtractionJob` enqueue + worker poll** (phase 1); the worker
uses the globally configured engine per **[FEAT-009](../../features/FEAT-009-configure-extraction-provider.md)**
(**approved** 2026-08-16 Product Authority) and **[DEC-001](../../decisions/DEC-001-extraction-provider-selection-policy.md)**
(**approved** 2026-08-17 Product Authority). **FEAT-009** owns the admin provider
toggle surface (no credential-upload UI); **FEAT-007** Admin Web invokes FEAT-009.
Docker/Railway installs the CLI globally, mounts
`credentials.json`, and runs **S1** scheduled auth probes with a human re-login
runbook. **S3** (48h spike) tests whether CLI credential refresh-writes survive
on a writable volume; it is non-blocking and evidence-gated.

Governing Features **FEAT-004**, **FEAT-005**, **FEAT-007**, and **FEAT-009** are
**approved** (2026-08-17 Product Authority for FEAT-004/005/007; 2026-08-16 for
FEAT-009). **DEC-001** extraction provider policy is **approved** (2026-08-17
Product Authority). FEAT-005 is linked because community guide intake already
enqueues `ExtractionJob` records consumed by the same worker.

Locked architecture is recorded in [design.md](./design.md) and must not be
reopened during Cook without a new Decision.

## Work Items

- [Work Item 1: Close FEAT-004, FEAT-009, and FEAT-007 authority for parallel provider and async extract jobs](./work-item-01-close-feat-004-and-feat-007-authority-for-parallel-provider-and-async-extract-jobs.md)
- [Work Item 2: Land PoseExtractorProvider factory for Gemini and Higgsfield CLI](./work-item-02-land-poseextractorprovider-factory-for-gemini-and-higgsfield-cli.md)
- [Work Item 3: Route extract through ExtractionJob worker with gpt_image_2 CLI spawn](./work-item-03-route-extract-through-extractionjob-worker-with-gpt-image-2-cli-spawn.md)
- [Work Item 4: Add FEAT-009 admin provider toggle (invoked via Admin Web)](./work-item-04-add-admin-provider-toggle-only.md)
- [Work Item 5: Docker Railway CLI install credentials volume and S1 auth probe runbook](./work-item-05-docker-railway-cli-install-credentials-volume-and-s1-auth-probe-runbook.md)
- [Work Item 6: Spike S3 CLI keep-alive refresh on writable volume 48h evidence](./work-item-06-spike-s3-cli-keep-alive-refresh-on-writable-volume-48h-evidence.md)
- [Work Item 7: Verify job extract provider switch error mapping and S1 probe](./work-item-07-verify-job-extract-provider-switch-error-mapping-and-s1-probe.md)

## Coverage

| Locked intent | Work Items |
| --- | --- |
| Close authority; async extract + dual-provider processing in FEAT-004; engine selection in FEAT-009/DEC-001; FEAT-007 invokes FEAT-009; provider-neutral errors in API spec | 1 |
| `PoseExtractorProvider` factory (`GeminiNativeProvider`, `HiggsfieldCliProvider`) | 2 |
| Canonical extract → `ExtractionJob` + worker poll; CLI `kling_omni_image` spawn | 3 |
| FEAT-009 admin provider toggle (Admin Web invokes; no credential UI) | 4 |
| Docker global CLI install; Railway creds volume; S1 auth probe runbook | 5 |
| S3 48h credential refresh spike (non-blocking) | 6 |
| End-to-end verification: job extract, provider switch, errors, S1 probe | 7 |
| Higgsfield only for extract jobs (same table) | 2, 3 |
| No sync `--wait` HTTP wrapper phase 1 | 3 |
| FEAT-005 community enqueue reuses worker | 3, 7 |

## Verification ledger

| Claim | Status | Evidence |
| --- | --- | --- |
| `POST /api/extract-pose` enqueues async job and returns `202` | **Verified** | `extractPoseRoutes.ts`; `extractPose.test.ts` L133–151 |
| Mobile client calls sync `/api/extract-pose` and expects `200` base64 | **Verified** | `PoseApiService.kt` L88–111 — follow-on migration out of scope |
| `extraction_jobs` table exists; no `provider` column | **Verified** | `schema.sql` L49–64 |
| `ExtractionJobStore` supports enqueue, claim, succeed, fail/requeue | **Verified** | `extractionJobStore.ts`; `job-processor.test.ts` lifecycle tests |
| Worker uses `PoseExtractorProvider` factory at claim time | **Verified** | `job-processor.ts`; `job-processor.test.ts` provider-switch tests |
| Admin community intake enqueues jobs and returns `202` | **Verified** | `adminCommunityRoutes.ts` L148+ |
| `GET /api/admin/jobs/:jobId` returns job status + result | **Verified** | `jobStatusRoutes.ts` L10–28 |
| Admin routes expose provider settings toggle | **Verified** | `adminSettingsRoutes.ts`; WI-4 |
| Admin Keys page includes extraction provider toggle | **Verified** | `web/admin-ui/src/app/admin/keys/page.js` |
| Next.js admin proxy injects Bearer secret server-side | **Verified** | `poseExtractAdminServer.js` L39–60 |
| Dockerfile installs Higgsfield CLI globally + probe script | **Verified** | `Dockerfile`; `scripts/higgsfield-auth-probe.sh` |
| API spec documents async `202` + `PROVIDER_*` job errors | **Verified** | `docs/harness/specs/api-contract.md#extract-pose`; `docs/harness/specs/api/openapi.yaml` v0.3.0 |
| Higgsfield CLI provider + factory in application source | **Verified** | `higgsfieldCliProvider.ts`, `poseExtractorProvider.ts` |
| `PoseExtractorProvider` interface pattern documented | **Verified** | sub2api phase-01 research doc |
| FEAT-004, FEAT-005, FEAT-007 status is `approved` | **Verified** | feature frontmatter |
| FEAT-009 status is `approved` | **Verified** | `FEAT-009-configure-extraction-provider.md` |
| Higgsfield CLI default model `kling_omni_image`; JSON result URL parse | **Verified** | `higgsfieldCliProvider.ts` `DEFAULT_MODEL`; historical fixture `higgsfield-gpt_image_2-success.json` for parse tests |
| S1 auth probe failure drill documented | **Verified** | `s1-auth-runbook.md` WI-7 section; invalid probe exit 1 |
| S1 auth probe success drill with valid credentials | **Unresolved** | **Owner: Lead/operator** — requires headed login + Railway volume creds; not in CI |
| S3 credential refresh-writes persist >1 day on volume | **Blocked** | **Owner: WI-6** — 48h spike; S1 remains prod path |
| Mobile async poll client for `202` extract | **Documented only** | Server contract in `extract-pose.md` + `design.md`; mobile still sync (`PoseApiService.kt`) — not implemented |
| Public poll route `GET /api/extract-jobs/:jobId` | **Verified** | `extractJobsRoutes.ts`; `extractPose.test.ts` poll tests |
| Provider error mapping (`PROVIDER_*`) in worker | **Verified** | `job-processor.test.ts` error table cases; `higgsfieldCliProvider.test.ts` |

**Totals:** Verified 21 · Documented only 1 · Failed 0 · Unresolved 1 (S1 valid-credentials prod drill) · Blocked 1 (S3 / WI-6)

**Plan completion note:** WI 1–5 and WI-7 are **completed**. WI-6 (S3 48h spike) remains **blocked** and non-blocking for this Plan.

## Risks

| Risk | Mitigation |
| --- | --- |
| Governing Features FEAT-004/005/007 approved | Approved 2026-08-17 Product Authority; FEAT-009 and DEC-001 approved; WI-1 prepares linkage only |
| Mobile still expects sync `200` after server moves to `202` | Document server contract in WI-1; mobile migration is follow-on outside this Plan |
| Higgsfield CLI JSON/output format undocumented | WI-3 captures fixture; fail job with `PROVIDER_CLI_FAILED` on parse errors |
| Headless credential expiry | S1 probe + human re-login runbook (WI-5); no automated `auth login` in Docker |
| Playwright worker removal breaks ops expecting browser path | `gemini_native` uses REST in worker; document deprecation in WI-3 |
| Provider toggle mid-queue | Global setting applies to next `claimNext`; in-flight jobs finish on claimed provider (document in WI-4) |

## Dependencies

- Approved FEAT-004, FEAT-005, FEAT-007 (2026-08-17 Product Authority); FEAT-009 approved (2026-08-16); DEC-001 approved (2026-08-17).
- Higgsfield CLI package availability on npm and Railway network egress for result URL fetch.
- Railway volume for `credentials.json` (S1 path).
- Existing `ExtractionJob` worker infrastructure (`extractionJobStore`, `jobStatusRoutes`).

## Note on governing Features

FEAT-004, FEAT-005, FEAT-007, and FEAT-009 are **approved**. **DEC-001**
extraction provider policy is **approved**. This Plan records implementation
intent and verification evidence. WI-1 updates Feature text for plan linkage
only; it does not approve Features or Decisions.

## Verification

- Unit and integration tests listed in WI-7 and [design.md](./design.md).
- `npm run backend:test` and `npm run backend:build` from repository root.
- `ckh workflow check docs/harness/plans/260816-2240-higgsfield-cli-parallel-extract-provider --workspace .`
- `ckh validate docs/harness/plans/260816-2240-higgsfield-cli-parallel-extract-provider --all`

## Appendix: Requirement parity matrix (WI-1)

| Requirement | Source | Implementation target | Work Item |
| --- | --- | --- | --- |
| FR-001 async extracted image via job poll | FEAT-004 | `POST /api/extract-pose` → `202`; `GET /api/extract-jobs/:jobId` | WI-3 |
| FR-003 enqueue + worker `PoseExtractorProvider` | FEAT-004 | `extractPoseRoutes.ts`, `job-processor.ts`, `worker-main.ts` | WI-2, WI-3 |
| FR-004 dual engines (`gemini_native`, `higgsfield_cli`) | FEAT-004 | `GeminiNativeProvider`, `HiggsfieldCliProvider` | WI-2, WI-3 |
| BR-001 no false usable result | FEAT-004 | Job `failed` + `error_code`; pre-queue validation | WI-3, WI-7 |
| BR-002 engine selection deferred to FEAT-009 | FEAT-004 | `ProviderSettingsStore` read at claim | WI-2, WI-4 |
| FR-001 read global engine (Admin) | FEAT-009 | `GET /api/admin/settings/extraction-provider` | WI-4 |
| FR-002 change global engine | FEAT-009 | `PUT /api/admin/settings/extraction-provider` | WI-4 |
| FR-003 persist across restarts | FEAT-009 | SQLite `app_settings` | WI-2, WI-4 |
| FR-004 reject invalid engine | FEAT-009 | Route validation | WI-4 |
| FR-005 worker uses engine at claim (B1/C1/D2) | FEAT-009 / DEC-001 | Factory in `job-processor.ts` | WI-2, WI-3, WI-4 |
| BR-001 admin-only engine change | FEAT-009 | Admin auth on settings routes | WI-4 |
| FR-001 admin proxies reuse upstream contracts | FEAT-007 | Next.js proxy for settings (invokes FEAT-009) | WI-4 |
| BR-001 no second extraction model in Admin Web | FEAT-007 | Toggle hosts FEAT-009; no duplicate requirements | WI-4 |
| FR-001 `202` queued acceptance | FEAT-005 | `adminCommunityRoutes` enqueue (unchanged shape) | WI-3 |
| FR-002 job status API-013 shape | FEAT-005 | `jobStatusRoutes`, public poll route | WI-3 |
| Async `202` + poll contract | extract-pose.md | Routes + spec alignment | WI-1, WI-3, WI-7 |
| `PROVIDER_*` error codes | extract-pose.md | Provider + route error mapping | WI-2, WI-3, WI-7 |
| Worker provider factory section | technical-architecture | Worker refactor doc (post-WI-3) | WI-7 |
| Docker global CLI + creds volume | design.md | Dockerfile, Railway volume | WI-5 |
| S1 auth probe runbook | design.md | Cron script + runbook | WI-5 |
| S3 48h credential refresh spike | design.md | Writable volume test | WI-6 |
| End-to-end verification | plan verification ledger | Tests + probe | WI-7 |

**Maintainer choices (non-blocking for WI-1):**

- Public poll route: `GET /api/extract-jobs/:jobId` (recommended in design.md) — WI-3 implements.
- Mobile async client: explicitly out of Plan scope — WI-7 documents server contract only.
