# Product spec

Nguồn sự thật cho hợp đồng dữ liệu và API của ai-pose. Harness Features mô tả hành vi; folder này mô tả entity, ERD, enum, và HTTP contract.

Tên entity / path / field tiếng Anh. Mô tả tiếng Việt. URL thật `/api/...`, không có `/v1/`.

## Cấu trúc

| Thư mục | Nội dung |
|---|---|
| [`data/`](data/README.md) | Domain model, entities, ERD, enums |
| [`api/`](api/README.md) | OpenAPI, conventions, API modules |

## Đọc theo nhu cầu

- **Entity, field, business rule** → [`data/entities/`](data/entities/)
- **Quan hệ** → [`data/erd/`](data/erd/)
- **Enum** → [`data/enums.md`](data/enums.md)
- **HTTP path, schema, status** → [`api/openapi.yaml`](api/openapi.yaml)
- **Auth, pagination, error envelope** → [`api/conventions.md`](api/conventions.md)
- **Semantics từng nhóm route** → [`api/modules/`](api/modules/)
- **Hành vi product** → [`../harness/features/`](../harness/features/)

## Feature map

| Feature | Data | API |
|---|---|---|
| FEAT-001, FEAT-002 | [Photo](data/entities/photo.md), [PersonalPose](data/entities/personal-pose.md) | Không có HTTP |
| FEAT-003 | [CommunityPose](data/entities/community-pose.md) | [community](api/modules/community.md) |
| FEAT-004 | [ExtractionJob](data/entities/extraction-job.md) | [extract-pose](api/modules/extract-pose.md) |
| FEAT-005 | [PoseGuide](data/entities/pose-guide.md), [MediaAsset](data/entities/media-asset.md) | [guides](api/modules/guides.md) |
| FEAT-006 | PoseGuide visibility | [publish](api/modules/publish.md) |
| FEAT-007 | Cùng model trên | [admin](api/modules/admin-community.md) |
| FEAT-008 | [Account](data/entities/account.md), [SavedEntry](data/entities/saved-entry.md), [PreparedPoseReference](data/entities/prepared-pose-reference.md) | [saved](api/modules/saved.md) |
