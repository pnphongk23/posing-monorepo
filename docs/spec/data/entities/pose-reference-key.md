# PoseReferenceKey (deprecated)

## Description

> **Deprecated.** `PoseReferenceKey` là union cũ Personal-vs-Community trên mobile
> (ID số local cho `PersonalPose`, UUID server cho `CommunityPose`). Khái niệm này
> đã **bị gỡ khỏi canonical model**; replaced bằng ID đơn giản `poseId` (UUID) và
> `mediaId` (UUID) — xem glossary
> [`pose-domain-glossary.md`](../../../harness/specs/pose-domain-glossary.md) mục 5.

Không persist. Trước đây dùng làm hợp đồng in-memory của
[FEAT-008](../../../harness/features/FEAT-008-use-published-poses.md).

## Migration

| `PoseReferenceKey` cũ | Canonical mới |
|---|---|
| `Personal.id` (Long) | `poseId` (UUID) của canonical [`Pose`](pose.md) |
| `Community.id` (String) | `poseId` (UUID) — cùng namespace, không phân biệt |
| Embed trong `PreparedPoseReference.key` | `PreparedPoseReference.poseId` + `mediaId` |

## Business Rules

| ID | Rule |
|---|---|
| BR-REF-001 | Không nằm trong canonical model; không persist. |
| BR-REF-002 | Không còn phân biệt Personal/Community key — mọi pose dùng `poseId` UUID. |
| BR-REF-003 | Use published pose không cấp quyền sở hữu pose. |

## Relationships

- Entities canonical: [`pose.md`](pose.md), [`prepared-pose-reference.md`](prepared-pose-reference.md)
- Glossary: [`pose-domain-glossary.md`](../../../harness/specs/pose-domain-glossary.md)