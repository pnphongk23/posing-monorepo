# ERD

Entity relationship diagrams cho hợp đồng dữ liệu product. Entity canonical duy
nhất là [`Pose`](../entities/pose.md); catalogue công khai là view/DTO
(`status = published`). Mỗi `Pose` có đúng ba `MediaAsset` role: `original`,
`skeleton`, `thumbnail` — cả ba non-nullable, materialize tại lúc tạo pose
(**pose được tạo sau khi extraction `succeeded`**). `ownerAccountId` bắt buộc
trên mọi `Pose`.

| File | Nội dung |
|---|---|
| [`server.md`](server.md) | Server: Pose, media, job, account, saved, keys |
| [`mobile.md`](mobile.md) | Mobile local: Photo, Pose (local) |
| [`conceptual.md`](conceptual.md) | Overlay Try Pose + ranh giới mobile/server |

**Quy ước:**

- Edge liền: quan hệ product bắt buộc
- Semantics field: [`../entities/`](../entities/)

Thuật ngữ canonical: [`pose-domain-glossary.md`](../../../harness/specs/pose-domain-glossary.md).