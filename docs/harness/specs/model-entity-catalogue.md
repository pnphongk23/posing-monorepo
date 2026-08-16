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
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseReferenceKey.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PreparedPoseReference.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt
    - web/services/pose-extract-server/src/db/schema.sql
    - web/services/pose-extract-server/src/db/communityStore.ts
    - web/services/pose-extract-server/src/db/extractionJobStore.ts
    - web/services/pose-extract-server/src/services/keyStore.ts
---

# Model and Entity Catalogue — stub

> **Nguồn sự thật đã chuyển sang [`docs/data/`](../../data/).**

Tài liệu này được giữ lại để duy trì harness wikilinks. Nội dung catalogue không còn ở đây.

| Tài nguyên | Đường dẫn |
|---|---|
| Entity index | [`docs/data/README.md`](../../data/README.md) |
| Domain model & TBD section | [`docs/data/domain-model.md`](../../data/domain-model.md) |
| Entity files (Photo, PersonalPose, CommunityPose, v.v.) | [`docs/data/entities/`](../../data/entities/) |
| Enums (PoseStatus, PoseDifficulty, ApiKeyStatus, ExtractionJobStatus) | [`docs/data/enums.md`](../../data/enums.md) |
| ERD (server, mobile, conceptual) | [`docs/data/erd/`](../../data/erd/) |

_Mapping ID cũ (tham chiếu nhanh cho harness features):_

<a id="me-001--photo--personal-captured-photo"></a>
<a id="me-002--personalpose--local-pose-row"></a>
<a id="me-003--communitypose"></a>
<a id="me-004--mediaasset--cross-feature-media-concept"></a>
<a id="me-005--extractionjob"></a>
<a id="me-006--apikeycredential"></a>
<a id="me-007--providerrequestlog"></a>
<a id="me-008--posereference"></a>
<a id="me-009--preparedposereference"></a>
<a id="me-011--paginationinfo--paginated-list-envelope"></a>
<a id="me-013--poseguide"></a>
<a id="me-014--account-and-savedentry"></a>

| ID cũ | Entity mới |
|---|---|
| ME-001 | [Photo](../../data/entities/photo.md) |
| ME-002 | [PersonalPose](../../data/entities/personal-pose.md) |
| ME-003 | [CommunityPose](../../data/entities/community-pose.md) |
| ME-004 | MediaAsset — TBD, xem [domain-model.md](../../data/domain-model.md) |
| ME-005 | [ExtractionJob](../../data/entities/extraction-job.md) |
| ME-006 | [ApiKeyCredential](../../data/entities/api-key-credential.md) |
| ME-007 | [ProviderRequestLog](../../data/entities/provider-request-log.md) |
| ME-008 | [PoseReferenceKey](../../data/entities/pose-reference-key.md) |
| ME-009 | [PreparedPoseReference](../../data/entities/prepared-pose-reference.md) |
| ME-010–ME-012 | Transport DTOs — xem [openapi.yaml](../../api/openapi.yaml) |
| ME-013 | PoseGuide — TBD, xem [domain-model.md](../../data/domain-model.md) |
| ME-014 | Account/SavedEntry — TBD, xem [domain-model.md](../../data/domain-model.md) |
