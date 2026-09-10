---
screen_id: SCR-007-03
screen_name: Admin Keys
related_feature: FEAT-007
compose: web/admin-ui/src/app/admin/keys/page.js
status: draft
template_version: 2
canonical: false
---

# SCR-007-03 — Admin Keys

<a id="scr-007-03-admin-keys"></a>

## 1. Screen identity

| Field | Value |
| --- | --- |
| Screen ID | SCR-007-03 |
| Screen name | Admin Keys |
| Related feature | FEAT-007 (primary); FEAT-009 (Extract Engine panel — mapping **Unresolved**) |
| Compose / Voyager | `web/admin-ui/src/app/admin/keys/page.js` |
| Stable anchor | `scr-007-03-admin-keys` |
| Template version | `2` |

## 2. Purpose

Cho Admin operator quản lý Gemini API keys (CRUD, status, reset counters) và — trên cùng screen — chọn/lưu global extract engine qua native select (UI **Observed**; contract FEAT-009/DEC-001 **Unresolved**).

## 3. Scope and ownership

Thuộc **FEAT-007** key operations (`/api/admin/keys`). Panel **Extract Engine** gọi `GET/PUT /api/admin/settings/extraction-provider` — **Observed** trong code; FEAT-009 `Current evidence` ghi "no extraction-provider settings exist today" — **Unresolved** status discrepancy. Không tách file provider-settings riêng.

## 4. Data contract and evidence

- **Data in (keys):** `GET /api/admin/keys` → `payload.data` — **Observed**.
- **Data out (keys):** `POST /api/admin/keys` (`name`, `apiKey`); `PATCH /api/admin/keys/:id` (`status`); `DELETE /api/admin/keys/:id`; `POST /api/admin/keys/reset` — **Observed**.
- **Data in/out (provider):** `GET /api/admin/settings/extraction-provider` → `data.provider`; `PUT` body `{ provider }` — **Observed** UI; mapping normative FEAT-009 + DEC-001 — **Unresolved**.
- **Provider options:** `gemini_native`, `higgsfield_cli` — **Observed**.
- **Key status options:** `active`, `disabled`, `exhausted` — **Observed**.

**Evidence labels:**

| Label | Áp dụng |
| --- | --- |
| **Normative** | FEAT-007 key proxy contracts; FEAT-009 FR-001–005 khi đã chứng minh E2E |
| **Observed** | Toàn bộ layout, forms, lists, provider panel từ `keys/page.js` |
| **Unresolved** | FEAT-009 evidence vs observed provider API/UI; DEC-001 B1/C1/D2 chưa proven E2E từ screen doc |

## 5. Screen items (main surface)

<a id="scr-007-03-admin-keys-main"></a>

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-007-03-HDR-001 | Back | Icon button (`NavButton`) | Req | `router.back()` — **Observed** |
| 2 | SCR-007-03-HDR-002 | Screen title | Text (`h1`) | Req | `"ADMIN KEYS"` uppercase — **Observed** |
| 3 | SCR-007-03-HDR-003 | Refresh keys | Icon button | Opt | `fetchKeys()`; icon `RefreshCcw` — **Observed** |
| 4 | SCR-007-03-ENG-001 | Extract Engine title | Text + icon | Req | `"Extract Engine"` + `Cpu` — **Observed** |
| 5 | SCR-007-03-ENG-002 | Refresh provider | Icon button | Opt | `fetchProvider()` — **Observed** |
| 6 | SCR-007-03-ENG-003 | Engine description | Text | Req | Copy về engine áp dụng cho job claim sau khi lưu — **Observed** |
| 7 | SCR-007-03-ENG-004 | Provider loading | Text | — | `"LOADING ENGINE..."` khi `providerLoading` — **Observed** |
| 8 | SCR-007-03-ENG-005 | Provider select | Native `<select>` | Req | Options Gemini Native / Higgsfield CLI; state `provider` — **Observed**; FEAT-009 normative mapping — **Unresolved** |
| 9 | SCR-007-03-ENG-006 | Save Extract Engine | Action button | Req | `SAVE EXTRACT ENGINE` / `SAVING...`; `PUT` provider; notice `"Đã lưu extract engine. Áp dụng cho job được claim sau khi lưu."` — **Observed** |
| 10 | SCR-007-03-ENG-007 | Provider error | Inline alert | — | `providerError` — **Observed** |
| 11 | SCR-007-03-ENG-008 | Provider notice | Inline notice | — | `providerNotice` — **Observed** |
| 12 | SCR-007-03-STS-001 | Server Status title | Text + icon | Req | `"Server Status"` + `Shield` — **Observed** |
| 13 | SCR-007-03-STS-002 | Active count | Text | Req | `Active: {activeCount}/{keys.length}` — **Observed** |
| 14 | SCR-007-03-STS-003 | Dev-only note | Text | Opt | Secret giữ ở Next.js API proxy — **Observed** |
| 15 | SCR-007-03-ADD-001 | Add Key title | Text | Req | `"Add Key"` — **Observed** |
| 16 | SCR-007-03-ADD-002 | Key name | Text input | Req | Placeholder `"Key name"` — **Observed** |
| 17 | SCR-007-03-ADD-003 | API Key | Textarea | Req | Placeholder `"AIza..."`; mono font — **Observed** |
| 18 | SCR-007-03-ADD-004 | Add API Key | Action button | Req | Validate name + apiKey trim; `POST`; notice `"Đã thêm API key."` — **Observed** |
| 19 | SCR-007-03-RST-001 | Reset daily counters | Button | Opt | `POST /api/admin/keys/reset`; notice exhausted→active — **Observed** |
| 20 | SCR-007-03-GLB-001 | Global error banner | Inline alert | — | Shared `error` state — **Observed** |
| 21 | SCR-007-03-GLB-002 | Global notice banner | Inline notice | — | Shared `notice` state — **Observed** |
| 22 | SCR-007-03-LST-001 | Keys loading | Text | — | `"LOADING..."` — **Observed** |
| 23 | SCR-007-03-LST-002 | Keys empty | Text | — | `"NO API KEYS YET"` — **Observed** |
| 24 | SCR-007-03-LST-003 | Key card | Card | Req | Per-key: `name`, `id`, delete, `requestsToday`, status select — **Observed** |
| 25 | SCR-007-03-LST-004 | Delete key | Icon button | Req | `DELETE /api/admin/keys/:id`; **không** `window.confirm` — **Observed** |
| 26 | SCR-007-03-LST-005 | Key status select | Native `<select>` | Req | `active`/`disabled`/`exhausted`; `PATCH` on change — **Observed** |

