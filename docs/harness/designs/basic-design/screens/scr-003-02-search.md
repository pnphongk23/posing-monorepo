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

### Basic design direction

Màn hình chỉ có một việc chính: **tìm và mở một pose phù hợp nhanh nhất**.

- Trạng thái ban đầu chỉ hiển thị search field và recent searches.
- Results và source filter chỉ xuất hiện sau khi user có query hoặc chọn một source.
- Không thêm intro copy, source cards, suggested titles hoặc nội dung browse phụ vào blank state.
- Dùng progressive disclosure: thành phần nào không giúp hoàn thành lượt tìm hiện tại thì không chiếm chỗ trên màn hình.

Visual reference triển khai trong [Search prototype](../../../prototype/screens/search.html); rationale/research nằm ở [search-design-notes.md](../../../prototype/search-design-notes.md). Prototype là **Observed visual exploration**, không thay thế Harness Feature hay API contract.

## 3. Scope and ownership

**Published-leg:** Search published catalogue và mở published detail thuộc ownership FEAT-003.

**Out-of-slice (Observed / shared):** Local results qua `PoseRepository` filter — context [FEAT-002](../../../features/FEAT-002-manage-a-local-photo-gallery.md); không phải acceptance FEAT-003. Source filter `My poses` / `Community` là proposed presentation cho mixed result surface; ownership và API semantics của filter này **Unresolved**.

## 4. Data contract and evidence

- **Data in (published leg):** `query` string → `CommunitySearchRepository` — **Normative** (`q` evidence **Unresolved**).
- **Data in (shared/local leg):** `query` string → local `PoseRepository` title filter — **Observed / Out-of-slice**, context [FEAT-002](../../../features/FEAT-002-manage-a-local-photo-gallery.md).
- **Data out (published leg):** `poseId` → `PosePreview` → `PoseDetailVoyagerScreen` — **Normative**.
- **Recent searches:** local client-side history used by the prototype — **Observed / Proposed**, not a FEAT-003 persistence contract.
- **Presentation state:** query, result source, loading, empty, error, offline/freshness note — **Observed / Proposed**; API success/error semantics remain governed by FEAT-003 and `../apis.md`.

## 5. Screen items

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-003-02-NAV-001 | Back | Icon button | Req | Tap → `navigator.pop()`; trở về SCR-003-01; giữ platform Back/edge-swipe behavior — **Normative navigation intent / Observed implementation** |
| 2 | SCR-003-02-NAV-002 | Title | Text | Req | Hiển thị `"Search"`; typography `NavigationTitle` — **Observed prototype** |
| 3 | SCR-003-02-INP-001 | Search field | `OutlinedTextField` | Req | Nhận `query`; auto-focus; placeholder `"Search poses"`; search icon; `testTag=search-field`; target tối thiểu 44dp — **Observed prototype / Proposed copy** |
| 4 | SCR-003-02-INP-002 | Clear query | Icon button | Opt | Chỉ show khi `query` non-empty; tap → `query=""`; focus lại field; target 44dp — **Observed prototype** |
| 5 | SCR-003-02-HIS-001 | Recent searches | Horizontal chip row | Opt | Chỉ show khi query rỗng; tap chip → điền query và chạy search; không tạo thêm browse taxonomy — **Proposed / Observed prototype** |
| 6 | SCR-003-02-RES-001 | Results heading | Heading + kicker | Req | Chỉ show sau query/source intent; hiển thị query hiện tại; không show result chrome trong blank state — **Proposed visual hierarchy** |
| 7 | SCR-003-02-RES-002 | Results count | Caption | Req | Hiển thị count khi có confirmed results; loading/error dùng status copy tương ứng; `testTag=search-results-count` — **Normative result concept / Observed implementation** |
| 8 | SCR-003-02-RES-003 | Source filter | Segmented chip row | Opt | Chỉ show trong result state; `All poses` / `My poses` / `Community`; selected state rõ ràng; source semantics **Unresolved** — **Proposed prototype** |
| 9 | SCR-003-02-RES-004 | Mixed results grid | 2-col staggered grid | Req | Scroll → `SearchItem[]`; render only after query/source intent; stable `poseId`; long content không che bottom dock — **Observed implementation / Proposed initial-state change** |
| 10 | SCR-003-02-RES-005 | Published result card | Card | Req | Tap → `onPublishedPoseClick`; map `CommunityPose` → `PosePreview`; **FEAT-003 owned** |
| 11 | SCR-003-02-RES-006 | Local result card | Card | Opt | Tap → `onLocalPoseClick`; **Out-of-slice / FEAT-002**; không dùng local item làm published catalogue evidence |
| 12 | SCR-003-02-RES-007 | Load more (published) | Infinite scroll | Opt | Chạm bottom → `page+1` search; dedupe `poseId`; published leg only — **Normative pagination intent / Observed implementation** |
| 13 | SCR-003-02-ST-001 | Loading | Inline status / indicator | — | Không thay toàn màn hình bằng spinner; giữ query và context; không show unconfirmed content — **Normative E1 principle / Proposed presentation** |
| 14 | SCR-003-02-ST-002 | Search error | Inline banner + Retry | — | Tap Retry → re-run search; Flow **E1**; preserve confirmed results — **Normative / Observed retry** |
| 15 | SCR-003-02-ST-003 | Empty search | Message + recovery action | — | API `200` + `data: []`; giải thích không có match; Clear/try different title → reset query; Flow **A1** — **Normative empty behavior / Proposed copy** |
| 16 | SCR-003-02-ST-004 | Offline / stale results | Freshness note | — | Nếu có confirmed list thì giữ list và báo freshness; nếu không có list thì dùng error recovery; không fabricate published content — **Proposed presentation; E1 contract applies** |
| 17 | SCR-003-02-ST-005 | Load-more error | Inline + Retry | — | Tap Retry → re-load-more; không xoá các result đã xác nhận — **Observed retry / Normative preservation principle** |

