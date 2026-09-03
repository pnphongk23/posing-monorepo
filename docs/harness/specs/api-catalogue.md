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

> **Single source of truth: [`api-contract.md`](./api-contract.md)** — conventions
> + module semantics; schemas chi tiết tại [`api/openapi.yaml`](./api/openapi.yaml).
>
> File này chỉ giữ lại để duy trì harness wikilinks và index anchors cũ; không
> chứa nội dung API contract.