## 6. Screen flow and feature links

| Transition | Target |
| --- | --- |
| Tap SCR-007-03-HDR-001 | Back (history) — thường [SCR-007-01 Dashboard](./scr-007-01-dashboard.md#scr-007-01-admin-dashboard-main) |

**FEAT-007 flow links:**

- Main flow: [[FEAT-007-operate-pose-content-from-admin-web#main-flow|FEAT-007 Main flow]] · [FEAT-007 Main flow](../../../../features/FEAT-007-operate-pose-content-from-admin-web.md#main-flow)
- Alternative A1 — Refresh: [[FEAT-007-operate-pose-content-from-admin-web#alternative-flows|FEAT-007 Alternative A1 — Refresh]] · [FEAT-007 Alternative flows](../../../../features/FEAT-007-operate-pose-content-from-admin-web.md#alternative-flows) (SCR-007-03-HDR-003)
- Exception E1 — Missing/invalid admin configuration: [[FEAT-007-operate-pose-content-from-admin-web#exception-flows|FEAT-007 Exception E1]] · [FEAT-007 Exception flows](../../../../features/FEAT-007-operate-pose-content-from-admin-web.md#exception-flows)
- Exception E2 — Upstream rejection: [[FEAT-007-operate-pose-content-from-admin-web#exception-flows|FEAT-007 Exception E2]] · [FEAT-007 Exception flows](../../../../features/FEAT-007-operate-pose-content-from-admin-web.md#exception-flows)

**FEAT-009 flow links** (Extract Engine panel — mapping **Unresolved**):

- Main flow: [[FEAT-009-configure-extraction-provider#main-flow|FEAT-009 Main flow]] · [FEAT-009 Main flow](../../../../features/FEAT-009-configure-extraction-provider.md#main-flow)
- Alternative A1 — Refresh: [[FEAT-009-configure-extraction-provider#alternative-flows|FEAT-009 Alternative A1 — Refresh]] · [FEAT-009 Alternative flows](../../../../features/FEAT-009-configure-extraction-provider.md#alternative-flows) (SCR-007-03-ENG-002)
- Exception E1 — Invalid engine: [[FEAT-009-configure-extraction-provider#exception-flows|FEAT-009 Exception E1]] · [FEAT-009 Exception flows](../../../../features/FEAT-009-configure-extraction-provider.md#exception-flows)
- Exception E2 — Proxy failure: [[FEAT-009-configure-extraction-provider#exception-flows|FEAT-009 Exception E2]] · [FEAT-009 Exception flows](../../../../features/FEAT-009-configure-extraction-provider.md#exception-flows) (SCR-007-03-ENG-007)

## 7. Traceability and unresolved items

| Item | API | Model |
| --- | --- | --- |
| SCR-007-03-LST-003–005 | `GET/POST/PATCH/DELETE /api/admin/keys`, `POST /api/admin/keys/reset` | `ApiKeyCredential` |
| SCR-007-03-ENG-005–006 | `GET/PUT /api/admin/settings/extraction-provider` | Global extraction engine setting — **Unresolved** vs FEAT-009 evidence |

HTTP contract: [../../apis.md](../../apis.md). Model: [../../models.md](../../models.md).

**Status discrepancy:**

| Topic | Feature evidence | Observed UI |
| --- | --- | --- |
| Extraction provider settings | FEAT-009 **Observed:** "no extraction-provider settings exist today" (`keys/page.js`) | Panel Extract Engine + GET/PUT provider API — **Unresolved** |
| DEC-001 policy axes B1/C1/D2 | FEAT-009 normative | UI copy nói job claim sau save; chưa proven E2E — **Unresolved** |
| FEAT-009 ownership | FEAT-007 invokes FEAT-009; không own provider config | Provider UI nằm trên Keys screen — **Observed**; cross-feature boundary documented |
