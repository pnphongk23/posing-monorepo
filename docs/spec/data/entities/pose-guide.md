# PoseGuide (deprecated alias of Pose)

## Description

> **Deprecated.** `PoseGuide` là tên **cũ** của aggregate canonical [`Pose`](pose.md).
> Toàn bộ semantics, fields và business rules đã chuyển sang
> [`pose.md`](pose.md). Đối chiếu glossary:
> [`pose-domain-glossary.md`](../../../harness/specs/pose-domain-glossary.md).

Trước đây `PoseGuide` là aggregate do Pose Guide Owner quản lý: metadata, media,
lịch sử extraction, và visibility ([FEAT-005](../../../harness/features/FEAT-005-manage-a-pose-guide.md)).
Tên gọi này đã được unified thành **`Pose`**. Mọi tham chiếu về sau dùng `Pose`;
file này giữ để duy trì wikilink và ghi nhận quá trình migrate.

## Migration

| `PoseGuide` cũ | `Pose` mới |
|---|---|
| `id` | `poseId` (UUID, ổn định local → published) |
| `ownerAccountId` | `ownerAccountId` |
| `sourceAssetId` | `originalMediaId` |
| `renderAssetId` | `skeletonMediaId` |
| `thumbnailAssetId` | `thumbnailMediaId` |
| `currentJobId` | `currentJobId` |
| `status` (`draft`\|`published`) | `status` (`local`\|`published`) |

Publication không tạo entity thứ hai; catalogue công khai là view/DTO của
`Pose.status = published`.

## Relationships

- Entity canonical: [`pose.md`](pose.md)
- Glossary: [`pose-domain-glossary.md`](../../../harness/specs/pose-domain-glossary.md)