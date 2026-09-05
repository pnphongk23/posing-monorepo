---
screen_id: SCR-XXX-NN
screen_name: <Human-readable screen name>
related_feature: <FEAT-XXX>
compose: <Compose / Voyager screen path(s)>
status: <draft|sample|approved>
template_version: 2
canonical: true
---

# <screen_id> — <screen_name>

> **Canonical screen template (v2)** — `docs/harness/designs/basic-design/screens/TEMPLATE.md`. Mọi screen instance trong folder này phải dùng cùng frontmatter fields (trừ `canonical` và `template_version`), thứ tự H2 đánh số, schema bảng item, và quy ước sub-surface bên dưới.
>
> **v1 compatibility (existing FEAT-003 instances):** Các file đã freeze ở `template_version: 1` và `canonical: false` chỉ dùng **core H2 §1–§7** (một surface duy nhất, không có H2 sub-surface). Không bắt buộc migrate; tooling đọc v1 instances như single-surface screen. Screen mới hoặc re-author dùng `template_version: 2` và `canonical: false`.

<a id="<stable-screen-anchor-id>"></a>

## 1. Screen identity

| Field | Value |
| --- | --- |
| Screen ID | `<screen_id>` |
| Screen name | `<screen_name>` |
| Related feature | `<related_feature>` |
| Compose / Voyager | `<compose paths>` |
| Stable anchor | `<stable-screen-anchor-id>` |
| Template version | `2` (instance: `2`; legacy v1 instances: `1`) |

## 2. Purpose

<Mô tả mục đích screen bằng tiếng Việt; tên kỹ thuật/path/field tiếng Anh.>

## 3. Scope and ownership

<Phạm vi ownership của screen (ví dụ **published-leg**, **account-gated**, v.v. theo feature liên quan); ghi rõ path **Observed / shared / out-of-slice** nếu có. Link cross-feature chỉ khi đã tồn tại trong evidence.>

## 4. Data contract and evidence

<Data in / data out / navigation contract dạng prose — **không** đưa vào cột bảng item.>

**Evidence labels** (áp dụng trong §4, §5, §8+):

| Label | Ý nghĩa |
| --- | --- |
| **Normative** | Contract hành vi/dữ liệu/API từ harness feature + `docs/spec` — không suy từ code |
| **Observed** | Ghi nhận implementation hiện tại; không thay source of truth |
| **Unresolved** | Conflict hoặc chưa chứng minh E2E |
| **Non-evidence** | Placeholder template hoặc sub-surface mẫu chưa có evidence — **không** dùng làm acceptance |

## 5. Screen items (main surface)

<a id="<stable-screen-anchor-id>-main"></a>

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | `<screen_id>-<GROUP>-001` | `<item name>` | `<UI type>` | Req | `<behavior; gộp input/output vào đây nếu có>` — **Normative** |

**Quy ước bảng (mọi surface / sub-surface):**

- Đúng **6 cột:** `No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi`.
- **Không** cột Data in / Data out / Input / Output — data contract thuộc §4.
- `No.` **reset `1..n` trong từng bảng** (mỗi surface / sub-surface một dãy riêng).
- **Item ID không reset** giữa các bảng — giữ **stable** và **duy nhất toàn file** khi tách, thêm, hoặc cập nhật item.
- Gắn nhãn evidence (**Normative** / **Observed** / **Unresolved**) trong cột hành vi hoặc prose §4 khi áp dụng.

**Item ID pattern (main surface):** `<screen_id>-<GROUP>-<NNN>` — ví dụ `SCR-003-01-HDR-001`, `SCR-003-01-GRD-002`.

## 6. Screen flow and feature links

<Transition tới screen khác trong slice; tham chiếu Item ID khi mô tả tap/back. Liệt kê chỉ các flow feature **áp dụng** cho screen này.>

**Feature flow links** — mỗi flow áp dụng phải có wiki-link **và** relative Markdown source link. Ví dụ FEAT-003:

