# PreparedPoseReference

## Description

Transport/state contract trên mobile, được emit khi "Try Pose" thành công. Xác nhận render asset đã sẵn sàng trước khi rời màn hình detail. Không persisted qua relaunch.

**Status:** `conceptual` — Source: `mobile/shared/src/commonMain/kotlin/com/aipose/data/PreparedPoseReference.kt`

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `key` | PoseReferenceKey | ✓ | Source-qualified identity của pose được chọn |
| `name` | String | ✓ | Display name của pose |
| `renderLocator` | String | ✓ | Verified render asset: data URI hoặc absolute local path. **Không bao giờ là remote URL.** |

## Relationships

- `key` → `PoseReferenceKey` (Personal hoặc Community)
- Được giữ trong `PoseServiceLocator`; pass sang Camera handoff

## Business Rules

| ID | Rule |
|---|---|
| BR-PREPREF-001 | `renderLocator` phải là local/data URI sau bước prepare — không được là remote URL. |
| BR-PREPREF-002 | `PreparedPoseReference` không persist qua relaunch app. |
| BR-PREPREF-003 | Bước verify image (magic byte check) phải pass trước khi emit reference. |
