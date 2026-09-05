---
screen_id: SCR-007-02
screen_name: Admin Community Poses
related_feature: FEAT-007
compose: web/admin-ui/src/app/admin/community/page.js
status: draft
template_version: 2
canonical: false
---

# SCR-007-02 — Admin Community Poses

<a id="scr-007-02-admin-community-poses"></a>

## 1. Screen identity

| Field | Value |
| --- | --- |
| Screen ID | SCR-007-02 |
| Screen name | Admin Community Poses |
| Related feature | FEAT-007 |
| Compose / Voyager | `web/admin-ui/src/app/admin/community/page.js` |
| Stable anchor | `scr-007-02-admin-community-poses` |
| Template version | `2` |

## 2. Purpose

Cho Admin operator upload pose (extract + tạo community pose), liệt kê poses hiện có, và chỉnh sửa/xóa metadata qua overlay edit.

## 3. Scope and ownership

Thuộc **FEAT-007** community intake/listing. Gọi Next.js admin proxies: `GET/POST/PATCH/DELETE /api/admin/community/poses`, `POST /api/admin/extract-pose`, `GET /api/admin/extract-jobs/:jobId`. Upload flow poll job client-side tối đa 60 lần (1s interval) — **Observed**; FEAT-007 ghi **Not observed** truthful async UI — **Unresolved** status discrepancy.

## 4. Data contract and evidence

- **Data in (list):** `GET /api/admin/community/poses?limit=100` → `payload.data` array — **Observed**.
- **Data in (upload):** `FormData` image → `POST /api/admin/extract-pose`; poll `GET /api/admin/extract-jobs/:jobId` until `succeeded`/`failed`; then `POST /api/admin/community/poses` với `jobId`, `ownerAccountId`, `name`, `tags`, `description`, `bodyParts: ['full-body']`, `difficulty: null` — **Observed**.
- **Data out (edit):** `PATCH /api/admin/community/poses/:poseId` với `name`, `tags`, `description`, `status` — **Observed**.
- **Data out (delete):** `DELETE /api/admin/community/poses/:poseId` sau native confirm — **Observed**.
- **Navigation:** `NavButton` mặc định `router.back()` — **Observed**.

**Evidence labels:**

| Label | Áp dụng |
| --- | --- |
| **Normative** | FEAT-007: `202` là queued không phải complete; Pose tạo sau job `succeeded` với `ownerAccountId` |
| **Observed** | Layout 2 cột, form fields, grid cards, edit overlay, client polling, `window.confirm` delete |
| **Unresolved** | Upload form `status` select không gửi trong POST body; badge `local` vs select `draft`/`published`; FEAT-007 "not observed" polling vs code poll 60× |

## 5. Screen items (main surface)

