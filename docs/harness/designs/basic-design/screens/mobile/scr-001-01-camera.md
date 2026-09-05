---
screen_id: SCR-001-01
screen_name: Camera
related_feature: FEAT-001
compose: CameraScreen (`mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt`)
status: draft
template_version: 2
canonical: false
---

# SCR-001-01 — Camera (`CameraScreen`)

> **Template v2** — `docs/harness/designs/basic-design/screens/TEMPLATE.md`. Sub-surfaces có evidence: `CameraMorePopup`, zoom slider (`CameraZoomSlider` trong `Popup`), và `PaywallScreen` (OVR canonical).

<a id="scr-001-01-camera-camerascreen"></a>

## 1. Screen identity

| Field | Value |
| --- | --- |
| Screen ID | SCR-001-01 |
| Screen name | Camera |
| Related feature | FEAT-001 (primary); FEAT-008, FEAT-011, FEAT-012 (cross-slice) |
| Compose / Voyager | `CameraScreen` via `CameraTab.Content()` (`Navigation.kt:153-170`) |
| Stable anchor | `scr-001-01-camera-camerascreen` |
| Template version | `2` |

## 2. Purpose

Cho phép Photographer xem camera preview, điều chỉnh controls (flash, grid, zoom, pose overlay), chụp ảnh và lưu local `Photo`; điều hướng Gallery hoặc quay lại Poses tab. Capture semantics thuộc [FEAT-001](../../../../features/FEAT-001-capture-a-photo-on-mobile.md); pose overlay handoff thuộc [FEAT-008](../../../../features/FEAT-008-use-published-poses.md).

## 3. Scope and ownership

