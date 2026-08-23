---
schema_version: 1
title: Backend feature and model entity scout
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[product-feature-inventory]]"
  decisions: []
  plans: []
  reports:
    - "[[REP-002-feature-gap-and-release-readiness-audit|REP-002]]"
  rules: []
  features:
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
  source_paths:
    - web/services/pose-extract-server/src/app.ts
    - web/services/pose-extract-server/src/db/schema.sql
    - web/services/pose-extract-server/src/db/communityStore.ts
    - web/services/pose-extract-server/src/db/extractionJobStore.ts
    - web/services/pose-extract-server/src/routes/extractPoseRoutes.ts
    - web/services/pose-extract-server/src/routes/communityRoutes.ts
    - web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts
    - web/services/pose-extract-server/src/routes/jobStatusRoutes.ts
    - web/services/pose-extract-server/src/services/keyStore.ts
    - web/services/pose-extract-server/src/worker/job-processor.ts
    - web/admin-ui/src/app/admin/community/page.js
    - mobile/shared/src/commonMain/sqldelight/com/aipose/Pose.sq
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PreparedPoseReference.kt
type: report
id: REP-004
status: completed
delivered: 2026-08-15
---

# REP-004: Backend feature and model entity scout

## Delivered outcome

This is a read-only scout report for the backend-related product surface. It
closes the current feature inventory and establishes a shared model/entity
vocabulary for the next Feature or Plan. It does not modify application code,
approve a product Decision, or claim that the asynchronous community pipeline
is production-ready.

## Feature baseline

The backend scope should remain within the existing Features; no duplicate
Feature IDs are needed.

| Capability to keep | Governing Feature | Observable scope | Current state |
| --- | --- | --- | --- |
| On-demand pose extraction | [[FEAT-004-extract-reusable-pose-images|FEAT-004]] | Accept an image, validate it, invoke an AI provider, and return one generated pose image with a structured result. | **Observed:** synchronous route, key pooling, provider call, usage logging, and error mapping exist. **Blocked:** validation, cancellation, abuse, and client/server contract gaps remain. |
| Browse community pose references | [[FEAT-003-browse-and-search-published-poses|FEAT-003]] | List and inspect published community poses with pagination and filters; provide a retrievable render asset to the mobile client. | **Observed:** public list/detail routes and mobile DTOs exist. **Blocked:** client contract/runtime parity and community asset readiness are not fully proven. |
| Administer extraction capacity | [[FEAT-005-manage-a-pose-guide|FEAT-005]] | Privileged operator can create, inspect, update, disable, delete, and reset provider key records without exposing the secret to the browser. | **Observed:** Bearer authentication, rate limiting, CRUD/status/reset routes, and Next.js server-side proxying exist. |
| Ingest and publish community poses | [[FEAT-005-manage-a-pose-guide|FEAT-005]] with [[FEAT-003-browse-and-search-published-poses|FEAT-003]] | Operator submits metadata and a source image; the system processes it asynchronously, stores a generated asset, and exposes it publicly only after it is ready. | **Failed:** job-to-pose-to-asset linkage and worker-to-R2 publication are missing. This is the main server release blocker. |
| Observe asynchronous work | [[FEAT-005-manage-a-pose-guide|FEAT-005]] | Operator can distinguish queued, processing, succeeded, and failed outcomes and recover from terminal failures. | **Observed:** protected job-status endpoint and retry counters exist. **Failed:** admin UI treats HTTP 202 as success and worker recovery/concurrency is incomplete. |

FEAT-001 and FEAT-002 remain local mobile storage features, not backend
features. `sub2api/` remains an untracked standalone checkout and is not part
of the active runtime lane. The historical Sub2API provider plan is therefore
tracked as future work, not as an implemented feature.

## Canonical model and entity baseline

The following is the shared vocabulary to use in subsequent Feature and Plan
work. It is a semantic baseline, not a completed database migration.