<a id="scr-007-02-admin-community-poses-main"></a>

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-007-02-HDR-001 | Back | Icon button (`NavButton`) | Req | `router.back()` khi không có `href` — **Observed** |
| 2 | SCR-007-02-HDR-002 | Screen title | Text (`h1`) | Req | `"Admin — Community Poses"` uppercase — **Observed** |
| 3 | SCR-007-02-UPL-001 | Upload panel title | Text | Req | `"Upload Pose"` — **Observed** |
| 4 | SCR-007-02-UPL-002 | Image picker | File input (`accept="image/*"`) | Req | Chọn file → preview base64; clear bằng nút X; validate thiếu file → error `"Vui lòng chọn hình ảnh."` — **Observed** |
| 5 | SCR-007-02-UPL-003 | Pose name | Text input | Req | Placeholder `"Pose name *"`; auto-fill từ tên file khi chọn ảnh; validate trim — **Observed** |
| 6 | SCR-007-02-UPL-004 | Tags | Text input | Opt | Placeholder `"Tags (comma-separated)"`; normalize comma list trước POST — **Observed** |
| 7 | SCR-007-02-UPL-005 | Description | Textarea | Opt | Placeholder `"Description"`; gửi `null` nếu rỗng — **Observed** |
| 8 | SCR-007-02-UPL-006 | Owner account UUID | Text input | Req | Default `00000000-0000-0000-0000-000000000001`; validate trim — **Observed** |
| 9 | SCR-007-02-UPL-007 | Status (upload form) | Native `<select>` | Opt | Options `draft`/`published`; initial state `'local'` (không khớp option) — **Observed**; **không** gửi trong POST body — **Unresolved** |
| 10 | SCR-007-02-UPL-008 | Upload error banner | Inline alert | — | Hiển thị `error` state — **Observed** |
| 11 | SCR-007-02-UPL-009 | Upload notice banner | Inline notice | — | Ví dụ `"Đang chạy extraction..."`, `"Đã extraction và tạo Pose thành công."` — **Observed** |
| 12 | SCR-007-02-UPL-010 | Upload Pose | Action button | Req | `UPLOAD POSE` / `UPLOADING...`; disabled khi `submitting`; chạy extract → poll job → POST pose → refresh list — **Observed** |
| 13 | SCR-007-02-LST-001 | List panel title | Text + count | Req | `"All Poses"` + `({poses.length})` — **Observed** |
| 14 | SCR-007-02-LST-002 | Refresh | Icon button | Opt | Gọi lại `fetchPoses`; icon spin khi `loadingPoses` — **Observed** |
| 15 | SCR-007-02-LST-003 | List error state | Alert + retry | — | Message `"Không tải được danh sách pose:"` + nút `THỬ LẠI` — **Observed** |
| 16 | SCR-007-02-LST-004 | List loading | Text | — | `"Loading..."` khi load lần đầu — **Observed** |
| 17 | SCR-007-02-LST-005 | List empty | Text | — | `"Chưa có pose nào"` — **Observed** |
| 18 | SCR-007-02-LST-006 | Pose card grid | Responsive grid | Req | `grid-cols-2 xl:3 2xl:4`; click/Enter/Space → mở edit overlay — **Observed** |
| 19 | SCR-007-02-LST-007 | Pose card image | Image / placeholder | Req | `skeletonUrl` hoặc upload icon placeholder — **Observed** |
| 20 | SCR-007-02-LST-008 | Pose card name | Text | Req | Truncate `pose.name` — **Observed** |
| 21 | SCR-007-02-LST-009 | Pose status badge | Badge | Req | `pose.status` uppercase; màu `local`/`published` từ `STATUS_BADGE` — **Observed** |
| 22 | SCR-007-02-LST-010 | Download count | Text | Opt | `↓{downloadCount ?? 0}` — **Observed** |

## 6. Screen flow and feature links