Thuộc **mobile capture leg** (FEAT-001). Pose overlay đọc `PreparedPoseReference` từ `PoseServiceLocator` hoặc snapshot restore (FEAT-008 / FEAT-012). Paid access gate thuộc [FEAT-011](../../../../features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md) — OVR canonical tại [§10 Paywall](#scr-001-01-camera-ovr-paywall). Gallery thumbnail → [SCR-002-01 Gallery](./scr-002-01-gallery.md#scr-002-01-gallery-galleryscreen) (FEAT-002, out-of-slice browse).

**Related feature status (evidence-backed):**

| Feature | Harness status | Screen evidence | Notes |
| --- | --- | --- | --- |
| FEAT-001 | approved | **Observed** — `CameraScreen`, `CameraCoordinator`, `PhotoRepository` | Android camera parity **Unresolved** per feature doc |
| FEAT-008 | draft | **Observed** — overlay từ `activeReference` / `OverlaySourceState.PoseImage` | Save/Unsave account API **Unresolved** |
| FEAT-011 | approved | **Observed** — `PaywallScreen` early gate (`CameraScreen.kt:92-98`) | Roadmap vẫn ghi post-v1.0 / no paywall code — **Unresolved** (xem §7) |
| FEAT-012 | approved | **Observed** — `CameraSnapshotRepository.load/save`, `clearPose` | Feature doc vẫn ghi durable restore **Unresolved** — **Unresolved** doc/code tension (xem §7) |

## 4. Data contract and evidence

- **Data in:** Camera permission state từ native `CameraController`; optional `PreparedPoseReference` (session + restored snapshot); `PurchaseSnapshot` từ `PurchaseGateway` — **Observed**.
- **Data out:** Capture → local `Photo` row + image file qua `CameraCoordinator` ports; settings/pose snapshot persist qua `CameraSnapshotPersistence.save` — **Observed** (FEAT-012 implementation); navigation `onDismiss` → Poses tab qua `LocalCameraDismiss` — **Observed**.
- **Navigation:** `CameraTab` standalone (ẩn `MainDock`); close/users buttons gọi `onDismiss`; gallery thumbnail → `GalleryTab` — **Observed**.

**Evidence labels:** Normative = harness feature/spec; Observed = code hiện tại; Unresolved = conflict hoặc chưa E2E.

## 5. Screen items (main surface)

<a id="scr-001-01-camera-main"></a>

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-001-01-PRV-001 | Camera preview | `CameraPreview` | Req | Native preview sau `CameraPermissionState.AUTHORIZED`; stop khi denied/restricted — **Observed** (`CameraScreen.kt:262-265`, `204-209`) |
| 2 | SCR-001-01-OVL-001 | Center crosshair | Overlay graphics | Opt | Hiện khi không có pose overlay (`poseOverlay == null`) — **Observed** (`270-272`) |
| 3 | SCR-001-01-OVL-002 | Rule-of-thirds grid | `CameraGridOverlay` | Opt | Hiện khi `uiState.isGridVisible`; toggle qua More popup — **Observed** (`276-278`, `FEAT-012` grid setting) |
| 4 | SCR-001-01-OVL-003 | Pose guide image | `AsyncImage` overlay | Opt | Khi `hasOverlay` + valid `CameraGuideAsset`; pan/zoom gesture; opacity/scale/tint từ `CameraUiState` — **Observed** (`287-319`, FEAT-008 handoff) |
| 5 | SCR-001-01-ST-001 | Pose guide unavailable | Text message | — | Khi asset invalid; không chặn capture — **Observed** (`283-285`, `522-538`) |
| 6 | SCR-001-01-HDR-001 | Close control | `CameraCloseButton` | Req | Tap → `onDismiss` (Poses tab); `testTag=camera-close-btn` — **Observed** (`324-327`, `542-558`) |
| 7 | SCR-001-01-HDR-002 | More / settings | `CameraMoreButton` | Opt | Toggle `isMoreMenuVisible`; disabled khi capture in-flight hoặc chưa authorized; mở [POP More](#scr-001-01-camera-pop-more) — **Observed** (`330-340`, `562-589`) |
| 8 | SCR-001-01-HDR-003 | Browse poses | `CameraUsersButton` | Opt | Tap → `onDismiss` khi controls enabled; `testTag=poseButton` — **Observed** (`377-383`, `592-619`) |
| 9 | SCR-001-01-ZOM-001 | Zoom indicator | `CameraZoomIndicator` | Opt | Label `cameraZoomLabel(value)`; tap toggle [POP zoom slider](#scr-001-01-camera-pop-zoom); `testTag=zoomButton` — **Observed** (`391-396`, `622-643`) |
| 10 | SCR-001-01-FX-001 | Capture flash veil | Full-bleed overlay | — | ~250ms sau capture accepted — **Observed** (`420-426`, `241-247`) |
| 11 | SCR-001-01-SHT-001 | Gallery thumbnail | `GalleryThumbnailButton` | Opt | Latest photo thumb hoặc placeholder `G`; tap → `GalleryTab` khi enabled — **Observed** (`441-444`, `752-795`; FEAT-001 A1) |
| 12 | SCR-001-01-SHT-002 | Shutter / capture | `CaptureButton` | Req | Enabled khi authorized và không in-flight; `coordinator.onCaptureRequested()` — **Normative** FR-001/FR-002; **Observed** (`446-454`, `722-749`) |
| 13 | SCR-001-01-SHT-003 | Flip camera | `FlipShortcutButton` | Opt | `cameraController.switchCamera()`; `testTag=camera-flip-btn` — **Observed** (`456`, `798-814`) |
| 14 | SCR-001-01-ST-002 | Capture status line | `Text` caption | — | `coordState.statusText()` khi non-null — **Observed** (`461-467`) |
| 15 | SCR-001-01-ST-003 | Permission denied veil | `PermissionDeniedOverlay` | — | Khi `DENIED` hoặc `RESTRICTED`; nút Open Settings — **Observed** (`470-472`, `702-719`; FEAT-001 E1) |

## 6. Screen flow and feature links

| Transition | Target |
| --- | --- |
| Tap SCR-001-01-HDR-001 / SCR-001-01-HDR-003 | Poses tab (`onDismiss` / `LocalCameraDismiss`) |
| Tap SCR-001-01-SHT-001 | [SCR-002-01 Gallery](./scr-002-01-gallery.md#scr-002-01-gallery-galleryscreen) (`GalleryTab`) |
| Unentitled user opens Camera | [SCR-001-01-OVR-001](#scr-001-01-camera-ovr-paywall) (blocking; không render main items) |
| Tap SCR-001-01-HDR-002 | [CameraMorePopup](#scr-001-01-camera-pop-more) |
| Tap SCR-001-01-ZOM-001 | [Zoom slider popup](#scr-001-01-camera-pop-zoom) |

**FEAT-001 flow links:**

- Main flow: [[FEAT-001-capture-a-photo-on-mobile#main-flow|FEAT-001 Main flow]] · [FEAT-001 Main flow](../../../../features/FEAT-001-capture-a-photo-on-mobile.md#main-flow)
- Alternative A1 — Open Gallery: [[FEAT-001-capture-a-photo-on-mobile#alternative-flows|FEAT-001 Alternative A1]] · [FEAT-001 Alternative flows](../../../../features/FEAT-001-capture-a-photo-on-mobile.md#alternative-flows) (SCR-001-01-SHT-001)
- Exception E1 — Permission denied: [[FEAT-001-capture-a-photo-on-mobile#exception-flows|FEAT-001 Exception E1]] · [FEAT-001 Exception flows](../../../../features/FEAT-001-capture-a-photo-on-mobile.md#exception-flows) (SCR-001-01-ST-003)
- Exception E2 — Persistence fails: [[FEAT-001-capture-a-photo-on-mobile#exception-flows|FEAT-001 Exception E2]] · [FEAT-001 Exception flows](../../../../features/FEAT-001-capture-a-photo-on-mobile.md#exception-flows) (SCR-001-01-ST-002 / coordinator)

**FEAT-008 flow links (pose overlay scope):**

- Main flow: [[FEAT-008-use-published-poses#main-flow|FEAT-008 Main flow]] · [FEAT-008 Main flow](../../../../features/FEAT-008-use-published-poses.md#main-flow) (SCR-001-01-OVL-003)
- Exception E1 — Skeleton unavailable: [[FEAT-008-use-published-poses#exception-flows|FEAT-008 Exception E1]] · [FEAT-008 Exception flows](../../../../features/FEAT-008-use-published-poses.md#exception-flows) (SCR-001-01-ST-001)

**FEAT-011 flow links:**

- Main flow: [[FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases#main-flow|FEAT-011 Main flow]] · [FEAT-011 Main flow](../../../../features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md#main-flow)
- Alternative A1 — Capture gate: [[FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases#alternative-flows|FEAT-011 Alternative A1]] · [FEAT-011 Alternative flows](../../../../features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md#alternative-flows) (SCR-001-01-OVR-001)
- Alternative A5 — Dismissal: [[FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases#alternative-flows|FEAT-011 Alternative A5]] · [FEAT-011 Alternative flows](../../../../features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md#alternative-flows)

**FEAT-012 flow links:**

- Main flow: [[FEAT-012-restore-pose-and-camera-settings-across-relaunch#main-flow|FEAT-012 Main flow]] · [FEAT-012 Main flow](../../../../features/FEAT-012-restore-pose-and-camera-settings-across-relaunch.md#main-flow)
- Alternative A2 — Clear overlay: [[FEAT-012-restore-pose-and-camera-settings-across-relaunch#alternative-flows|FEAT-012 Alternative A2]] · [FEAT-012 Alternative flows](../../../../features/FEAT-012-restore-pose-and-camera-settings-across-relaunch.md#alternative-flows) (SCR-001-01-POP-006)
- Exception E1 — Corrupt pose asset: [[FEAT-012-restore-pose-and-camera-settings-across-relaunch#exception-flows|FEAT-012 Exception E1]] · [FEAT-012 Exception flows](../../../../features/FEAT-012-restore-pose-and-camera-settings-across-relaunch.md#exception-flows)

## 7. Traceability and unresolved items

| Item | API / persistence | Model / notes |
| --- | --- | --- |
| SCR-001-01-SHT-002 | None (local capture) | `Photo` via `PhotoRepository` — [models.md](../../models.md) |
| SCR-001-01-OVL-003 | Community detail (Try Pose, upstream) | `PreparedPoseReference` |
| SCR-001-01-POP-* / ZOM-* | `CameraSnapshot` SQLDelight | `PersistedCameraSettings`, `PersistedPoseIdentity` — FEAT-012 |
| SCR-001-01-OVR-001 | RevenueCat SDK (external) | `PurchaseSnapshot`, `premium` entitlement — FEAT-011 |

**Unresolved:**

1. **FEAT-012 doc/code tension:** Feature doc `Current evidence` vẫn ghi durable restore **Unresolved** / không persist qua relaunch (`FEAT-012` L148-149), trong khi code **Observed** load/save snapshot (`CameraScreen.kt:107-132`, `194-199`; plan `260831-0000` verified). Cần align harness doc với implementation.
2. **FEAT-011 roadmap/code discrepancy:** [product-delivery-roadmap.md](../../../../specs/product-delivery-roadmap.md) L108-109, L143 ghi **không có** paywall code trong `mobile/`; code **Observed** có `Paywall.kt`, `PaywallScreen`, gateway gating. Roadmap stale so với approved FEAT-011 + implementation.
3. **FEAT-011 gate semantics:** Normative trigger mô tả gated action (Try Pose / Capture / Gallery save-share); **Observed** Camera chặn toàn bộ `CameraScreen` ngay khi mở tab nếu chưa `hasConfirmedPremium` (`CameraScreen.kt:92-98`), không đợi shutter.
4. **`frameRatio`:** Có trong `CameraUiState` và `selectFrameRatio`, **Observed** không có user-facing control trong `CameraMorePopup` body — khớp FEAT-012 BR-004; không document ratio item.
5. **Android camera:** FEAT-001 partial — iOS evidence only.

---

## 8. Popup — `CameraMorePopup`

<a id="scr-001-01-camera-pop-more"></a>

Mở từ SCR-001-01-HDR-002; `androidx.compose.ui.window.Popup` focusable; dismiss outside → `isMoreMenuVisible = false`.

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-001-01-POP-001 | Flash row | Popup action row | Req | Cycle OFF → AUTO → ON; đóng popup sau chọn; cập nhật `cameraController.setFlashMode` — **Observed** (`848-866`) |
| 2 | SCR-001-01-POP-002 | Grid row | Popup action row | Req | Toggle grid; đóng popup; persist setting — **Observed** (`869-889`, FEAT-012) |
| 3 | SCR-001-01-POP-003 | Pose guide section header | Text | Opt | Chỉ khi `hasPoseGuide` — **Observed** (`892-894`) |
| 4 | SCR-001-01-POP-004 | Show / Hide pose guide | Popup action row | Opt | Toggle `isOverlayVisible`; không auto-close popup — **Observed** (`895-906`) |
| 5 | SCR-001-01-POP-005 | Opacity slider | `Slider` 10–100% | Opt | `overlayOpacity` 0.1f..1f; persist — **Observed** (`907-915`, FEAT-012) |
| 6 | SCR-001-01-POP-006 | Clear pose | Popup action row | Opt | `clearPose()` — gỡ overlay, giữ settings/zoom — **Observed** (`916-925`, FEAT-012 A2) |
| 7 | SCR-001-01-POP-007 | Line color Black / White | Two-option row | Opt | `PoseLineColor` toggle — **Observed** (`926-958`, FEAT-012) |

## 9. Popup — zoom slider (`CameraZoomSlider`)

<a id="scr-001-01-camera-pop-zoom"></a>

Mở từ SCR-001-01-ZOM-001; `Popup` bottom-center; dismiss → `isZoomSliderVisible = false`.

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-001-01-POP-008 | Zoom value label | Text | Req | `cameraZoomLabel(value)` — **Observed** (`667`) |
| 2 | SCR-001-01-POP-009 | Zoom slider | `Slider` | Req | Range 1f..3f; `cameraController.setZoomFactor`; `testTag=zoomSlider`; persist zoom — **Observed** (`668-672`, `411-414`, FEAT-012) |

## 10. Overlay — `PaywallScreen` (canonical)

<a id="scr-001-01-camera-ovr-paywall"></a>

**Canonical OVR** cho mọi `PaywallScreen` occurrence trên mobile. Camera: full-screen thay thế `CameraScreen` body khi `!(purchaseSnapshot.hasConfirmedPremium \|\| premiumTestBypassEnabled)` — **Observed** (`CameraScreen.kt:92-98`). Gallery save/share tham chiếu Item ID này, không duplicate bảng OVR.

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-001-01-OVR-001 | Paywall shell | Full-screen overlay | Req | `testTag=paywall`; `gateway.loadOffering()` on enter — **Observed** (`Paywall.kt:75-81`) |
| 2 | SCR-001-01-OVR-002 | Title + close | Heading + close control | Req | "Premium access"; close → `onDismiss` (Camera: exit tab context) — **Observed** (`87-96`) |
| 3 | SCR-001-01-OVR-003 | Value proposition copy | Text block | Req | Scope copy Try Pose / Camera / Gallery save-share — **Observed** (`98-99`) |
| 4 | SCR-001-01-OVR-004 | Offering / error states | Conditional content | Req | UNCONFIGURED, NO_OFFERING, loading, product cards; Retry buttons — **Observed** (`101-128`, FEAT-011 A3/E3) |
| 5 | SCR-001-01-OVR-005 | Subscribe CTA | `PrimaryButton` | Req | `gateway.purchase(selectedProduct)`; disabled khi busy/no plan — **Observed** (`131-141`, FEAT-011 E1) |
| 6 | SCR-001-01-OVR-006 | Purchase outcome message | Text | — | Cancelled / failed / confirmed premium — **Observed** (`142-145`) |
| 7 | SCR-001-01-OVR-007 | Restore purchases | `PrimaryButton` | Req | `gateway.restore()` — **Observed** (`146`, FEAT-011 A4) |
| 8 | SCR-001-01-OVR-008 | Legal links | Text buttons | Req | Terms of Use / Privacy Policy — **Observed** (`148-157`, FEAT-011 FR-005) |
