---
screen_id: SCR-003-03
screen_name: Pose Detail
related_feature: FEAT-003
compose: PoseDetailScreen (+ PoseDetailVoyagerScreen navigation wrapper)
status: sample
template_version: 1
canonical: false
---

# SCR-003-03 — Pose Detail (`PoseDetailScreen`)

<a id="scr-003-03-pose-detail-posedetailscreen"></a>

## 1. Screen identity

| Field | Value |
| --- | --- |
| Screen ID | SCR-003-03 |
| Screen name | Pose Detail |
| Related feature | FEAT-003 |
| Compose / Voyager | `PoseDetailScreen` (+ `PoseDetailVoyagerScreen` navigation wrapper) |
| Stable anchor | `scr-003-03-pose-detail-posedetailscreen` |

## 2. Purpose

**FEAT-003 published-leg:** Hiển thị metadata và media published pose sau khi user chọn published card; enrich qua `GET /api/community/poses/:id`.

## 3. Scope and ownership

**Observed / shared:** `repository.getPoseById` local-first path — navigation optimization, không định nghĩa FEAT-003 contract. Published detail ownership bắt đầu từ `poseId` published + community detail API.

**Wrapper:** `PoseDetailVoyagerScreen` nhận `PosePreview`, tạo `PoseDetailViewModel(poseId)`, push từ list hoặc search.

Try Pose / Save là cross-ref [FEAT-008](../../../features/FEAT-008-use-published-poses.md) — **out-of-slice**.

## 4. Data contract and evidence

- **Data in:** `poseId` + `PosePreview` từ navigation (list/search card tap qua `PoseDetailVoyagerScreen`) — **Observed**; enrich qua `GET /api/community/poses/:id` → `CommunityPose` — **Normative**.
- **Data out:** Back → return to list (**Normative** E2); Try Pose → [FEAT-008](../../../features/FEAT-008-use-published-poses.md) cross-ref only — **out-of-slice**.

## 5. Screen items

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-003-03-NAV-001 | Back | Icon button | Req | Tap → `onBack` / pop → list; **Normative** E2: return to list |
| 2 | SCR-003-03-HRO-001 | Hero image | `AsyncImage` | Req | Input `poseId`, `PosePreview` → thumbnail/skeleton URL; preview-first từ navigation DTO; enrich từ `CommunityPose` |
| 3 | SCR-003-03-META-001 | Pose name | Text | Req | Hiển thị `name` |
| 4 | SCR-003-03-META-002 | Difficulty | Text | Opt | Hiển thị `difficulty`; chỉ render khi non-null |
| 5 | SCR-003-03-META-003 | Description | Text | Opt | Hiển thị `description`; từ `CommunityPose` |
| 6 | SCR-003-03-META-004 | Tags / body parts | Text / chips | Opt | Hiển thị `tags`, `bodyParts` |
| 7 | SCR-003-03-ST-001 | Loading | Scaffold + hero placeholder | — | Input `poseId` → preview hoặc loading; **Observed** local-first; published path qua API |
| 8 | SCR-003-03-ST-002 | Not found | Center message | — | Hiển thị "Pose not found"; **Normative** E2: explain unavailability; **return to list** via back |
| 9 | SCR-003-03-ST-003 | Error | Center message | — | Error explanation; **Normative** E2: explain failure; **return to list**; cấm stale detail |
| 10 | SCR-003-03-ACT-001 | Try Pose | Primary button | Opt | Tap → camera handoff; **FEAT-008** — out-of-slice |
| 11 | SCR-003-03-ACT-002 | Save | — | — | **FEAT-008** — out-of-slice |

## 6. Screen flow and feature links

| Transition | Target |
| --- | --- |
| Back SCR-003-03-NAV-001 (from browse) | [SCR-003-01 Community Browse](./scr-003-01-community-browse.md#scr-003-01-community-browse-poseslistscreen-posesscreen) |
| Back SCR-003-03-NAV-001 (from search path) | [SCR-003-02 Search](./scr-003-02-search.md#scr-003-02-search-searchscreen) |

**FEAT-003 flow links:**

- Main flow: [[FEAT-003-browse-and-search-published-poses#main-flow|FEAT-003 Main flow]] · [FEAT-003 Main flow](../../../features/FEAT-003-browse-and-search-published-poses.md#main-flow)
- Exception E2 — Detail unavailable: [[FEAT-003-browse-and-search-published-poses#exception-flows|FEAT-003 Exception E2 — Detail unavailable]] · [FEAT-003 Exception flows](../../../features/FEAT-003-browse-and-search-published-poses.md#exception-flows) (SCR-003-03-ST-002/003)

## 7. Traceability and unresolved items

| Item | API | Model |
| --- | --- | --- |
| SCR-003-03-HRO-001, META-001–004 | `GET /api/community/poses/:id` | `CommunityPose` |
| SCR-003-03-HRO-001 | — | `PosePreview` từ SCR-003-01-GRD-002 / SCR-003-02-RES-003 |

**Observed / shared (out-of-slice FEAT-003; không thêm Item ID):**

- Delete `AlertDialog` (`showDeleteDialog`) — owned by [FEAT-005](../../../features/FEAT-005-manage-a-pose-guide.md); source [`PoseDetailScreen.kt`](../../../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PoseDetailScreen.kt).
- Preparing/deleting full-screen overlay (`DetailActionState.Preparing` / `Deleting`) — preparing owned by [FEAT-008](../../../features/FEAT-008-use-published-poses.md); deleting owned by [FEAT-005](../../../features/FEAT-005-manage-a-pose-guide.md); source [`PoseDetailScreen.kt`](../../../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PoseDetailScreen.kt).
- `PaywallScreen` (`showPaywall`) — owned by [FEAT-008](../../../features/FEAT-008-use-published-poses.md) / [FEAT-011](../../../features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md); **occurrence only** → canonical OVR tại [SCR-001-01 §11 Paywall](./mobile/scr-001-01-camera.md#scr-001-01-camera-ovr-paywall) (Camera; không duplicate bảng OVR); source [`PoseDetailScreen.kt`](../../../../../mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PoseDetailScreen.kt).

HTTP contract: [../apis.md](../apis.md). Model: [../models.md](../models.md). Tổng flow: [./README.md](./README.md#overall-screen-flow).
