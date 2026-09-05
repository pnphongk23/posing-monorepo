---
screen_id: SCR-007-01
screen_name: Admin Dashboard
related_feature: FEAT-007
compose: web/admin-ui/src/app/admin/page.js
status: draft
template_version: 2
canonical: false
---

# SCR-007-01 — Admin Dashboard

<a id="scr-007-01-admin-dashboard"></a>

## 1. Screen identity

| Field | Value |
| --- | --- |
| Screen ID | SCR-007-01 |
| Screen name | Admin Dashboard |
| Related feature | FEAT-007 |
| Compose / Voyager | `web/admin-ui/src/app/admin/page.js` |
| Stable anchor | `scr-007-01-admin-dashboard` |
| Template version | `2` |

## 2. Purpose

Hub điều hướng Admin Web: quay về app root và mở hai mục vận hành — quản lý API keys và community pose intake/listing.

## 3. Scope and ownership

Thuộc **FEAT-007** operating surface. Screen chỉ render navigation cards; không gọi API trực tiếp. Hai destination (`/admin/keys`, `/admin/community`) là **Observed** child screens trong cùng Admin slice.

## 4. Data contract and evidence

- **Data in:** Không có fetch dữ liệu trên screen này — **Observed**.
- **Data out:** Điều hướng qua Next.js `Link` tới `/admin/keys` hoặc `/admin/community`; back về `/` qua `NavButton` — **Observed**.
- **Navigation contract:** `ADMIN_SECTIONS` cố định hai entry (API Keys, Community Poses) — **Observed**.

**Evidence labels:**

| Label | Áp dụng |
| --- | --- |
| **Normative** | FEAT-007 mô tả Admin operator mở Admin page và proxy upstream khi submit action trên child screens |
| **Observed** | Layout, copy, và hai section card từ `page.js` |
| **Unresolved** | Không có trên screen hub |

## 5. Screen items (main surface)

<a id="scr-007-01-admin-dashboard-main"></a>

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-007-01-HDR-001 | Back | Icon button (`NavButton`) | Req | `href="/"`; label `"Back"`; icon `ChevronLeft` — **Observed** |
| 2 | SCR-007-01-HDR-002 | Screen title | Text (`h1`) | Req | Hiển thị `"ADMIN"`; `text-xl font-extrabold tracking-neo` — **Observed** |
| 3 | SCR-007-01-NAV-001 | API Keys card | Link + card | Req | `href="/admin/keys"`; icon `Shield`; title `"API Keys"`; description `"Manage Gemini API keys for pose extraction"`; `bg-accent-yellow` — **Observed** |
| 4 | SCR-007-01-NAV-002 | Community Poses card | Link + card | Req | `href="/admin/community"`; icon `Users`; title `"Community Poses"`; description `"Upload and manage community pose library"`; `bg-accent-green` — **Observed** |

## 6. Screen flow and feature links

| Transition | Target |
| --- | --- |
| Tap SCR-007-01-HDR-001 | App root `/` |
| Tap SCR-007-01-NAV-001 | [SCR-007-03 Keys](./scr-007-03-keys.md#scr-007-03-admin-keys-main) |
| Tap SCR-007-01-NAV-002 | [SCR-007-02 Community](./scr-007-02-community.md#scr-007-02-admin-community-poses-main) |

**FEAT-007 flow links:**

- Main flow: [[FEAT-007-operate-pose-content-from-admin-web#main-flow|FEAT-007 Main flow]] · [FEAT-007 Main flow](../../../../features/FEAT-007-operate-pose-content-from-admin-web.md#main-flow)
- Alternative A1 — Refresh: [[FEAT-007-operate-pose-content-from-admin-web#alternative-flows|FEAT-007 Alternative A1 — Refresh]] · [FEAT-007 Alternative flows](../../../../features/FEAT-007-operate-pose-content-from-admin-web.md#alternative-flows)
- Exception E1 — Missing/invalid admin configuration: [[FEAT-007-operate-pose-content-from-admin-web#exception-flows|FEAT-007 Exception E1]] · [FEAT-007 Exception flows](../../../../features/FEAT-007-operate-pose-content-from-admin-web.md#exception-flows)
- Exception E2 — Upstream rejection: [[FEAT-007-operate-pose-content-from-admin-web#exception-flows|FEAT-007 Exception E2]] · [FEAT-007 Exception flows](../../../../features/FEAT-007-operate-pose-content-from-admin-web.md#exception-flows)

## 7. Traceability and unresolved items

| Item | API | Model |
| --- | --- | --- |
| SCR-007-01-NAV-001 | — (child screen) | — |
| SCR-007-01-NAV-002 | — (child screen) | — |

HTTP contract (child screens): [../../apis.md](../../apis.md). Model: [../../models.md](../../models.md).

**Status discrepancy:** Không có item UI trên hub; discrepancy chỉ áp dụng trên child screens (xem SCR-007-02, SCR-007-03).
