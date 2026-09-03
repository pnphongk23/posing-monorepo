---
schema_version: 1
type: spec
title: Harness Model and Entity Catalogue
status: draft
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[product-feature-inventory]]"
    - "[[erd]]"
    - "[[api-catalogue]]"
  decisions: []
  plans: []
  reports:
    - "[[REP-004-backend-feature-and-model-entity-scout|REP-004]]"
  rules: []
  features:
    - "[[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]"
    - "[[FEAT-002-manage-a-local-photo-gallery|FEAT-002]]"
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
    - "[[FEAT-006-publish-a-pose|FEAT-006]]"
    - "[[FEAT-007-operate-pose-content-from-admin-web|FEAT-007]]"
    - "[[FEAT-008-use-published-poses|FEAT-008]]"
  source_paths:
    - mobile/shared/src/commonMain/sqldelight/com/aipose/Photo.sq
    - mobile/shared/src/commonMain/sqldelight/com/aipose/Pose.sq
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PhotoRepository.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseRepository.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PreparedPoseReference.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt
    - web/services/pose-extract-server/src/db/schema.sql
    - web/services/pose-extract-server/src/db/communityStore.ts
    - web/services/pose-extract-server/src/db/extractionJobStore.ts
    - web/services/pose-extract-server/src/services/keyStore.ts
---

# Model and Entity Catalogue — stub

> **Nguồn sự thật mô hình dữ liệu nằm tại [`docs/spec/data/`](../../spec/data/README.md)** —
> entity index + layer/ownership tại [`README.md`](../../spec/data/README.md),
> domain model [`domain-model.md`](../../spec/data/domain-model.md), entity files
> [`entities/`](../../spec/data/entities/), enums [`enums.md`](../../spec/data/enums.md),
> ERD tại [`erd/`](../../spec/data/erd/).
>
> File này chỉ giữ lại để duy trì harness wikilinks và index anchors cũ; không
> chứa nội dung catalogue.