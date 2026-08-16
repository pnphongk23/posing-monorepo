---
schema_version: 1
type: spec
title: Harness API Catalogue
status: draft
relationships:
  specs:
    - "[[model-entity-catalogue]]"
    - "[[erd]]"
    - "[[technical-architecture]]"
  decisions: []
  plans: []
  reports:
    - "[[REP-004-backend-feature-and-model-entity-scout|REP-004]]"
    - "[[REP-002-feature-gap-and-release-readiness-audit|REP-002]]"
  rules: []
  features:
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
    - "[[FEAT-006-publish-a-pose|FEAT-006]]"
    - "[[FEAT-007-operate-pose-content-from-admin-web|FEAT-007]]"
    - "[[FEAT-008-use-published-poses|FEAT-008]]"
  source_paths:
    - web/services/pose-extract-server/src/app.ts
    - web/services/pose-extract-server/src/routes/adminRoutes.ts
    - web/services/pose-extract-server/src/routes/extractPoseRoutes.ts
    - web/services/pose-extract-server/src/routes/communityRoutes.ts
    - web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts
    - web/services/pose-extract-server/src/routes/jobStatusRoutes.ts
    - web/admin-ui/src/app/api
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt
---

# API Catalogue — stub

> **Nguồn sự thật đã chuyển sang [`docs/api/`](../../api/).**

Tài liệu này được giữ lại để duy trì harness wikilinks. API catalogue không còn ở đây.

<a id="server-endpoints"></a>
<a id="api-001--get-apihealth"></a>
<a id="api-003--post-apiextract-pose"></a>
<a id="api-004--get-apiadminkeys"></a>
<a id="api-008--get-apicommunityposes"></a>
<a id="api-009--get-apicommunityposesid"></a>
<a id="api-010--get-apiadmincommunityposes"></a>
<a id="api-020-detail--legacy-post-apiextract"></a>
<a id="nextjs-proxy-and-legacy-routes"></a>
<a id="explicitly-absent-or-unresolved-api-contracts"></a>

| Tài nguyên | Đường dẫn |
|---|---|
| API index | [`docs/api/README.md`](../../api/README.md) |
| OpenAPI 3.1 contract (paths, schemas, status codes) | [`docs/api/openapi.yaml`](../../api/openapi.yaml) |
| Conventions (URL, auth, pagination, errors) | [`docs/api/conventions.md`](../../api/conventions.md) |
| Health | [`docs/api/modules/health.md`](../../api/modules/health.md) |
| Extract Pose | [`docs/api/modules/extract-pose.md`](../../api/modules/extract-pose.md) |
| Community (public) | [`docs/api/modules/community.md`](../../api/modules/community.md) |
| Admin Keys | [`docs/api/modules/admin-keys.md`](../../api/modules/admin-keys.md) |
| Admin Community | [`docs/api/modules/admin-community.md`](../../api/modules/admin-community.md) |
| Admin Jobs | [`docs/api/modules/admin-jobs.md`](../../api/modules/admin-jobs.md) |

_Mapping ID cũ (tham chiếu nhanh cho harness features):_

| ID cũ | Route | Module |
|---|---|---|
| API-001 | `GET /api/health` | [health.md](../../api/modules/health.md) |
| API-003 | `POST /api/extract-pose` | [extract-pose.md](../../api/modules/extract-pose.md) |
| API-004 | `GET /api/admin/keys` | [admin-keys.md](../../api/modules/admin-keys.md) |
| API-005 | `POST /api/admin/keys` | [admin-keys.md](../../api/modules/admin-keys.md) |
| API-006 | `PATCH /api/admin/keys/:id` | [admin-keys.md](../../api/modules/admin-keys.md) |
| API-007 | `DELETE /api/admin/keys/:id`, `POST /api/admin/keys/reset` | [admin-keys.md](../../api/modules/admin-keys.md) |
| API-008 | `GET /api/community/poses` | [community.md](../../api/modules/community.md) |
| API-009 | `GET /api/community/poses/:id` | [community.md](../../api/modules/community.md) |
| API-010 | `GET /api/admin/community/poses` | [admin-community.md](../../api/modules/admin-community.md) |
| API-011 | `POST /api/admin/community/poses/upload-url` | [admin-community.md](../../api/modules/admin-community.md) |
| API-012 | `POST /api/admin/community/poses` | [admin-community.md](../../api/modules/admin-community.md) |
| API-013 | `GET /api/admin/jobs/:jobId` | [admin-jobs.md](../../api/modules/admin-jobs.md) |
| API-015–API-019 | Next.js proxies | [conventions.md](../../api/conventions.md) |
| API-020 | Legacy `POST /api/extract` | [conventions.md](../../api/conventions.md) |