| Canonical entity | System of record | Current implementation | Responsibility |
| --- | --- | --- | --- |
| `PoseReference` | Product concept | Mobile uses `PoseReferenceKey.Personal` or `.Community`. | Source-qualified identity for a pose selected, displayed, or handed to Camera. It is not one physical table. |
| `PersonalPose` | Mobile local database | SQLDelight table `Pose`, identified by `Long`. | User-owned local pose metadata and local/embedded image locators. It must not be mixed with server community records. |
| `CommunityPose` | Server SQLite | `community_poses` and `CommunityPoseRecord`, identified by UUID. | Public/catalog metadata, moderation/publication state, and reference to the render asset. |
| `MediaAsset` | Local storage or R2 | **Unresolved (TBD):** no first-class server entity; current code stores `imagePath` and job base64 fields. | Shared semantic object for source, generated render, and thumbnail assets, including storage locator and MIME metadata. |
| `ExtractionJob` | Server SQLite | `extraction_jobs` and `ExtractionJob`, identified by UUID. | Async processing state, attempts, lock, error, source/result payloads. It currently lacks durable links to `CommunityPose` and `MediaAsset`. |
| `ApiKeyCredential` | Server SQLite | `api_keys` and `KeyStore`. | Provider credential lifecycle and usage counters. The secret is server-only even though the internal record contains it. |
| `ProviderRequestLog` | Server SQLite | `request_logs` and `RequestLogRecord`. | Provider usage, duration, success, and error diagnostics. It is not a user-facing pose entity. |

### Baseline relationships

```text
PoseReference
├── PersonalPose       (mobile-local source)
└── CommunityPose      (server-owned source)

CommunityPose ──< ExtractionJob ──> MediaAsset(source/result)
CommunityPose ────────────────> MediaAsset(render/thumbnail)
ApiKeyCredential ──< ProviderRequestLog
```

**Observed:** `PoseReferenceKey` already prevents Personal and Community IDs
from colliding on mobile, and `PreparedPoseReference` carries a verified render
locator into the future Camera handoff. **Inferred:** the server needs the same
source-qualified distinction rather than treating `imagePath` as the identity.

The minimum semantic fields for the missing `MediaAsset` relationship are:
asset identity, owner/reference, role (`source`, `render`, or `thumbnail`),
storage kind, storage key or local locator, MIME type, and readiness. Exact
column names, retention, checksum, and whether asset history is retained are
left for a later technical Decision.

The minimum relationship fields needed by `ExtractionJob` are:
`communityPoseId`, `sourceAssetId`, and `resultAssetId` (nullable until the
worker succeeds). Current schema evidence shows none of these fields, so the
worker cannot durably connect its result to the pose that will be published.

## Architecture and flows

### Synchronous extraction

```text
Mobile client
  → POST /api/extract-pose
  → upload validation + per-IP limiter
  → KeyPoolManager / ApiKeyCredential
  → GeminiService
  → ProviderRequestLog
  → imageBase64 response
```

The route is synchronous and has no server-side progress or cancellation
contract. A provider quota error exhausts the selected key and retries with
another active key.

### Community ingestion and publication

```text
Admin browser
  → Next.js server proxy with admin secret
  → POST /api/admin/community/poses
  → CommunityPose + ExtractionJob
  → Playwright worker
  → provider result
  → [MISSING: MediaAsset upload/link/readiness]
  → public community catalog
```

**Observed:** the API returns `202` and a `jobId`; the worker stores a generated
base64 result in the job row. **Failed:** the worker does not upload/link the
result to a community asset, while the route can construct an `imagePath` and
accept a published status before the asset is ready.

### Public catalog

`GET /api/community/poses` filters to published records and returns pagination;
`GET /api/community/poses/:id` returns a published record and increments the
download count. Public readiness must therefore be owned by the
CommunityPose-to-MediaAsset lifecycle, not inferred from HTTP 202.

## Relevant code and evidence

