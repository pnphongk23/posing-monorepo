---
schema_version: 1
title: Operate Pose Content from Admin Web
relationships:
  specs:
    - "[[product-feature-inventory]]"
    - "[[technical-architecture]]"
    - "[[ui-ux-system]]"
    - "[[model-entity-catalogue]]"
    - "[[erd]]"
    - "[[api-catalogue]]"
  decisions: []
  plans:
    - "[[260816-2240-higgsfield-cli-parallel-extract-provider/plan|260816-2240]]"
  reports:
    - "[[REP-002-feature-gap-and-release-readiness-audit|REP-002]]"
    - "[[REP-004-backend-feature-and-model-entity-scout|REP-004]]"
  rules: []
  features:
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
    - "[[FEAT-006-publish-a-pose|FEAT-006]]"
    - "[[FEAT-009-configure-extraction-provider|FEAT-009]]"
  source_paths:
    - web/admin-ui/src/app/admin/keys/page.js
    - web/admin-ui/src/app/admin/community/page.js
    - web/admin-ui/src/app/api/admin
    - web/admin-ui/src/lib/poseExtractAdminServer.js
    - web/services/pose-extract-server/src/routes/adminRoutes.ts
    - web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts
type: feature
id: FEAT-007
status: approved
created: 2026-08-15
approved: 2026-08-17
approved_by: Product Authority
---

# FEAT-007: Operate Pose Content from Admin Web

## Introduction

An authorized Admin operator uses one web surface for provider-key operations
and community pose intake/listing. This is an operating context, not a second
extraction, pose-guide, or publication model; it invokes FEAT-004, FEAT-005,
FEAT-006, and [FEAT-009](FEAT-009-configure-extraction-provider.md) for
extraction-engine configuration (FEAT-007 does not own provider configuration).

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Admin operator | Business role | Operate provider and pose intake safely | Use protected Admin Web actions |
| Next.js proxy | System boundary | Keep admin secret server-side | Forward canonical upstream calls |

### Preconditions

- Admin Web has the server URL and admin secret configuration; the operator is authorized by the upstream Bearer check.

### Trigger

The operator manages keys, lists community poses, or submits a pose.

### Main flow

1. **Actor:** The operator opens an Admin page. **System:** Next.js calls the protected upstream service.
2. **Actor:** The operator submits an action. **System:** The proxy forwards the request and returns the upstream status/payload.
3. **System:** The Admin UI presents the confirmed response. **System:** Async `202` remains an accepted queue state, not completion.

### Alternative flows

- **A1 — Refresh.** Source step: 1 or 3. Condition: the operator requests current data. Behavior: call the same canonical endpoint again. Resume at step: 1.

### Exception flows

- **E1 — Missing/invalid admin configuration.** Source step: 1. Failure: proxy cannot construct an upstream request. Handling: show proxy failure. Prohibited: exposing secrets or claiming success.
- **E2 — Upstream rejection.** Source step: 2. Failure: auth/validation/worker intake fails. Handling: preserve last confirmed UI state. Prohibited: converting acceptance into completion.

### Postconditions

- **Success:** The operator sees the upstream confirmed result.
- **Failure:** Protected data remains server-side and the last confirmed state is retained.

### Current evidence

- **Observed:** Admin Keys and Community pages exist; Next.js server-side proxies
  inject `POSE_EXTRACT_ADMIN_SECRET`; Express admin routes use Bearer auth.
- **Observed:** Key CRUD/status/reset, community listing, upload-url, and
  multipart submission proxies are implemented.
- **Not observed:** Admin polling of API-013, owner assignment, publication
  update/unpublish actions, or a confirmed truthful UI state for the async job.
- **Planned (draft):** [Plan 260816-2240](../../plans/260816-2240-higgsfield-cli-parallel-extract-provider/plan.md)
  adds Admin Web proxy routes and UI host for the
  [FEAT-009](FEAT-009-configure-extraction-provider.md) extraction-engine
  toggle; FEAT-007 invokes FEAT-009 and does not own provider configuration.

### Traceability

| Concern | Canonical reference | Evidence |
| --- | --- | --- |
| Entities | [`CommunityPose`](../../spec/data/entities/community-pose.md), [`ExtractionJob`](../../spec/data/entities/extraction-job.md), [`ApiKeyCredential`](../../spec/data/entities/api-key-credential.md) | [`schema.sql`](../../../web/services/pose-extract-server/src/db/schema.sql), [`KeyStore`](../../../web/services/pose-extract-server/src/services/keyStore.ts) |
| ERD | [Server physical graph](../../spec/data/erd/server.md) and [unresolved job/asset links](../../spec/data/erd/conceptual.md) | [`app.ts`](../../../web/services/pose-extract-server/src/app.ts) |
| APIs | [Next.js proxies](../../spec/api/conventions.md), upstream [admin keys](../../spec/api/modules/admin-keys.md) / [community](../../spec/api/modules/admin-community.md) / [jobs](../../spec/api/modules/admin-jobs.md) | [`web/admin-ui/src/app/api/admin`](../../../web/admin-ui/src/app/api/admin), [`poseExtractAdminServer.js`](../../../web/admin-ui/src/lib/poseExtractAdminServer.js) |
| Supporting UI | Key and community admin pages | [`keys/page.js`](../../../web/admin-ui/src/app/admin/keys/page.js), [`community/page.js`](../../../web/admin-ui/src/app/admin/community/page.js) |

## Requirements

- **FR-001:** Admin proxies reuse the shared upstream API contracts.
- **FR-002:** Admin secrets are injected server-side and never documented as browser payloads.
- **BR-001:** Admin Web must not define a second extraction, guide, or publication model.

## Acceptance

- [ ] Key and community proxy paths are traceable to upstream APIs.
- [ ] Invalid/auth failures are not shown as confirmed success.
- [ ] `202` community submission is labelled accepted/queued, not complete/public.

## Relationships

- Shared references: [CommunityPose](../../spec/data/entities/community-pose.md), [ERD server](../../spec/data/erd/server.md), [proxies](../../spec/api/conventions.md).
- Related features: [FEAT-004](FEAT-004-extract-reusable-pose-images.md), [FEAT-005](FEAT-005-manage-a-pose-guide.md), [FEAT-006](FEAT-006-publish-a-pose.md), [FEAT-009](FEAT-009-configure-extraction-provider.md) (Admin Web invokes FEAT-009 for global extraction-engine configuration).
### Supporting evidence

- [`poseExtractAdminServer.js`](../../../web/admin-ui/src/lib/poseExtractAdminServer.js)
- [`admin/keys/page.js`](../../../web/admin-ui/src/app/admin/keys/page.js)
- [`admin/community/page.js`](../../../web/admin-ui/src/app/admin/community/page.js)
- [`adminRoutes.ts`](../../../web/services/pose-extract-server/src/routes/adminRoutes.ts)
- [`REP-004`](../reports/REP-004-backend-feature-and-model-entity-scout.md)
