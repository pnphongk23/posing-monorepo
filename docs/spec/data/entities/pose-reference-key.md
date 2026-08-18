# PoseReferenceKey

## Description

Discriminated union trên mobile phân biệt pose cá nhân (ID số) và pose cộng đồng (UUID). Hợp đồng in-memory của [FEAT-008](../../../harness/features/FEAT-008-use-published-poses.md). Không persist.

## Fields

Hai variant:

| Field | Type | Required | Description |
|---|---|---|---|
| `Personal.id` | Long | ✓ | ID local của [`PersonalPose`](personal-pose.md) |
| `Community.id` | String | ✓ | UUID của [`CommunityPose`](community-pose.md) / [`PoseGuide`](pose-guide.md) |

## Relationships

- `Personal(id)` → `PersonalPose.id`
- `Community(id)` → `CommunityPose.id`
- Embed trong [`PreparedPoseReference.key`](prepared-pose-reference.md)

## Business Rules

| ID | Rule |
|---|---|
| BR-REF-001 | Không phải bảng SQL; không persist. |
| BR-REF-002 | Không được nhầm ID số `PersonalPose` với UUID `CommunityPose`. |
| BR-REF-003 | Use published pose không đổi variant thành quyền sở hữu guide. |
