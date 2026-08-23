---
schema_version: 1
type: spec
title: Technical Architecture
status: draft
relationships:
  specs:
    - "[[product-feature-inventory]]"
    - "[[ui-ux-system]]"
    - "[[model-entity-catalogue]]"
    - "[[erd]]"
    - "[[api-catalogue]]"
  decisions: []
  plans: []
  reports: []
  rules: []
  features:
    - "[[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]"
    - "[[FEAT-002-manage-a-local-photo-gallery|FEAT-002]]"
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
  source_paths:
    - settings.gradle.kts
    - gradle/libs.versions.toml
    - mobile/composeApp
    - mobile/shared
    - web/admin-ui
    - web/services/pose-extract-server/src
---

# Technical Architecture

## Scope

This document describes the code-backed architecture of the `ai-pose` monorepo. It covers the mobile application targeting both iOS and Android (where Android support is currently an unresolved parity gap), the shared data module, the web/admin application, the extraction service, persistence, and external integrations. The untracked `sub2api/` checkout is excluded because no active build or runtime path imports it.

## System map

| Lane | Runtime | Responsibility | Primary entry points |
| --- | --- | --- | --- |
| Mobile UI | Kotlin 2.0, Compose Multiplatform 1.6, iOS 15+ & Android (unresolved parity gap) | Camera, pose library, gallery, local interactions | `mobile/App.kt`, `mobile/iosApp/iosApp/ContentView.swift` |
| Shared mobile data | Kotlin Multiplatform, SQLDelight 2.0, Ktor 2.3 | Local photos/poses and remote API client | `mobile/shared/src/commonMain/kotlin/com/aipose/data/` |
| Web/admin | Next.js 16.2, React 19.2, Tailwind CSS 4 | Admin UI and server-side proxy routes | `web/admin-ui/src/app/` |
| API service | Node 20+, Express 5, TypeScript 6 | Extraction, community catalog, API-key administration, job status | `web/services/pose-extract-server/src/index.ts`, `src/app.ts` |
| Worker | Node 20+, Playwright | Processes queued extraction jobs through a browser session | `web/services/pose-extract-server/src/worker/worker-main.ts` |

## Runtime flows

### Mobile capture and local gallery

1. Compose requests camera permission through the platform-specific `CameraController` actual implementation (iOS implemented; Android is an unresolved parity gap).
2. A capture returns bytes to `CameraScreen`.
3. `ImageStorage` writes the image to app-private storage, and `PhotoRepository` stores its path in SQLDelight.
4. `GalleryViewModel` observes the database reactively and groups photos chronologically by local timezone day for grid/list presentation.

### Pose extraction API & Key-Pooling Mechanics

1. **Client Request:** A client sends multipart image data via `POST /api/extract-pose`.
2. **Validation and Rate Limiting:** The Express server validates the upload payload (file size, MIME type) and enforces IP-based rate limiting before invoking downstream AI services.
3. **Key Allocation:** The `KeyPoolManager` retrieves an active Gemini API key from the rotating credentials database. If all keys are exhausted or unavailable, it throws a credentials exhausted error.
4. **Provider Invocation:** `GeminiService` forwards the image to the external AI provider, records the key usage, tracks transaction duration, and returns the response.
5. **Async Job Contract (canonical target):** The server **enqueues an `ExtractionJob`** and returns `202` + `jobId`; the client polls `GET /api/extract-jobs/:jobId` until `succeeded`/`failed`. **No `Pose` exists at this stage** — `jobId` is the correlation key. On `succeeded`, the caller finalizes creation via `POST /api/guides` (owner) or admin intake (`201`), which creates the `Pose` (`poseId` stable, **`ownerAccountId` mandatory on every Pose**, `status: local`) and materializes the three `MediaAsset`s (`original`, `skeleton`, `thumbnail`).
6. **Synchronous Transaction Contract (observed legacy):** The current implementation operates as a single request/response flow returning base64-encoded skeleton image data, MIME type, and processing elapsed time. The server has no progressive status endpoint or cancellation hook; client cancellation aborts the local request but does not physically terminate remote server execution.

