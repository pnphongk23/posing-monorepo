# PoseReferenceKey

## Description

Typed discriminated union trên mobile phân biệt personal pose (ID số nguyên) với community pose (UUID string). Là in-memory type, không persisted.

**Status:** `conceptual` — Source: `mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseReferenceKey.kt`

## Fields

Là sealed class Kotlin với hai variant:

| Field | Type | Required | Description |
|---|---|---|---|
| `Personal.id` | Long | ✓ | ID local của `PersonalPose` |
| `Community.id` | String | ✓ | UUID của `CommunityPose` trên server |

## Relationships

- `Personal(id)` → `PersonalPose.id` (mobile local)
- `Community(id)` → `CommunityPose.id` (server UUID)
- Được embed trong `PreparedPoseReference.key`

## Business Rules

| ID | Rule |
|---|---|
| BR-REF-001 | `PoseReferenceKey` không phải SQL table; không có persistence. |
| BR-REF-002 | Ngăn ID số nguyên local `PersonalPose` bị nhầm với UUID string `CommunityPose`. |
