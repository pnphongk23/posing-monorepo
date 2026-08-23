# PersonalPose (deprecated — folded into Pose)

## Description

> **Deprecated as entity.** `PersonalPose` không còn là entity domain riêng trong
> canonical model. Khái niệm pose cá nhân được hợp nhất vào [`Pose`](pose.md)
> với một `poseId` (UUID) ổn định. Không tạo entity `PersonalPose` song song.
> Transition ghi nhận tại glossary
> [`pose-domain-glossary.md`](../../../harness/specs/pose-domain-glossary.md).

Trước đây dùng trong gallery ([FEAT-002](../../../harness/features/FEAT-002-manage-a-local-photo-gallery.md))
và khi mobile persist kết quả extraction ([FEAT-004](../../../harness/features/FEAT-004-extract-reusable-pose-images.md)).
Nay pose local dùng `Pose` với `status = local`.

## Migration

| `PersonalPose` cũ | `Pose` mới |
|---|---|
| `id` (INTEGER local) | `poseId` (UUID) |
| `imagePath` (local render) | `skeletonMediaId` → `MediaAsset` role `skeleton` |
| `thumbnailPath` | `thumbnailMediaId` |
| `originalImagePath` | `originalMediaId` |
| `isMine` / `likes` | Không phải canonical domain; loại bỏ khỏi canonical model |

## Business Rules

| ID | Rule |
|---|---|
| BR-PERSONAL-001 | Canonical model không tạo `PersonalPose` tách biệt; dùng `Pose` (`status = local`). |
| BR-PERSONAL-002 | `Photo.poseId` trỏ canonical `Pose.poseId` (UUID), không trỏ integer local. |
| BR-PERSONAL-003 | Persist kết quả FEAT-004 trên mobile tạo `Pose` local; không publish hộ. |

## Relationships

- Entity canonical: [`pose.md`](pose.md)
- Glossary: [`pose-domain-glossary.md`](../../../harness/specs/pose-domain-glossary.md)