### Motion and animation

Motion của Search phục vụ **feedback**, **state change** và **continuity**. Đây là màn hình có thao tác lặp lại nhiều (typing, clear, filter), nên cường độ motion phải thấp và không được làm chậm việc tìm pose.

| Trigger | Motion | Purpose | Rule |
| --- | --- | --- | --- |
| Push vào Search | Dùng transition mặc định của platform; keyboard xuất hiện theo system | Continuity | Không thêm custom entrance hoặc scale toàn màn hình — **Normative platform behavior / Proposed** |
| Focus search field | Cursor/focus ring theo platform; giữ layout ổn định | Feedback | Không phóng to field hoặc đẩy content khi keyboard mở — **Proposed** |
| Typing / query change | Results cập nhật ổn định; nếu cần thay state dùng opacity cross-fade nhẹ `--nb-transition-fast` → `--nb-transition-normal` | State change | Không stagger từng card, không animate layout theo từng keystroke, không full-screen spinner — **Proposed** |
| Clear query | Clear icon biến mất nhẹ; field và discovery/results đổi state nhanh | Feedback + state change | Có thể dùng `--nb-transition-fast`; không giữ loading giả sau khi clear — **Observed token / Proposed** |
| Tap recent search / source filter | Press feedback ngắn; selected state đổi trực tiếp | Feedback | Không bounce, ripple kéo dài hoặc chuyển màn hình phụ — **Proposed** |
| Tap result card | Native press feedback → platform push sang detail | Feedback + continuity | Không zoom card, parallax hoặc delay trước navigation — **Normative navigation intent / Proposed** |
| Loading / retry / error | Inline indicator hoặc message xuất hiện tại vùng result | State change | Không dùng animation lặp để thu hút chú ý; retry không shake banner — **Normative state principle / Proposed** |
| Scroll / Back / keyboard | Hành vi mặc định của platform | Continuity | Không override bằng custom physics hoặc scroll-linked effect — **Normative platform behavior** |

**Reduced Motion:** khi user bật Reduce Motion, bỏ cross-fade/press transform tùy biến; cập nhật state tức thì, giữ nguyên feedback bằng màu/label/icon và vẫn dùng system navigation. Không dùng animation làm nguồn thông tin duy nhất.

**Performance guardrail:** giữ stable keys cho result cards, không render stagger animation cho grid, không animate per-frame layout. Nếu typing hoặc results transition bị chậm, đo typing latency/render cost trước khi thêm optimization — **Unresolved until measured**.

## 6. Screen flow and feature links

| Transition | Target |
| --- | --- |
| Tap SCR-003-02-NAV-001 | [SCR-003-01 Community Browse](./scr-003-01-community-browse.md#scr-003-01-community-browse-poseslistscreen-posesscreen) |
| Tap SCR-003-02-RES-005 | [SCR-003-03 Pose Detail](./scr-003-03-pose-detail.md#scr-003-03-pose-detail-posedetailscreen) |

**Interaction sequence:**

1. Open Search → focus field; blank state shows only Search + Recent searches.
2. Type or select a recent query → replace discovery with result header, count, optional source filter, and result grid.
3. Clear → remove query and return to discovery; do not add another panel or marketing message.
4. Open a card → push detail; Back returns to Search with query/source context preserved where supported.

**FEAT-003 flow links:**

- Main flow (search path): [[FEAT-003-browse-and-search-published-poses#main-flow|FEAT-003 Main flow]] · [FEAT-003 Main flow](../../../features/FEAT-003-browse-and-search-published-poses.md#main-flow)
- Alternative A1 — Empty result: [[FEAT-003-browse-and-search-published-poses#alternative-flows|FEAT-003 Alternative A1 — Empty result]] · [FEAT-003 Alternative flows](../../../features/FEAT-003-browse-and-search-published-poses.md#alternative-flows) (SCR-003-02-ST-003)
- Exception E1 — Catalogue unavailable: [[FEAT-003-browse-and-search-published-poses#exception-flows|FEAT-003 Exception E1 — Catalogue unavailable]] · [FEAT-003 Exception flows](../../../features/FEAT-003-browse-and-search-published-poses.md#exception-flows) (SCR-003-02-ST-002/004)

## 7. Traceability and unresolved items

| Item | API | Model / ghi chú |
| --- | --- | --- |
| SCR-003-02-RES-003, RES-005 | `GET /api/community/poses?q=...` | `CommunityPose`; `q` **Unresolved** E2E |
| SCR-003-02-RES-003 | — | `PosePreview` → SCR-003-03 |

### Unresolved design/implementation gaps

- **Initial blank state:** current `SearchViewModel` requests `search("")` and can render local/published results before a query (**Observed code**); this basic design intentionally defers results until query/source intent (**Proposed visual behavior**).
- **Mixed-source filter:** `All poses` / `My poses` / `Community` exists in the prototype, but filter semantics and API ownership are not defined by FEAT-003 (**Unresolved**).
- **Recent-search persistence:** prototype fixture only; retention, deletion, privacy, and cross-device sync are unspecified (**Unresolved**).
- **Query contract:** API/OpenAPI defines `q`, but FEAT-003 E2E evidence and mobile live-vs-mock wiring remain **Unresolved** — see [../apis.md](../apis.md#unresolved).

HTTP contract: [../apis.md](../apis.md#unresolved). Model: [../models.md](../models.md). Tổng flow: [./README.md](./README.md#overall-screen-flow).
