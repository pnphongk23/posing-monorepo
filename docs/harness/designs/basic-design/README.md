# Basic Design — Screens, APIs, Models

<a id="basic-design-top"></a>

## 1. Purpose

<a id="purpose"></a>
**Basic Design** document hoá presentation và contract layers cho product surfaces đã có evidence, theo ba lớp **Screens + APIs + Models**, bám Harness Feature và `docs/spec` làm source-of-truth.

| Layer | File | Vai trò |
| --- | --- | --- |
| Screens | [screens/README.md](./screens/README.md) | Inventory 11 screen files (mobile shell / mobile / admin / legacy); flow, ownership, shared occurrences |
| APIs | [apis.md](./apis.md) | **20 Normative operations** trong 6 modules + [proxy convention](./apis.md#api-proxy-01) và [Observed register](./apis.md#api-admin-community-obs-01) — link spec/OpenAPI, không duplicate |
| Models | [models.md](./models.md) | **8 entity** + `PosePreview` + [enum register](./models.md#models-enum-register) / [ERD summary](./models.md#models-erd-summary) — link `docs/spec/data`, không duplicate |

**Không** thay thế Harness Feature hay `docs/spec` — chỉ map flow → screen → API → model với nhãn evidence.

## 2. Evidence labeling

<a id="evidence-labeling"></a>
| Label | Nguồn | Cách dùng trong slice |
| --- | --- | --- |
| **Normative** | Harness Feature + `docs/spec` | Contract hành vi/dữ liệu/API — không suy từ code |
| **Observed** | Code/read-only delivery evidence | Ghi nhận implementation hiện tại; không thay SoT |
| **Unresolved** | Conflict hoặc chưa chứng minh E2E | `q`/search, lifecycle, limit override, filter UI, production readiness |

Áp dụng nhãn cho: query `q`, local/shared paths, `limit` override khi `q`, lifecycle FEAT-003, paywall/provider discrepancies — xem [screens/README.md §4](./screens/README.md#discrepancy-register).

## 3. Screens scope

<a id="screens-scope"></a>
**11 screen files** (không gồm `TEMPLATE.md`):

| Area | Count | Screen IDs | Inventory |
| --- | --- | --- | --- |
| Mobile app-entry shell | 1 | SCR-000-01 | [Home](./screens/scr-000-01-home.md#scr-000-01-home-posestab-poseslistscreen-posesscreen) |
| Mobile | 4 | SCR-001-01, SCR-002-01, SCR-004-01, SCR-005-01 | [screens/README §1.1](./screens/README.md#inventory-mobile) |
| Admin Web | 3 | SCR-007-01, SCR-007-02, SCR-007-03 | [screens/README §1.2](./screens/README.md#inventory-admin) |
| Legacy root (FEAT-003) | 3 | SCR-003-01, SCR-003-02, SCR-003-03 | [screens/README §1.3](./screens/README.md#inventory-legacy) |

Feature-to-screen map đầy đủ FEAT-001 … FEAT-014: [screens/README.md §2](./screens/README.md#feature-mapping).

**Paywall (PLAN_FINAL):** Chỉ [SCR-001-01 Camera OVR](./screens/mobile/scr-001-01-camera.md#scr-001-01-camera-ovr-paywall) là canonical PaywallScreen host/item (`SCR-001-01-OVR-001` … `OVR-008`). [SCR-002-01](./screens/mobile/scr-002-01-gallery.md) và [SCR-003-03](./screens/scr-003-03-pose-detail.md) chỉ ghi occurrence + cross-ref Camera OVR — không canonical, không invent Paywall item.

**FEAT-009:** Shared/ambiguous evidence trên [SCR-007-03 Keys](./screens/admin/scr-007-03-keys.md#scr-007-03-admin-keys-main) (Extract Engine panel, FEAT-007 primary host). Semantics **Unresolved** — xem [screens/README.md D-009](./screens/README.md#discrepancy-register).

## 4. How to read

<a id="how-to-read"></a>
1. **[screens/README.md](./screens/README.md)** — Inventory, status authority, discrepancies, shared-occurrence register, overall Mermaid flow.
2. **[apis.md](./apis.md)** — **20 Normative operations** (6 modules: community, extract-pose, guides, publish, saved, admin-community) + proxy/observed register; map business flow → HTTP contract (link spec, không duplicate).
3. **[models.md](./models.md)** — **8 entity** + auxiliary `PosePreview`; enum register và ERD summary (link `docs/spec/data`, không duplicate).

Đọc theo thứ tự trên khi trace **flow → screen → API → model → source-of-truth**.

Per-screen detail: [TEMPLATE.md](./screens/TEMPLATE.md) + file screen tương ứng trong inventory.

## 5. Rationale — layered structure

<a id="rationale"></a>
Bốn concern tách file để reviewer đọc nhanh: landing (`README`), presentation (`screens/`), contract (`apis`), data projection (`models`). Không lồng spec entity hay OpenAPI schema — chỉ tóm tắt + link canonical.

Legacy root `scr-003-*` giữ template v1 (FEAT-003 sample slice); mobile/admin dùng template v2. Tách area folder (`mobile/`, `admin/`) phản ánh delivery surface, không đổi HTTP/model contract.

Pattern tham khảo (design slice khác): [FEAT-013 saved poses design](../feat-013-saved-poses/README.md).

## 6. Mapping — FEAT-003 flows → screens → APIs → model

<a id="mapping-feat-003"></a>
| Flow ID | Mô tả | Screen(s) | API | Model |
| --- | --- | --- | --- | --- |
| Main 1 | Mở catalogue, request published list | [SCR-003-01](./screens/scr-003-01-community-browse.md#scr-003-01-community-browse-poseslistscreen-posesscreen) | `GET /api/community/poses` (**Normative**) | `CommunityPose` (list item) |
| Main 2 | Page, refresh, search; filter `difficulty`/`tag` (API **Normative**); không trùng `poseId` active | SCR-003-01, [SCR-003-02](./screens/scr-003-02-search.md#scr-003-02-search-searchscreen) | `GET /api/community/poses` (+ `q` khi search — **Unresolved**, xem [apis.md](./apis.md#unresolved)) | `CommunityPose` |
| Main 3 | Mở published card → detail + metadata | [SCR-003-03](./screens/scr-003-03-pose-detail.md#scr-003-03-pose-detail-posedetailscreen) | `GET /api/community/poses/:id` | `CommunityPose` |
| A1 | Empty result | SCR-003-01, SCR-003-02 | `GET /api/community/poses` → HTTP `200`, `data: []` | `CommunityPose` (empty); screen empty state |
| A2 | Refresh | SCR-003-01 | `GET /api/community/poses` | `CommunityPose` |
| E1 | Catalogue unavailable | SCR-003-01, SCR-003-02 | Lỗi transport/5xx | Giữ list đã xác nhận |
| E2 | Detail unavailable | SCR-003-03 | `404 NOT_FOUND` | Giải thích NotFound/Error; **return to list**; cấm stale detail |

**Main 2 ghi chú:** Pagination và refresh thuộc published catalogue (**Normative**). Query `q` được khai báo trong [`api-contract.md`](../../specs/api-contract.md) / OpenAPI (**Normative** contract), nhưng evidence status **Unresolved** — FEAT-003 Current evidence vẫn mock-backed; mobile live vs mock tension — xem [apis.md](./apis.md#unresolved). Filter `difficulty` / `tag`: API hỗ trợ (**Normative**); mobile filter UI **Unresolved** / chưa proven — không mô tả UI filter trong slice.

Feature authority: [FEAT-003](../../features/FEAT-003-browse-and-search-published-poses.md).

**Cross-feature screen hosts (summary):**

| Feature | Dedicated screen | Ghi chú |
| --- | --- | --- |
| App shell / Home | [SCR-000-01](./screens/scr-000-01-home.md#scr-000-01-home-posestab-poseslistscreen-posesscreen) | Root host for `PosesTab`; no separate Home Feature owner; FEAT-003 supplies Community content |
| FEAT-001 | [SCR-001-01](./screens/mobile/scr-001-01-camera.md#scr-001-01-camera-camerascreen) | Paywall OVR canonical |
| FEAT-002 | [SCR-002-01](./screens/mobile/scr-002-01-gallery.md#scr-002-01-gallery-galleryscreen) | |
| FEAT-003 | SCR-003-01/02/03 | Published-leg — [screens/README §6](./screens/README.md#ownership-boundary-feat-003) |
| FEAT-004 | [SCR-004-01](./screens/mobile/scr-004-01-add-pose.md#scr-004-01-add-pose) | Add Pose form + processing sub-surface |
| FEAT-005 | [SCR-004-01](./screens/mobile/scr-004-01-add-pose.md#scr-004-01-add-pose), [SCR-005-01](./screens/mobile/scr-005-01-jobs.md#scr-005-01-jobs) | Add Pose metadata + Jobs screen |
| FEAT-007 | SCR-007-01/02/03 | |
| FEAT-006/008/010/011/012/013/014 | No dedicated screen | Chi tiết: [screens/README §2](./screens/README.md#feature-mapping) |

## 7. Source-of-truth and evidence rules

<a id="source-of-truth"></a>
| Layer | Canonical source | Vai trò của slice này |
| --- | --- | --- |
| Behavior | Harness Feature | Map flow ID → screen/API |
| Data | [`docs/harness/specs/data-contract.md`](../../specs/data-contract.md) | Link entity/enum/ERD |
| HTTP | [`docs/harness/specs/api-contract.md`](../../specs/api-contract.md) | Link module + OpenAPI |
| Visual language | [UI/UX System](../../specs/ui-ux-system.md) | Neo-brutalism, explicit states |
| Code | `mobile/`, `web/` (**Observed** only) | Không định nghĩa behavior trong design doc |

**Prototype** (`docs/prototype/`) là tham chiếu visual thăm dò, **không** là behavior source.

## 8. Unresolved (landing-level)

<a id="unresolved-landing"></a>

- **Status authority:** Harness inventory vs feature frontmatter — FEAT-002/003/004/005/007 discrepancies; FEAT-010/011/012 **missing** Harness README rows dù frontmatter `approved` — [screens/README §3](./screens/README.md#status-authority-table).
- FEAT-003 lifecycle: inventory **Proposed** vs feature frontmatter **approved**.
- Title search `q`: spec/OpenAPI **Normative** vs FEAT-003 Current evidence mock-backed; mobile `LiveCommunitySearchRepository` vs `MockCommunitySearchRepository` — xem [apis.md](./apis.md#unresolved).
- Filter `difficulty` / `tag`: API **Normative**; mobile filter UI chưa chứng minh.
- `limit` khi `q`: **Observed** server override — không phải OpenAPI contract; xem [apis.md](./apis.md#unresolved).
- Production community exposure và asset readiness chưa proven (theo FEAT-003 evidence).
- FEAT-009 Extract Engine panel trên SCR-007-03: **Observed** UI vs feature evidence gap — semantics **Unresolved**.
- FEAT-011 paywall: roadmap vs code; Gallery/Pose Detail chỉ occurrence → Camera OVR canonical.
