---
screen_id: SCR-003-02
screen_name: Search
related_feature: FEAT-003
compose: SearchScreen
status: sample
template_version: 1
canonical: false
---

# SCR-003-02 — Search (`SearchScreen`)

<a id="scr-003-02-search-searchscreen"></a>

## 1. Screen identity

| Field | Value |
| --- | --- |
| Screen ID | SCR-003-02 |
| Screen name | Search |
| Related feature | FEAT-003 |
| Compose / Voyager | `SearchScreen` |
| Stable anchor | `scr-003-02-search-searchscreen` |

## 2. Purpose

**FEAT-003 published-leg:** Tìm published pose theo title qua `GET /api/community/poses?q=...` (**Normative** contract; evidence **Unresolved** — xem [../apis.md](../apis.md#unresolved)).

## 3. Scope and ownership

**Out-of-slice (Observed / shared):** Local results qua `PoseRepository` filter — context [FEAT-002](../../../features/FEAT-002-manage-a-local-photo-gallery.md); không phải acceptance FEAT-003. Published-leg (SCR-003-02-RES-003, RES-005) thuộc ownership FEAT-003.

## 4. Data contract and evidence

- **Data in (published leg):** `query` string → `CommunitySearchRepository` — **Normative** (`q` evidence **Unresolved**).
- **Data out (published leg):** `poseId` → `PosePreview` → `PoseDetailVoyagerScreen` — **Normative**.

## 5. Screen items

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-003-02-NAV-001 | Back | Icon button | Req | Tap → `navigator.pop()`; trở về SCR-003-01 |
| 2 | SCR-003-02-NAV-002 | Title | Text | Req | Hiển thị `"Search"` |
| 3 | SCR-003-02-INP-001 | Search field | `OutlinedTextField` | Req | Nhận `query` → debounced search; placeholder "Type a title"; auto-focus; `testTag=search-field` |
| 4 | SCR-003-02-INP-002 | Clear query | Icon button | Opt | Tap → `query=""`; chỉ khi `query` non-empty |
| 5 | SCR-003-02-RES-001 | Results count | Caption | Req | Hiển thị count / Loading / Unavailable; `testTag=search-results-count` |
| 6 | SCR-003-02-RES-002 | Mixed results grid | 2-col staggered grid | Req | Scroll → `SearchItem` list; **Observed:** local trước, published sau — mixed UI không normative FEAT-003 |
| 7 | SCR-003-02-RES-003 | Published result card | Card | Req | Tap → `onPublishedPoseClick`; map `CommunityPose` → `PosePreview`; **FEAT-003 owned** |
| 8 | SCR-003-02-RES-004 | Local result card | Card | Opt | Tap → `onLocalPoseClick`; **Out-of-slice / FEAT-002**; không public catalogue contract |
| 9 | SCR-003-02-RES-005 | Load more (published) | Infinite scroll | Opt | Chạm bottom → `page+1` search; dedupe `poseId`; published leg only |
| 10 | SCR-003-02-ST-001 | Initial loading | Indicator | — | Trong lúc search đầu |
| 11 | SCR-003-02-ST-002 | Search error | Banner + Retry | — | Tap Retry → re-run search; Flow **E1**; **Observed** retry |
| 12 | SCR-003-02-ST-003 | Empty search | Title + subtitle + Clear | — | Tap Clear → reset query; Flow **A1**; API `200` + `data: []` (published leg) |
| 13 | SCR-003-02-ST-004 | Load-more error | Inline + Retry | — | Tap Retry → re-load-more; **Observed** retry |

## 6. Screen flow and feature links

| Transition | Target |
| --- | --- |
| Back SCR-003-02-NAV-001 | [SCR-003-01 Community Browse](./scr-003-01-community-browse.md#scr-003-01-community-browse-poseslistscreen-posesscreen) |
| Tap SCR-003-02-RES-003 | [SCR-003-03 Pose Detail](./scr-003-03-pose-detail.md#scr-003-03-pose-detail-posedetailscreen) |

**FEAT-003 flow links:**

- Main flow (search path): [[FEAT-003-browse-and-search-published-poses#main-flow|FEAT-003 Main flow]] · [FEAT-003 Main flow](../../../features/FEAT-003-browse-and-search-published-poses.md#main-flow)
- Alternative A1 — Empty result: [[FEAT-003-browse-and-search-published-poses#alternative-flows|FEAT-003 Alternative A1 — Empty result]] · [FEAT-003 Alternative flows](../../../features/FEAT-003-browse-and-search-published-poses.md#alternative-flows) (SCR-003-02-ST-003)
- Exception E1 — Catalogue unavailable: [[FEAT-003-browse-and-search-published-poses#exception-flows|FEAT-003 Exception E1 — Catalogue unavailable]] · [FEAT-003 Exception flows](../../../features/FEAT-003-browse-and-search-published-poses.md#exception-flows) (SCR-003-02-ST-002/004)

## 7. Traceability and unresolved items

| Item | API | Model / ghi chú |
| --- | --- | --- |
| SCR-003-02-RES-003, RES-005 | `GET /api/community/poses?q=...` | `CommunityPose`; `q` **Unresolved** E2E |
| SCR-003-02-RES-003 | — | `PosePreview` → SCR-003-03 |

HTTP contract: [../apis.md](../apis.md#unresolved). Model: [../models.md](../models.md). Tổng flow: [./README.md](./README.md#overall-screen-flow).