| Transition | Target |
| --- | --- |
| Tap SCR-007-02-HDR-001 | Back (history) — thường [SCR-007-01 Dashboard](./scr-007-01-dashboard.md#scr-007-01-admin-dashboard-main) |
| Tap SCR-007-02-LST-006 | [§8 Edit Pose overlay](#scr-007-02-admin-community-poses-ovr-edit-pose) |
| Successful upload | Refresh list (SCR-007-02-LST-002 behavior inline) |

**FEAT-007 flow links:**

- Main flow: [[FEAT-007-operate-pose-content-from-admin-web#main-flow|FEAT-007 Main flow]] · [FEAT-007 Main flow](../../../../features/FEAT-007-operate-pose-content-from-admin-web.md#main-flow)
- Alternative A1 — Refresh: [[FEAT-007-operate-pose-content-from-admin-web#alternative-flows|FEAT-007 Alternative A1 — Refresh]] · [FEAT-007 Alternative flows](../../../../features/FEAT-007-operate-pose-content-from-admin-web.md#alternative-flows) (SCR-007-02-LST-002)
- Exception E1 — Missing/invalid admin configuration: [[FEAT-007-operate-pose-content-from-admin-web#exception-flows|FEAT-007 Exception E1]] · [FEAT-007 Exception flows](../../../../features/FEAT-007-operate-pose-content-from-admin-web.md#exception-flows)
- Exception E2 — Upstream rejection: [[FEAT-007-operate-pose-content-from-admin-web#exception-flows|FEAT-007 Exception E2]] · [FEAT-007 Exception flows](../../../../features/FEAT-007-operate-pose-content-from-admin-web.md#exception-flows) (SCR-007-02-UPL-008, SCR-007-02-LST-003)

## 7. Traceability and unresolved items

| Item | API | Model |
| --- | --- | --- |
| SCR-007-02-LST-006–010 | `GET /api/admin/community/poses` | Community pose list DTO |
| SCR-007-02-UPL-010 | `POST /api/admin/extract-pose`, `GET /api/admin/extract-jobs/:id`, `POST /api/admin/community/poses` | `ExtractionJob`, `Pose` |
| SCR-007-02-OVR-010 (save) | `PATCH /api/admin/community/poses/:poseId` | `Pose` metadata |
| SCR-007-02-OVR-011 (delete) | `DELETE /api/admin/community/poses/:poseId` | `Pose` |

HTTP contract: [../../apis.md](../../apis.md). Model: [../../models.md](../../models.md).

**Status discrepancy:**

| Topic | Feature evidence | Observed UI |
| --- | --- | --- |
| Truthful async job UI | FEAT-007 **Not observed** Admin polling / truthful state | Client poll 60×1s; notice `"Đang chạy extraction..."` — **Unresolved** |
| Upload status field | — | Select hiển thị nhưng không POST — **Unresolved** |
| Status vocabulary | — | Badge `local`/`published` vs select `draft`/`published` — **Unresolved** |

## 8. Overlay — Edit Pose

<a id="scr-007-02-admin-community-poses-ovr-edit-pose"></a>

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-007-02-OVR-001 | Scrim layer | Overlay (`fixed inset-0 z-50 bg-black/50`) | Req | Click scrim → `closeEdit()` — **Observed** |
| 2 | SCR-007-02-OVR-002 | Edit panel shell | Panel (`max-w-lg max-h-[90vh]`) | Req | `stopPropagation` trên panel; scroll overflow — **Observed** |
| 3 | SCR-007-02-OVR-003 | Edit title | Text | Req | `"Edit Pose"` — **Observed** |
| 4 | SCR-007-02-OVR-004 | Close (X) | Icon button | Req | `closeEdit()` — **Observed** |
| 5 | SCR-007-02-OVR-005 | Pose preview image | Image / placeholder | Req | `selectedPose.skeletonUrl` — **Observed** |
| 6 | SCR-007-02-OVR-006 | Pose name | Text input | Req | Validate trim; placeholder `"Pose name *"` — **Observed** |
| 7 | SCR-007-02-OVR-007 | Tags | Text input | Opt | Comma-separated; normalize trước PATCH — **Observed** |
| 8 | SCR-007-02-OVR-008 | Description | Textarea | Opt | Gửi `null` nếu rỗng — **Observed** |
| 9 | SCR-007-02-OVR-009 | Status | Native `<select>` | Req | Options `draft`/`published`; PATCH `status` — **Observed** |
| 10 | SCR-007-02-OVR-010 | Save | Action button | Req | `SAVE` / `SAVING...`; PATCH pose; notice `"Đã lưu thay đổi thành công."` — **Observed** |
| 11 | SCR-007-02-OVR-011 | Delete | Action button | Req | Trước DELETE gọi `window.confirm('Bạn có chắc chắn xóa pose "…"? Hành động này không thể hoàn tác.')`; cancel → không xóa; confirm → DELETE + close + list notice — **Observed** (native confirmation, không sub-surface DLG) |
| 12 | SCR-007-02-OVR-012 | Cancel | Button | Req | `closeEdit()`; disabled khi saving/deleting — **Observed** |
| 13 | SCR-007-02-OVR-013 | Edit error banner | Inline alert | — | `editError` — **Observed** |
| 14 | SCR-007-02-OVR-014 | Edit notice banner | Inline notice | — | `editNotice` — **Observed** |
