# Tài liệu Data

Đây là nguồn sự thật duy nhất cho mô hình dữ liệu của dự án ai-pose.

## Cấu trúc

| Tệp/Thư mục | Nội dung |
|---|---|
| [`domain-model.md`](domain-model.md) | Tổng quan domain, phân loại thực thể, khái niệm TBD |
| [`entities/`](entities/) | Một file per entity: fields, relationships, business rules |
| [`erd/`](erd/) | ERD dạng Mermaid: server, mobile, conceptual overlay |
| [`enums.md`](enums.md) | Shared enums với giá trị và ý nghĩa |
| [`CHANGELOG.md`](CHANGELOG.md) | Lịch sử thay đổi tài liệu data |

## Phân loại thực thể

| Entity | Layer | Status | File |
|---|---|---|---|
| Photo | Mobile local | `implemented` | [`entities/photo.md`](entities/photo.md) |
| PersonalPose | Mobile local | `implemented` | [`entities/personal-pose.md`](entities/personal-pose.md) |
| CommunityPose | Server | `implemented` | [`entities/community-pose.md`](entities/community-pose.md) |
| ExtractionJob | Server | `implemented` | [`entities/extraction-job.md`](entities/extraction-job.md) |
| ApiKeyCredential | Server | `implemented` | [`entities/api-key-credential.md`](entities/api-key-credential.md) |
| ProviderRequestLog | Server | `implemented` | [`entities/provider-request-log.md`](entities/provider-request-log.md) |
| PoseReferenceKey | Mobile conceptual | `conceptual` | [`entities/pose-reference-key.md`](entities/pose-reference-key.md) |
| PreparedPoseReference | Mobile conceptual | `conceptual` | [`entities/prepared-pose-reference.md`](entities/prepared-pose-reference.md) |
| MediaAsset | Cross-cutting | `tbd` | [`domain-model.md`](domain-model.md#thực-thể-tbd) |
| Account / SavedEntry | Server | `tbd` | [`domain-model.md`](domain-model.md#thực-thể-tbd) |
| PoseGuide | Server | `tbd` | [`domain-model.md`](domain-model.md#thực-thể-tbd) |

## Quy tắc đọc

- **Semantics thực thể** → `entities/*.md`
- **Relationships** → `erd/`
- **Business rules** → section "Business Rules" trong entity file tương ứng
- **API contract** → [`docs/api/openapi.yaml`](../api/openapi.yaml)
- **Lịch sử** → `CHANGELOG.md`
