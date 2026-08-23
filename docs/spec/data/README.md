# Tài liệu Data

Nguồn sự thật duy nhất cho mô hình dữ liệu product của ai-pose.

Tài liệu này mô tả **hợp đồng dữ liệu mà Features yêu cầu**, không mô tả schema runtime. Tên entity, field, và enum giữ tiếng Anh; mô tả viết tiếng Việt.

## Cấu trúc

| Tệp/Thư mục | Nội dung |
|---|---|
| [`domain-model.md`](domain-model.md) | Tổng quan domain, ranh giới layer, Feature ownership |
| [`entities/`](entities/) | Một file per entity: fields, relationships, business rules |
| [`erd/`](erd/) | ERD dạng Mermaid: server, mobile, conceptual overlay |
| [`enums.md`](enums.md) | Shared enums với giá trị và ý nghĩa |
| [`CHANGELOG.md`](CHANGELOG.md) | Lịch sử thay đổi tài liệu data |

## Phân loại thực thể

> Canonical: một entity `Pose` duy nhất; catalogue công khai là view/DTO
> (`status = published`). **`Pose` được tạo chỉ sau khi extraction `succeeded`**
> (trong lúc extraction chỉ có `ExtractionJob` với `jobId`); `ownerAccountId`
> bắt buộc trên mọi Pose; ba media role (`original`, `skeleton`, `thumbnail`)
> materialize tại lúc tạo, non-nullable. Glossary:
> [`../../../harness/specs/pose-domain-glossary.md`](../../harness/specs/pose-domain-glossary.md).

| Entity | Layer | Owning Feature | File |
|---|---|---|---|
| Photo | Mobile local | [FEAT-001](../../harness/features/FEAT-001-capture-a-photo-on-mobile.md), [FEAT-002](../../harness/features/FEAT-002-manage-a-local-photo-gallery.md) | [`entities/photo.md`](entities/photo.md) |
| Pose | Canonical pose (mobile local + server) | [FEAT-005](../../harness/features/FEAT-005-manage-a-pose-guide.md) | [`entities/pose.md`](entities/pose.md) |
| PoseGuide (deprecated alias) | — | [FEAT-005](../../harness/features/FEAT-005-manage-a-pose-guide.md) | [`entities/pose-guide.md`](entities/pose-guide.md) |
| CommunityPose (DTO/view) | Public catalogue view | [FEAT-003](../../harness/features/FEAT-003-browse-and-search-published-poses.md), [FEAT-006](../../harness/features/FEAT-006-publish-a-pose.md) | [`entities/community-pose.md`](entities/community-pose.md) |
| PersonalPose (deprecated) | — | [FEAT-002](../../harness/features/FEAT-002-manage-a-local-photo-gallery.md) | [`entities/personal-pose.md`](entities/personal-pose.md) |
| MediaAsset | Server media | [FEAT-005](../../harness/features/FEAT-005-manage-a-pose-guide.md), [FEAT-006](../../harness/features/FEAT-006-publish-a-pose.md) | [`entities/media-asset.md`](entities/media-asset.md) |
| ExtractionJob | Server job | [FEAT-004](../../harness/features/FEAT-004-extract-reusable-pose-images.md), [FEAT-005](../../harness/features/FEAT-005-manage-a-pose-guide.md) | [`entities/extraction-job.md`](entities/extraction-job.md) |
| Account | Server identity | [FEAT-006](../../harness/features/FEAT-006-publish-a-pose.md), [FEAT-008](../../harness/features/FEAT-008-use-published-poses.md) | [`entities/account.md`](entities/account.md) |
| SavedEntry | Server collection | [FEAT-008](../../harness/features/FEAT-008-use-published-poses.md) | [`entities/saved-entry.md`](entities/saved-entry.md) |
| ApiKeyCredential | Server ops | [FEAT-004](../../harness/features/FEAT-004-extract-reusable-pose-images.md), [FEAT-007](../../harness/features/FEAT-007-operate-pose-content-from-admin-web.md) | [`entities/api-key-credential.md`](entities/api-key-credential.md) |
| ProviderRequestLog | Server ops | [FEAT-004](../../harness/features/FEAT-004-extract-reusable-pose-images.md) | [`entities/provider-request-log.md`](entities/provider-request-log.md) |
| PoseReferenceKey (deprecated) | Mobile conceptual | [FEAT-008](../../harness/features/FEAT-008-use-published-poses.md) | [`entities/pose-reference-key.md`](entities/pose-reference-key.md) |
| PreparedPoseReference | Mobile conceptual | [FEAT-008](../../harness/features/FEAT-008-use-published-poses.md) | [`entities/prepared-pose-reference.md`](entities/prepared-pose-reference.md) |

## Quy tắc đọc

- **Semantics thực thể** → `entities/*.md`
- **Relationships** → `erd/`
- **Business rules** → section "Business Rules" trong entity file tương ứng
- **API contract** → [`openapi.yaml`](../api/openapi.yaml) và [`modules/`](../api/modules/)
- **Lịch sử** → `CHANGELOG.md`