### Community content administration & Workers

1. **Server Proxying:** Browser requests from the Admin UI pass through server-side Next.js route proxies (`web/admin-ui/src/app/api/admin/`), which inject the `POSE_EXTRACT_ADMIN_SECRET` before forwarding calls to Express.
2. **Metadata and Queueing:** Operators submit community pose metadata and source images via `POST /api/admin/community/poses` or through the two-phase contract: image via `POST /api/extract-pose` (enqueues job, `202` + `jobId`), then pose creation referencing the succeeded `jobId` (`201`). In the current implementation the Express server **enqueues the extraction job and returns `202 Accepted`**; the **`Pose` entity is created ONLY AFTER extraction succeeds (`201 Created`)** — no Pose row exists before that.
3. **Worker Processing:** The background Playwright worker process (`startWorker`) polls the job table, claims pending tasks, executes extraction in a browser session, and writes the generated base64 result back to the `extraction_jobs` row. **`Pose` is the single canonical entity** — `community_poses` (runtime table name, if present) is legacy/operational naming, not a separate canonical entity. **Observed source evidence does not show a durable link from a job to the canonical `Pose`'s `MediaAsset`s; see [ExtractionJob](../../spec/data/entities/extraction-job.md) and [ERD unresolved links](../../spec/data/erd/conceptual.md).**
4. **Pose creation (post-extraction):** Per the canonical domain model, a `Pose` is created **only after the extraction job is `succeeded`** (stable `poseId`, mandatory `ownerAccountId`, `status: local`, three media roles `original`/`skeleton`/`thumbnail` materialized). Public endpoints (`GET /api/community/poses`) filter by **`Pose.status = 'published'`** (exposed through the read-only `CommunityPose` DTO; no separate storage). **The source does not independently prove linked-asset readiness, so the stronger “valid linked R2 URL” claim is unresolved.**

## Data and trust boundaries

- Mobile photos and poses are local SQLDelight records whose image payloads live in app storage.
- Server key, community, and extraction-job state is SQLite-backed through `better-sqlite3`.
- R2 stores community objects; its credentials and the admin secret are server-only configuration.
- Next.js admin API routes proxy to Express using `POSE_EXTRACT_SERVER_URL` and `POSE_EXTRACT_ADMIN_SECRET`; secrets are not placed in client components.
- The Playwright worker requires a separately managed authenticated browser profile. It is operationally distinct from the direct API extraction path.

## Repository authority

- `docs/harness/` is the current-state product and engineering source of truth.
- `docs/superpowers/` and root `plans/` preserve design and implementation history; their completion claims require confirmation against current code.
- `docs/prototype/` is an interactive UI reference, not production behavior.
- `docs/privacy-ugc-compliance.md` is a pre-release checklist, not evidence that public UGC controls are implemented.

## Known gaps

- Root `README.md` is now a monorepo router; detailed runtime contracts remain in the Harness rather than being duplicated there.
- The mobile navigation passes an empty callback for the "Extract Pose" CTA button on the empty-state screen; however, the header Plus button opens a gallery image picker and successfully triggers pose extraction and local database persistence.
- Camera overlay rendering is guarded by `if (false)` in `CameraScreen`, so overlay controls are not current behavior.
- Community API documentation conflicts with the multipart/job implementation described above.
- Production activation and authentication lifecycle of the Playwright worker is not proven by repository configuration alone.
- The Compose iOS simulator production target compiles, but `:shared:iosSimulatorArm64Test` does not: `PoseApiServiceTest.kt` imports `kotlinx.coroutines.test.runTest` without a matching test dependency.
- Android camera capture, local gallery, and SQLDelight driver actual implementations are unresolved parity gaps.

## Verification

Run bounded checks from the repository root:

```sh
npm run backend:test
npm run backend:build
npm run build
./gradlew :composeApp:compileKotlinIosSimulatorArm64 :shared:iosSimulatorArm64Test
ckh validate --all --workspace .
ckh index check --workspace .
```

Build failures are evidence of current health and must be recorded; historical `error.log` is not a substitute for a fresh run.
