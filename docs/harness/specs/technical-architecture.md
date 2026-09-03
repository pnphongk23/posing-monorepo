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

Code-backed architecture of the `ai-pose` monorepo: the mobile application
targeting iOS first (Android is an unresolved parity gap), the shared data
module, the web/admin application, the extraction service, persistence, and
external integrations. The untracked `sub2api/` checkout is excluded because no
active build or runtime path imports it.

> **Quan hệ tài liệu:** architecture map này mô tả *cấu trúc runtime*. Hợp đồng
> dữ liệu/API (fields, business rules, paths, status codes) và domain model là
> nguồn sự thật tại [`docs/spec/`](../../spec/README.md) — không lặp lại ở đây.
> Hành vi product theo Feature thuộc [`docs/harness/features/`](../features/).

## System map

| Lane | Runtime | Responsibility | Primary entry points |
| --- | --- | --- | --- |
| Mobile UI | Kotlin 2.0, Compose Multiplatform 1.6, iOS 15+ & Android (unresolved parity gap) | Camera, pose library, gallery, local interactions | `mobile/App.kt`, `mobile/iosApp/iosApp/ContentView.swift` |
| Shared mobile data | Kotlin Multiplatform, SQLDelight 2.0, Ktor 2.3 | Local photos/poses and remote API client | `mobile/shared/src/commonMain/kotlin/com/aipose/data/` |
| Web/admin | Next.js 16.2, React 19.2, Tailwind CSS 4 | Admin UI and server-side proxy routes | `web/admin-ui/src/app/` |
| API service | Node 20+, Express 5, TypeScript 6 | Extraction, community catalog, API-key administration, job status | `web/services/pose-extract-server/src/index.ts`, `src/app.ts` |
| Worker | Node 20+, Playwright | Processes queued extraction jobs through a browser session | `web/services/pose-extract-server/src/worker/worker-main.ts` |

## Runtime flows (survey)

Flow chi tiết (kể cả 202/201 creation timing, ba media role, `ownerAccountId`,
key pooling) là hợp đồng tại [`docs/spec/data/domain-model.md`](../../spec/data/domain-model.md)
và [`docs/spec/api/modules/`](../../spec/api/modules/); dưới đây chỉ là bản đồ
lan truyền giữa các lane.

### Mobile capture and local gallery

1. Compose requests camera permission through the platform-specific
   `CameraController` actual (iOS implemented; Android parity gap).
2. Capture returns bytes to `CameraScreen`; `ImageStorage` writes to app-private
   storage and `PhotoRepository` stores the path in SQLDelight.
3. `GalleryViewModel` observes the database reactively and groups photos by local
   timezone day. Photo/Pose mobile entity semantics:
   [`docs/spec/data/entities/photo.md`](../../spec/data/entities/photo.md).

### Pose extraction (API + worker + key pooling)

1. Client submits multipart image via `POST /api/extract-pose`; the server
   **enqueues an `ExtractionJob`** and returns `202` + `jobId` (no `Pose` exists
   yet). Contract: [`modules/extract-pose.md`](../../spec/api/modules/extract-pose.md),
   [`entities/extraction-job.md`](../../spec/data/entities/extraction-job.md),
   [openapi.yaml](../../spec/api/openapi.yaml).
2. `KeyPoolManager` allocates a Gemini API key from the rotating credential
   database; `GeminiService` forwards the image, records usage, tracks duration.
   Provider policy: [`DEC-001`](../decisions/DEC-001-extraction-provider-selection-policy.md).
3. The Playwright worker (`startWorker`) polls the job table, claims pending
   jobs, runs extraction in a browser session, and writes results back to the
   `extraction_jobs` row.
4. On `succeeded`, the caller finalizes Pose creation (`POST /api/guides` for
   owner, admin intake for Admin) → `201` — Pose + three MediaAssets
   materialized. Canonical timing: [`entities/pose.md`](../../spec/data/entities/pose.md).

### Community content administration

1. Admin UI requests pass through Next.js server-side proxies
   (`web/admin-ui/src/app/api/admin/`) which inject the
   `POSE_EXTRACT_ADMIN_SECRET` before forwarding to Express
   ([`conventions.md`](../../spec/api/conventions.md)).
2. Operators submit pose metadata/images via `POST /api/admin/community/poses`
   (enqueue → `202`) and finalize creation after extraction succeeds (`201`).
   Contracts: [`modules/admin-community.md`](../../spec/api/modules/admin-community.md),
   [`modules/admin-jobs.md`](../../spec/api/modules/admin-jobs.md).
3. The canonical entity is `Pose`; `community_poses` (runtime table name, if
   present) is legacy/operational naming, not a separate canonical entity
   ([`entities/pose.md`](../../spec/data/entities/pose.md),
   [`ERD conceptual`](../../spec/data/erd/conceptual.md)).

## Data and trust boundaries

- Mobile photos/poses are local SQLDelight records; image payloads live in app
  storage.
- Server key, community, and extraction-job state is SQLite-backed through
  `better-sqlite3`.
- R2 stores community objects; its credentials and the admin secret are
  server-only configuration.
- Next.js admin routes proxy to Express using `POSE_EXTRACT_SERVER_URL` and
  `POSE_EXTRACT_ADMIN_SECRET`; secrets are not placed in client components.
- The Playwright worker requires a separately managed authenticated browser
  profile; it is operationally distinct from the direct API extraction path.
- Runtime table naming is operational; canonical domain model is
  [`docs/spec/data/`](../../spec/data/README.md).

## Repository authority

- `docs/harness/` is the current-state product and engineering source of truth.
- Historical design records and root `plans/` preserve design and implementation
  history; their completion claims require confirmation against current code.
- `docs/prototype/` is an interactive UI reference, not production behavior.
- `docs/privacy-ugc-compliance.md` is a pre-release checklist, not evidence that
  public UGC controls are implemented.

## Known gaps

- Root `README.md` is a monorepo router; detailed runtime contracts live in the
  Harness rather than being duplicated there.
- The mobile empty-state "Extract Pose" CTA passes an empty callback; the header
  Plus button opens a gallery image picker and successfully triggers extraction
  and local persistence.
- Camera overlay rendering is guarded by `if (false)` in `CameraScreen`, so
  overlay controls are not current behavior.
- Production activation and authentication lifecycle of the Playwright worker is
  not proven by repository configuration alone.
- `:shared:iosSimulatorArm64Test` does not compile: `PoseApiServiceTest.kt`
  imports `kotlinx.coroutines.test.runTest` without a matching test dependency.
- Android camera capture, local gallery, and SQLDelight driver actual
  implementations are unresolved parity gaps.

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

Build failures are evidence of current health and must be recorded; historical
`error.log` is not a substitute for a fresh run.