- `web/services/pose-extract-server/src/app.ts` — mounts health, extraction, public community, admin community, and job-status routes.
- `web/services/pose-extract-server/src/routes/extractPoseRoutes.ts` — multipart validation, rate limiting, key rotation, provider invocation, and synchronous response.
- `web/services/pose-extract-server/src/routes/communityRoutes.ts` — published-only public list/detail contract.
- `web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts` — admin upload URL, multipart submission, queue creation, and pose creation.
- `web/services/pose-extract-server/src/db/schema.sql` — current `api_keys`, `request_logs`, `community_poses`, and `extraction_jobs` tables.
- `web/services/pose-extract-server/src/worker/job-processor.ts` — claims a job, invokes the browser client, and marks only the job result.
- `mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt` — mobile extraction/community DTOs and server error envelope.
- `mobile/shared/src/commonMain/sqldelight/com/aipose/Pose.sq` — local `PersonalPose` storage shape.
- `mobile/shared/src/commonMain/kotlin/com/aipose/data/PreparedPoseReference.kt` — verified render locator prepared for Camera handoff.

## Findings and risks

- **Observed:** the backend test suite, TypeScript build, and TypeScript lint pass; this validates route/store/service behavior covered by tests, not the missing worker-to-R2 pipeline.
- **Observed:** `community_poses.image_path` is a URL-like string while `extraction_jobs` stores source/result images as base64; there is no shared asset entity.
- **Observed:** community enqueue and pose creation are separate writes, and the job schema has no pose or asset foreign key.
- **Failed:** no repository evidence proves `ExtractionJob → MediaAsset → published CommunityPose` end-to-end.
- **Inferred:** FEAT-005 should own the complete asynchronous state machine, while FEAT-003 should consume only ready public records.
- **Inferred:** PersonalPose and CommunityPose should remain separate persistence entities while sharing the `PoseReference` vocabulary.
- **Unresolved (TBD):** exact publish-state vocabulary (`draft`, `processing`, `ready`, `published`, `failed`) and who is allowed to transition it.
- **Unresolved (TBD):** whether direct Gemini and browser Gemini are separate supported modes or one canonical provider path.
- **Unresolved (TBD):** asset retention/deletion policy and whether failed/orphan jobs are retained for audit.

## Active work and constraints

- Existing `FEAT-003`, `FEAT-004`, and `FEAT-005` are the governing product artifacts and remain draft/blocked according to the current Harness evidence.
- REP-002 already records the critical backend gaps; this report refines its feature ownership and model/entity vocabulary without rewriting its completed history.
- The repository contains preserved user changes in mobile and documentation paths; this report does not normalize or revert them.
- `/use-agy` is not present as a callable skill or command in the current workspace/catalog. No AGY result is fabricated here; prior AGY evidence remains referenced through REP-002.

## Unknowns

- **Unresolved (TBD):** Product Authority must confirm the exact user-visible community lifecycle and publication behavior before a coding Plan is approved.
- **Unresolved (TBD):** Repository Maintainer must confirm the technical shape of `MediaAsset` and the job/pose transaction boundary before schema migration work.
- **Unresolved (TBD):** The smallest next implementation check is an integration test that submits one community pose, runs one worker job, verifies one durable asset, and confirms the public route exposes it only after readiness.

## Changed files

- `docs/harness/reports/REP-004-backend-feature-and-model-entity-scout.md` — this read-only scout report.
- `docs/harness/index.md` — regenerated Harness catalog/backlinks after adding REP-004.

## Verification evidence

- `npx gitnexus status` — repository index is up-to-date at commit `5011daa`.
- `npm run backend:test` — 14 test files and 78 tests passed.
- `npm run backend:build` — TypeScript build passed.
- `npm --prefix web/services/pose-extract-server run lint` — TypeScript lint passed.
- `ckh validate --all --workspace .` — passed before report authoring.
- Direct source inspection with `rg`, `sed`, and line-numbered evidence covered the server routes, stores, worker, mobile DTOs, local entity, existing Features, Specs, Plans, and Reports.
- **Tôi không thể xác minh điều này hoạt động vì** the repository has no passing end-to-end evidence for worker result upload, pose/asset linkage, and public publication readiness.

## Plan variance

No implementation Plan governed this read-only report. No application code,
database schema, provider configuration, or product lifecycle was changed.

## Repeated friction

- `RTK.md` is referenced by repository instructions but is absent from the workspace search path.
- `/use-agy` is requested but unavailable as a local skill/command, so the report explicitly labels that limitation and uses direct scout evidence.