- Main flow: [[FEAT-003-browse-and-search-published-poses#main-flow|FEAT-003 Main flow]] · [FEAT-003 Main flow](../../../features/FEAT-003-browse-and-search-published-poses.md#main-flow)
- Alternative A1 / A2: [[FEAT-003-browse-and-search-published-poses#alternative-flows|FEAT-003 Alternative A1/A2]] · [Alternative flows](../../../features/FEAT-003-browse-and-search-published-poses.md#alternative-flows)
- Exception E1 / E2: [[FEAT-003-browse-and-search-published-poses#exception-flows|FEAT-003 Exception E1/E2]] · [Exception flows](../../../features/FEAT-003-browse-and-search-published-poses.md#exception-flows)

## 7. Traceability and unresolved items

<Screen item → API → model; unresolved chỉ khi có trong evidence hiện có. Link `../apis.md`, `../models.md` khi cần.>

---

## 8. Sub-surface rules

> **Chỉ thêm H2 §8 trở đi khi screen có sub-surface thực tế** (full-screen detail/sub-screen, dialog, bottom sheet, menu, popup, context menu, overlay). Mỗi sub-surface = **một H2 độc lập** + anchor ổn định + bảng 6 cột riêng. Xóa toàn bộ khối placeholder bên dưới nếu screen không có sub-surface tương ứng.
>
> Các section placeholder dưới đây đánh dấu **Non-evidence** — chỉ hướng dẫn author; không phải acceptance contract.

**Item ID suffix (sub-surface):** `<screen_id>-<SUFFIX>-<NNN>`

| Suffix | Sub-surface | Ý nghĩa |
| --- | --- | --- |
| `DTL` | Full-screen detail | Nested navigable full-screen detail/sub-screen **co-located** trong file main screen; push/back (hoặc inline full-screen host tương đương) — **không** phải `DLG`, `OVR`, `BS`, `MNU`, `POP`, `CTX` |
| `DLG` | Dialog | Modal dialog (alert, confirm, form dialog) |
| `BS` | BottomSheet | Bottom sheet / modal sheet |
| `MNU` | Menu | Dropdown / overflow / action menu anchored to control |
| `POP` | Popup | Ephemeral popup (tooltip-adjacent, lightweight popover, non-modal) |
| `CTX` | Context menu | Long-press / right-click context menu |
| `OVR` | Overlay | Full-screen or scrim overlay (loading veil, blocking overlay, coach mark layer) |

**Khi dùng `DTL` (co-located) vs standalone `SCR-*` file:**

- **`DTL` co-located:** Detail/sub-screen gắn chặt main surface (cùng feature slice, cùng navigation host hoặc inline overlay), cần traceability Item ID ↔ main trong **một file**, và surface là **full-screen navigable** (back/dismiss trả về main). Ví dụ: `SCR-002-01-DTL-001` … `SCR-002-01-DTL-005` trong [Gallery](./mobile/scr-002-01-gallery.md#scr-002-01-gallery-dtl-photo-detail).
- **Standalone `SCR-*` file:** Detail có screen identity độc lập (tab root, feature slice riêng, reuse từ nhiều parent, hoặc đủ phức tạp để warrant §1–§7 riêng). Không dùng suffix `DTL` — dùng `screen_id` mới và file instance riêng.
- Mỗi `DTL` = **một H2** (thường là sub-surface H2 đầu tiên sau §7, ví dụ §8) + anchor `<stable-screen-anchor-id>-dtl-<slug>` + bảng 6 cột; Item ID `<screen_id>-DTL-<NNN>`.

### Full-screen detail — `<detail name>` *(placeholder — Non-evidence)*

<a id="<stable-screen-anchor-id>-dtl-<slug>"></a>

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | `<screen_id>-DTL-001` | `<back / dismiss control>` | Icon button | Req | `<open trigger Item ID từ main surface>; onDismiss/back → main>` — **Non-evidence** |

## 9. Dialog — `<dialog name>` *(placeholder — Non-evidence)*

<a id="<stable-screen-anchor-id>-dlg-<slug>"></a>

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | `<screen_id>-DLG-001` | `<dialog title / shell>` | Dialog | Req | `<open trigger Item ID>; dismiss/back behavior>` — **Non-evidence** |

## 10. Bottom sheet — `<sheet name>` *(placeholder — Non-evidence)*

<a id="<stable-screen-anchor-id>-bs-<slug>"></a>

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | `<screen_id>-BS-001` | `<sheet handle / shell>` | BottomSheet | Req | `<open trigger Item ID>; swipe-to-dismiss>` — **Non-evidence** |

## 11. Menu — `<menu name>` *(placeholder — Non-evidence)*

<a id="<stable-screen-anchor-id>-mnu-<slug>"></a>

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | `<screen_id>-MNU-001` | `<menu anchor control>` | Menu | Req | `<anchor Item ID>; item selection behavior>` — **Non-evidence** |

## 12. Popup — `<popup name>` *(placeholder — Non-evidence)*

<a id="<stable-screen-anchor-id>-pop-<slug>"></a>

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | `<screen_id>-POP-001` | `<popup content>` | Popup | Opt | `<anchor Item ID>; auto-dismiss rules>` — **Non-evidence** |

## 13. Context menu — `<context menu name>` *(placeholder — Non-evidence)*

<a id="<stable-screen-anchor-id>-ctx-<slug>"></a>

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | `<screen_id>-CTX-001` | `<context target>` | Context menu | Opt | Long-press / secondary click on `<anchor Item ID>` — **Non-evidence** |

## 14. Overlay — `<overlay name>` *(placeholder — Non-evidence)*

<a id="<stable-screen-anchor-id>-ovr-<slug>"></a>

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | `<screen_id>-OVR-001` | `<overlay layer>` | Overlay | Opt | `<trigger Item ID>; blocking vs non-blocking>` — **Non-evidence** |

---

## 15. Rationale

| Quyết định | Lý do |
| --- | --- |
| Multi-surface trong một file | `DTL` / dialog / sheet / menu thường không đủ độc lập để tách screen file; gom sub-surface giữ traceability Item ID ↔ main surface |
| `DTL` co-located vs standalone `SCR-*` | `DTL` cho nested full-screen detail trong cùng file; standalone file khi detail warrant screen identity riêng (xem §8) |
| H2 §1–§7 giữ nguyên v1 | FEAT-003 instances (`template_version: 1`) không cần re-author; tooling đọc core sections tương thích |
| `No.` reset per table; Item ID stable cross-table | Đọc bảng theo surface; ID vẫn unique và ổn định khi thêm sub-surface |
| Evidence labels tách khỏi bảng item | Data contract ở §4; hành vi item ở cột thứ 6; tránh cột Data in/out |
| Placeholder §9–§14 Non-evidence | Template hướng dẫn suffix/pattern; author xóa hoặc thay bằng sub-surface thật có evidence |
| Wiki-link + relative source + flow anchors | Đồng bộ harness feature flows (`#main-flow`, `#alternative-flows`, `#exception-flows`) cho cả human và tooling |
