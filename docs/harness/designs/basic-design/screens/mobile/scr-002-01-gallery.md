---
screen_id: SCR-002-01
screen_name: Gallery
related_feature: FEAT-002
compose: GalleryScreen + PhotoDetailDialog (`mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/gallery/`)
status: draft
template_version: 2
canonical: false
---

# SCR-002-01 — Gallery (`GalleryScreen` + `PhotoDetailDialog`)

> **Template v2** — `docs/harness/designs/basic-design/screens/TEMPLATE.md`. Main list = `GalleryScreen`; full-screen detail và delete `AlertDialog` = sub-surfaces trong cùng file. `PaywallScreen` tham chiếu OVR canonical tại [SCR-001-01 §11](./scr-001-01-camera.md#scr-001-01-camera-ovr-paywall).

<a id="scr-002-01-gallery-galleryscreen"></a>

## 1. Screen identity

| Field | Value |
| --- | --- |
| Screen ID | SCR-002-01 |
| Screen name | Gallery |
| Related feature | FEAT-002 (primary); FEAT-011 (gated save/share) |
| Compose / Voyager | `GalleryScreen` via `GalleryListScreen` (`Navigation.kt:219-233`); `PhotoDetailDialog` inline khi `selectedPhoto != null` **hoặc** qua `GalleryPhotoDetailScreen` Voyager push |
| Stable anchor | `scr-002-01-gallery-galleryscreen` |
| Template version | `2` |

## 2. Purpose

Cho phép Photographer duyệt ảnh local theo nhóm ngày, mở chi tiết, favorite (callback), xóa, export Save to Photos và share — **Observed** contract FEAT-002. Capture upstream tại [SCR-001-01 Camera](./scr-001-01-camera.md#scr-001-01-camera-camerascreen) (FEAT-001).

## 3. Scope and ownership

Thuộc **local gallery leg** (FEAT-002): reactive `Photo` records từ SQLDelight, không HTTP API. Paid save/share gate thuộc [FEAT-011](../../../../features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md) — paywall UI **không** duplicate; cross-ref [SCR-001-01-OVR-001](./scr-001-01-camera.md#scr-001-01-camera-ovr-paywall).

**Related feature status (evidence-backed):**

| Feature | Harness status | Screen evidence | Notes |
| --- | --- | --- | --- |
| FEAT-002 | approved | **Observed** — `GalleryScreen`, `GalleryViewModel`, `PhotoDetailDialog` | File cleanup on delete **Partial** per feature doc |
| FEAT-011 | approved | **Observed** — `showPaywall` on save/share tap (`PhotoDetailDialog.kt:157-178`, `286-291`) | Roadmap ghi no paywall code — **Unresolved** (cùng discrepancy SCR-001-01 §7) |

## 4. Data contract and evidence

- **Data in:** `GalleryViewModel.uiState` — `photos`, `groupedByDate`, `isLoading`, `selectedPhoto` — **Observed**; auto-load qua `listShouldAutoLoad` — **Observed** (`GalleryScreen.kt:70`).
- **Data out:** `selectPhoto` / navigation push → detail; `deletePhoto`, `toggleFavorite`, `saveToPhotos` / `shareImage` platform calls — **Observed**; delete failure → snackbar, dialog stays open — **Observed** (`201-214`, `260-271`).
- **Navigation:** Tab root `GalleryListScreen` + `MainDock`; `onPhotoClick` → `GalleryDetailVoyagerScreen`; legacy inline `PhotoDetailDialog` khi `onPhotoClick == null` và `selectedPhoto != null` — **Observed** (`195-225`, `229`).

## 5. Screen items (main surface)

<a id="scr-002-01-gallery-main"></a>

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-002-01-SCA-001 | Scaffold shell | `Scaffold` + `SnackbarHost` | Req | Container `AiPoseColors.Background`; snackbar cho delete/save errors — **Observed** (`76-78`, `73`) |
| 2 | SCR-002-01-HDR-001 | Back control | Icon button 32dp | Opt | Chỉ khi `onBack != null`; `testTag=gallery-back-btn` — **Observed** (`99-116`; Voyager detail host) |
| 3 | SCR-002-01-HDR-002 | Screen title | Text | Req | Label `"Gallery"`; `NavigationTitle` — **Observed** (`119-123`) |
| 4 | SCR-002-01-HDR-003 | Crown upgrade CTA | Icon button 44dp / yellow surface | Opt | Nút vương miện vàng dẫn tới Paywall (`paywall.html`) per prototype `gallery.html:38-43` |
| 5 | SCR-002-01-FLT-001 | Date filter chips | Horizontal row of chips | Req | Hàng chip lọc ngày (`All`, `Today`, `7 days`, `30 days`, `Date`), active chip nền hồng per prototype `gallery.html:47-63`. **KHÔNG CÓ SEARCH BAR**. |
| 6 | SCR-002-01-ST-001 | Initial loading | `CircularProgressIndicator` | — | Khi `uiState.isLoading` — **Observed** (`129-132`) |
| 7 | SCR-002-01-ST-002 | Empty gallery | Card + CTA | — | `"No photos yet"` + `PrimaryButton` "Open camera" → `onOpenCamera` — **Observed** (`136-150`; FEAT-002 A1) |
| 8 | SCR-002-01-GRD-001 | Date section header | `SectionHeader` | Req | Một header per `groupedByDate` key; count = photos.size — **Observed** (`163-176`) |
| 9 | SCR-002-01-GRD-002 | Photo grid | `LazyVerticalGrid` 3 cột | Req | `GalleryGridDefaults.DENSE_COLUMN_COUNT=3`, gap 3dp; `MainDockContentInset` bottom padding — **Observed** (`155-161`, `GalleryGridDefaults.kt`) |
| 10 | SCR-002-01-GRD-003 | Photo card | `PhotoCard` dense | Req | Tap → `onPhotoClick` hoặc `viewModel.selectPhoto` → [detail](#scr-002-01-gallery-dtl-photo-detail) — **Observed** (`182-186`) |

## 6. Screen flow and feature links

| Transition | Target |
| --- | --- |
| Tap SCR-002-01-ST-002 CTA / dock Camera | [SCR-001-01 Camera](./scr-001-01-camera.md#scr-001-01-camera-camerascreen) (`CameraTab`) |
| Tap SCR-002-01-GRD-003 | [Photo detail](#scr-002-01-gallery-dtl-photo-detail) (Voyager push hoặc inline overlay) |
| Save / Share without premium (detail) | [SCR-001-01-OVR-001](./scr-001-01-camera.md#scr-001-01-camera-ovr-paywall) (`PaywallScreen` overlay) |
| Delete (detail) | [Delete AlertDialog](#scr-002-01-gallery-dlg-delete) |

**FEAT-002 flow links:**

- Main flow: [[FEAT-002-manage-a-local-photo-gallery#main-flow|FEAT-002 Main flow]] · [FEAT-002 Main flow](../../../../features/FEAT-002-manage-a-local-photo-gallery.md#main-flow)
- Alternative A1 — Empty gallery: [[FEAT-002-manage-a-local-photo-gallery#alternative-flows|FEAT-002 Alternative A1]] · [FEAT-002 Alternative flows](../../../../features/FEAT-002-manage-a-local-photo-gallery.md#alternative-flows) (SCR-002-01-ST-002)
- Alternative A2 — Export: [[FEAT-002-manage-a-local-photo-gallery#alternative-flows|FEAT-002 Alternative A2]] · [FEAT-002 Alternative flows](../../../../features/FEAT-002-manage-a-local-photo-gallery.md#alternative-flows) (SCR-002-01-DTL-003 Save to Photos)
- Exception E1 — Missing file: [[FEAT-002-manage-a-local-photo-gallery#exception-flows|FEAT-002 Exception E1]] · [FEAT-002 Exception flows](../../../../features/FEAT-002-manage-a-local-photo-gallery.md#exception-flows) (image load error paths)
- Exception E2 — Delete/export fails: [[FEAT-002-manage-a-local-photo-gallery#exception-flows|FEAT-002 Exception E2]] · [FEAT-002 Exception flows](../../../../features/FEAT-002-manage-a-local-photo-gallery.md#exception-flows) (SCR-002-01-DLG-002, snackbar)

**FEAT-011 flow links (save/share gate only):**

- Alternative A2 — Gallery save/share gate: [[FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases#alternative-flows|FEAT-011 Alternative A2]] · [FEAT-011 Alternative flows](../../../../features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md#alternative-flows) → [SCR-001-01-OVR-001](./scr-001-01-camera.md#scr-001-01-camera-ovr-paywall)
- Alternative A5 — Dismissal: [[FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases#alternative-flows|FEAT-011 Alternative A5]] · [FEAT-011 Alternative flows](../../../../features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md#alternative-flows)

## 7. Traceability and unresolved items

| Item | API | Model |
| --- | --- | --- |
| SCR-002-01-GRD-002, GRD-003 | None (local SQLDelight) | `Photo` — [models.md](../../models.md) |
| SCR-002-01-DTL-003 | None | `saveToPhotos` platform (iOS in scope FEAT-002) |
| SCR-002-01-DTL-004 | None | `shareImage` platform |
| Paywall (save/share) | RevenueCat (external) | Cross-ref SCR-001-01-OVR-* |

**Unresolved:**

1. **Favorite toggle UI:** `onToggleFavorite` callback tồn tại (`PhotoDetailDialog.kt:91`) nhưng **Observed** không có control favorite trên detail chrome — FR-002 favorite path chưa surfaced trên UI này.
2. **Dual detail hosts:** Voyager `GalleryPhotoDetailScreen` (navigation default) vs inline `selectedPhoto` overlay — cùng `PhotoDetailDialog` composable; E2E matrix nên cover cả hai entry paths.
3. **FEAT-011 roadmap discrepancy:** Giống [SCR-001-01 §7](./scr-001-01-camera.md#scr-001-01-camera-camerascreen) — roadmap claims no paywall code; implementation present.
4. **Save button icon:** Save action dùng `Icons.Default.Share` — **Observed** quirk (`PhotoDetailDialog.kt:162`); không đổi trong screen doc scope.

---

## 8. Full-screen detail — `PhotoDetailDialog`

<a id="scr-002-01-gallery-dtl-photo-detail"></a>

Full-screen `Box` (không Material dialog shell); mở từ SCR-002-01-GRD-003 hoặc Voyager `GalleryPhotoDetailScreen`.

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-002-01-DTL-001 | Back control | Icon button 44dp | Req | `onDismiss()` — **Observed** (`123-138`) |
| 2 | SCR-002-01-DTL-002 | Photo image | `MatchedImageDestination` + `AsyncImage` | Req | `destinationChromeVisible` gating; crop fill; `photo.poseName` a11y — **Observed** (`207-248`) |
| 3 | SCR-002-01-DTL-003 | Save action | Icon button 44dp | Opt | Premium gate → [SCR-001-01-OVR-001](./scr-001-01-camera.md#scr-001-01-camera-ovr-paywall); else `onSave(photo)` — **Observed** (`148-167`, FEAT-002 A2 / FEAT-011 A2) |
| 4 | SCR-002-01-DTL-004 | Share action | Icon button 44dp | Opt | Cùng premium gate → SCR-001-01-OVR-001; else `onShare(photo)` — **Observed** (`169-183`) |
| 5 | SCR-002-01-DTL-005 | Delete action | Icon button 44dp | Req | `showDeleteConfirm = true` → [DLG delete](#scr-002-01-gallery-dlg-delete) — **Observed** (`185-202`) |

**Paywall occurrence (FEAT-011):** Khi `showPaywall`, render `PaywallScreen` full-size (`PhotoDetailDialog.kt:286-291`). Item contract: dùng **SCR-001-01-OVR-001** … **SCR-001-01-OVR-008** tại [scr-001-01-camera.md §11](./scr-001-01-camera.md#scr-001-01-camera-ovr-paywall) — không duplicate bảng OVR tại file này.

## 9. Dialog — delete confirmation (`AlertDialog`)

<a id="scr-002-01-gallery-dlg-delete"></a>

Mở từ SCR-002-01-DTL-005; Material `AlertDialog`.

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-002-01-DLG-001 | Delete dialog shell | `AlertDialog` | Req | Title `"Delete Photo"`; body permanent-delete copy — **Observed** (`255-258`) |
| 2 | SCR-002-01-DLG-002 | Confirm delete | `TextButton` | Req | `onDelete(photo.id)` suspend; dismiss detail chỉ khi `true`; failure → snackbar + dialog closes without detail dismiss — **Observed** (`259-277`, FEAT-002 E2) |
| 3 | SCR-002-01-DLG-003 | Cancel | `TextButton` | Req | `showDeleteConfirm = false` — **Observed** (`279-282`) |
