---
screen_id: SCR-003-01
screen_name: Poses
related_feature: FEAT-003
compose: PosesListScreen (wrapper) + PosesScreen (implementation)
status: sample
template_version: 1
canonical: false
---

# SCR-003-01 — Poses (`PosesListScreen` + `PosesScreen`)

<a id="scr-003-01-community-browse-poseslistscreen-posesscreen"></a>

## 1. Screen identity

| Field | Value |
| --- | --- |
| Screen ID | SCR-003-01 |
| Screen name | Poses |
| Related feature | FEAT-003 |
| Compose / Voyager | `PosesListScreen` (wrapper) + `PosesScreen` (implementation) |
| Stable anchor | `scr-003-01-community-browse-poseslistscreen-posesscreen` |

## 2. Purpose

Hiển thị catalogue community published dạng masonry grid; hỗ trợ refresh, load-more, điều hướng search và detail.

## 3. Scope and ownership

Thuộc **published-leg** FEAT-003: browse catalogue qua `GET /api/community/poses`. Đây là một collection Poses duy nhất trong app hiện tại; chưa expose My Poses hoặc Create Pose trên surface này.

## 4. Data contract and evidence

- **Data in:** `CommunityPose[]` từ `GET /api/community/poses` (qua `PosesLibraryCoordinator`) — **Normative**.
- **Data out:** `poseId` → `PosePreview` khi user chọn card → push detail — **Normative**.

## 5. Screen items

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-003-01-WRAP-001 | `PosesListScreen` shell | Voyager `Screen` + `Box` | Req | Khi Tab Poses active → compose `PosesScreen` + `MainDock`; wrapper duy nhất gắn bottom dock |
| 2 | SCR-003-01-HDR-001 | Screen title | Text | Req | Hiển thị label `"Poses"`; typography `NavigationTitle` |
| 3 | SCR-003-01-HDR-002 | Search affordance | Icon button (44dp) | Opt | Tap → push `SearchScreen`; `testTag=poses-search-button`; label a11y "Search poses" |
| 4 | SCR-003-01-GRD-001 | Pose card grid | `LazyVerticalStaggeredGrid` 2 cột | Req | Scroll → render `CommunityPose`; staggered aspect ratio; thumbnail/skeleton fallback |
| 5 | SCR-003-01-GRD-002 | Pose card | `CommunityPoseCard` | Req | Tap → `PosePreview` → detail; key `poseId`; không duplicate active ID khi load-more |
| 6 | SCR-003-01-GRD-004 | Load more | Infinite scroll | Opt | Chạm cuối grid → request `page+1`; `pageSize=20`; spinner hoặc retry inline |
| 7 | SCR-003-01-GRD-005 | Pull-to-refresh | Pull gesture | Opt | Pull down → re-fetch `page=1`; Flow **A2**; khi lỗi giữ catalogue đã xác nhận |
| 8 | SCR-003-01-ST-001 | Initial loading | `CircularProgressIndicator` | — | Khi `items` rỗng và đang load |
| 9 | SCR-003-01-ST-002 | Initial error | State message + Retry | — | Tap Retry → re-load initial; Flow **E1**; không fabricate published content |
| 10 | SCR-003-01-ST-003 | Empty catalogue | Text | — | Hiển thị `"No poses found."`; Flow **A1**; API `200` + `data: []` |
| 11 | SCR-003-01-ST-004 | Refresh error banner | Banner + Retry | — | Tap Retry → re-refresh; **Observed** retry; giữ catalogue trước đó |
| 12 | SCR-003-01-ST-005 | Load-more error | Inline + Retry | — | Tap Retry → re-load-more; Flow **E1** (partial); **Observed** retry |

## 6. Screen flow and feature links

| Transition | Target |
| --- | --- |
| Tap SCR-003-01-HDR-002 | [SCR-003-02 Search](./scr-003-02-search.md#scr-003-02-search-searchscreen) |
| Tap SCR-003-01-GRD-002 | [SCR-003-03 Pose Detail](./scr-003-03-pose-detail.md#scr-003-03-pose-detail-posedetailscreen) |

**FEAT-003 flow links:**

- Main flow: [[FEAT-003-browse-and-search-published-poses#main-flow|FEAT-003 Main flow]] · [FEAT-003 Main flow](../../../features/FEAT-003-browse-and-search-published-poses.md#main-flow)
- Alternative A1 — Empty result: [[FEAT-003-browse-and-search-published-poses#alternative-flows|FEAT-003 Alternative A1 — Empty result]] · [FEAT-003 Alternative flows](../../../features/FEAT-003-browse-and-search-published-poses.md#alternative-flows) (SCR-003-01-ST-003)
- Alternative A2 — Refresh: [[FEAT-003-browse-and-search-published-poses#alternative-flows|FEAT-003 Alternative A2 — Refresh]] · [FEAT-003 Alternative flows](../../../features/FEAT-003-browse-and-search-published-poses.md#alternative-flows) (SCR-003-01-GRD-005)
- Exception E1 — Catalogue unavailable: [[FEAT-003-browse-and-search-published-poses#exception-flows|FEAT-003 Exception E1 — Catalogue unavailable]] · [FEAT-003 Exception flows](../../../features/FEAT-003-browse-and-search-published-poses.md#exception-flows) (SCR-003-01-ST-002/004/005)

## 7. Traceability and unresolved items

| Item | API | Model |
| --- | --- | --- |
| SCR-003-01-GRD-002, GRD-004, GRD-005 | `GET /api/community/poses` | `CommunityPose`, pagination envelope |
| SCR-003-01-GRD-002 | — | `PosePreview` navigation hop → SCR-003-03 |

HTTP contract: [../apis.md](../apis.md). Model: [../models.md](../models.md). Tổng flow: [./README.md](./README.md#overall-screen-flow).
