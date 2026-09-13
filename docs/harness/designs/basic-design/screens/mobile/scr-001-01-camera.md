---
screen_id: SCR-001-01
screen_name: Camera
related_feature: FEAT-001
compose: CameraScreen (mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt)
status: draft
template_version: 2
canonical: false
---

# SCR-001-01 — Camera (CameraScreen)

> **Canonical screen template (v2)** — docs/harness/designs/basic-design/screens/TEMPLATE.md.
> Main surface là Camera. Pose picker, Camera Tools, Scale factor và Paywall là
> các camera-local sub-surface được ghi ở các section tương ứng.
>
> **Evidence boundary:** Harness Features/specs là contract. Native Compose là
> implementation evidence. Prototype chỉ là evidence khám phá và được ghi nhãn
> riêng.

<a id="scr-001-01-camera-camerascreen"></a>

## 1. Screen identity

| Field | Value |
| --- | --- |
| Screen ID | SCR-001-01 |
| Screen name | Camera |
| Related feature | FEAT-001 (primary); FEAT-008, FEAT-011, FEAT-012 (cross-slice) |
| Compose / Voyager | CameraScreen via CameraTab.Content() |
| Stable anchor | scr-001-01-camera-camerascreen |
| Template version | 2 |

## 2. Purpose

The user comes here to frame a subject and capture one usable local photo.
Camera is capture-first: the live preview and shutter dominate the surface;
secondary controls adjust the camera or choose a pose without leaving Camera.

The pose choice is a camera-local selection task. It reuses the Poses library's
data and visual language, including the two-column staggered cards, but it is not
Home, not the Poses screen, and not a separate guide screen.

## 3. Scope and ownership

Camera owns the mobile capture leg of FEAT-001: preview lifecycle, permission
recovery, capture coordination, the capture rail, and local capture feedback.

- FEAT-008 owns the verified pose preparation/handoff contract; Camera only
  consumes the prepared reference and renders it when valid.
- The Pose picker is a Camera-owned bottom sheet, while its pose collection is
  read from the existing Poses data contract. It does not create a second guide
  dataset.
- FEAT-011 Paywall is the canonical paid-access occurrence for Camera.
- FEAT-012 defines persisted pose/camera settings; Gallery and pose browsing/
  detail remain outside this screen's ownership.

## 4. Data contract and evidence

**Data in**

- Camera permission and lifecycle state; authorized preview frames.
- Optional verified PreparedPoseReference from Try Pose or restored state.
- Visible pose-library collection for the camera-local picker; native collection
  ownership is unresolved, while the prototype reads the shared pose fixtures.
- Camera settings snapshot: facing, flash, grid, pose overlay settings, and zoom.
- Current premium entitlement for the canonical Paywall gate.

**Data out**

- One accepted shutter request produces one persisted local Photo only after
  capture and file/metadata writes succeed.
- A valid capture updates the latest Gallery thumbnail; a failed write never
  becomes a successful capture.
- Pose selection returns a pose identity to Camera. Settings and applicable pose
  identity use the CameraSnapshot path; durable relaunch behavior remains
  unresolved in FEAT-012.

**Navigation contract**

- Camera is a standalone CameraTab surface; the main dock is hidden.
- Camera Close/Back returns to the initiating Poses/library context.
- Camera-local transient surfaces consume dismissal first. The pose picker uses
  an app-bar Close, backdrop dismissal, and Escape; Camera Tools and Scale use
  anchored popups with outside/Escape dismissal. Selecting a pose replaces the
  picker return rather than adding a picker route to Back.

**Evidence labels**

| Label | Meaning |
| --- | --- |
| **Normative** | Contract from Harness Features and docs/harness/specs. |
| **Observed** | Current native or rendered prototype evidence. |
| **Unresolved** | Conflict or behavior not yet proven end to end. |

## 5. Screen items (main surface)

<a id="scr-001-01-camera-main"></a>

Hierarchy: preview → shutter → secondary controls → local feedback.

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-001-01-PRV-001 | Camera preview | CameraPreview | Req | Render only after permission is authorized; stop on denied/restricted or inactive lifecycle — **Normative**, **Observed** native. |
| 2 | SCR-001-01-OVL-001 | Rule-of-thirds grid | CameraGridOverlay | Opt | Toggle from Camera Tools and persist where FEAT-012 applies — **Observed** native. |
| 3 | SCR-001-01-OVL-002 | Pose reference | AsyncImage overlay | Opt | Render only a verified PreparedPoseReference; invalid or missing assets remain recoverable and never render as valid — **Normative** FEAT-008/012, **Observed** native. |
| 4 | SCR-001-01-HDR-001 | Close Camera | Icon button | Req | Return to the initiating library context; local transient surfaces dismiss first — **Observed** native, **Normative** design rule. |
| 5 | SCR-001-01-HDR-002 | Camera Tools | Icon button | Opt | Open the anchored Camera Tools popup; disable while Camera is unavailable — **Observed** native/prototype. |
| 6 | SCR-001-01-HDR-003 | Choose pose | Icon-only image action | Opt | Open the camera-local Pose picker in §8. It shares Poses visual language but is not Home or a separate screen — **Observed** prototype, native route **Unresolved**. |
| 7 | SCR-001-01-ZOM-001 | Scale factor value | Circular output control | Req | Show the current value; tap opens the local Scale popup in §10 — **Observed** prototype/native, exact range **Unresolved**. |
| 8 | SCR-001-01-SHT-001 | Latest photo thumbnail | GalleryThumbnailButton | Opt | Tap opens Gallery only when Camera controls are enabled — **Normative** FEAT-001/002, **Observed** native. |
| 9 | SCR-001-01-SHT-002 | Shutter / capture | CaptureButton | Req | Enable only for authorized, preview-ready Camera; one accepted tap creates one capture identity and duplicate taps are ignored — **Normative** FEAT-001, **Observed** native. |
| 10 | SCR-001-01-SHT-003 | Flip camera | FlipShortcutButton | Opt | Switch front/back camera and preserve facing where settings restore applies — **Observed** native. |
| 11 | SCR-001-01-ST-002 | Capture in progress | Disabled shutter + spinner | Req | Capturing/Persisting disables the shutter and shows local busy feedback — **Normative/Observed**. |
| 12 | SCR-001-01-ST-003 | Capture failure/status | Inline status | Req for failure | Report persistence/native failure truthfully and keep recovery available; never claim success before a valid Photo exists — **Normative** FEAT-001. |
| 13 | SCR-001-01-ST-004 | Permission denied/restricted | Recovery overlay | Req when applicable | Stop preview, disable capture, and show Settings/request guidance; no false success — **Normative** FEAT-001 E1. |
| 14 | SCR-001-01-ST-005 | Preview loading | Loading state | Req when applicable | Keep Camera truthful until permission and preview readiness are confirmed — **Normative** lifecycle intent. |

## 6. Screen flow and feature links

<a id="scr-001-01-camera-flow"></a>

- Enter Camera → permission/recovery → preview-ready Camera.
- Preview-ready Camera → shutter → Capturing/Persisting → local Photo and
  thumbnail, or truthful inline failure.
- Choose pose → §8 Pose picker → select → Camera.
- Camera Tools → §9; Scale factor → §10; latest thumbnail → FEAT-002 Gallery.
- Close/Back from ready Camera → initiating Poses/library context.

| Transition | Target / result | Evidence and rule |
| --- | --- | --- |
| Camera entry with authorized permission | Preview-ready Camera | Shutter is enabled only when Camera reports capture readiness — **Normative/Observed**. |
| Permission denied or restricted | Recovery overlay | Preserve Camera context, disable capture, and provide recovery guidance — **Normative** FEAT-001 E1. |
| Tap SCR-001-01-HDR-003 | §8 Pose picker bottom sheet | Keep Camera as parent; do not route through Home/Poses — **Observed** prototype, native route **Unresolved**. |
| Close, backdrop, Escape, or platform Back from §8 | Camera without selection change | Dismiss the local sheet and restore focus to Choose pose — **Observed** prototype. |
| Select a pose in §8 | Camera with selected pose | Replace the picker return; verify/prepare the reference before overlay use — **Normative** FEAT-008, **Observed** prototype. |
| Tap SCR-001-01-SHT-001 | FEAT-002 Gallery | Navigate only when Camera controls are enabled — **Observed** native. |
| Tap SCR-001-01-HDR-001 | Initiating Poses/library context | Camera Close does not silently discard valid prepared state — **Observed** native/FEAT-012. |
| Camera opened without entitlement | §11 canonical Paywall | Gate semantics follow FEAT-011; exact trigger timing is **Unresolved**. |

**Feature flow links**

- FEAT-001 Main: [[FEAT-001-capture-a-photo-on-mobile#main-flow|FEAT-001 Main flow]] · [source](../../../../features/FEAT-001-capture-a-photo-on-mobile.md#main-flow). A1: [[FEAT-001-capture-a-photo-on-mobile#alternative-flows|Alternative flow]] · [source](../../../../features/FEAT-001-capture-a-photo-on-mobile.md#alternative-flows). E1/E2: [[FEAT-001-capture-a-photo-on-mobile#exception-flows|Exception flows]] · [source](../../../../features/FEAT-001-capture-a-photo-on-mobile.md#exception-flows).
- FEAT-008 Main: [[FEAT-008-use-published-poses#main-flow|FEAT-008 Main flow]] · [source](../../../../features/FEAT-008-use-published-poses.md#main-flow). A1: [[FEAT-008-use-published-poses#alternative-flows|Alternative A1]] · [source](../../../../features/FEAT-008-use-published-poses.md#alternative-flows). E1: [[FEAT-008-use-published-poses#exception-flows|Exception E1]] · [source](../../../../features/FEAT-008-use-published-poses.md#exception-flows).
- FEAT-011 A1/A6: [[FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases#alternative-flows|FEAT-011 Alternative flows]] · [source](../../../../features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md#alternative-flows). E1/E5: [[FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases#exception-flows|Exception flows]] · [source](../../../../features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md#exception-flows).
- FEAT-012 Main: [[FEAT-012-restore-pose-and-camera-settings-across-relaunch#main-flow|FEAT-012 Main flow]] · [source](../../../../features/FEAT-012-restore-pose-and-camera-settings-across-relaunch.md#main-flow). A1/A2: [[FEAT-012-restore-pose-and-camera-settings-across-relaunch#alternative-flows|Alternative flows]] · [source](../../../../features/FEAT-012-restore-pose-and-camera-settings-across-relaunch.md#alternative-flows). E1/E2: [[FEAT-012-restore-pose-and-camera-settings-across-relaunch#exception-flows|Exception flows]] · [source](../../../../features/FEAT-012-restore-pose-and-camera-settings-across-relaunch.md#exception-flows).

## 7. Traceability and unresolved items

| Item group | API / persistence | Model / implementation evidence |
| --- | --- | --- |
| SCR-001-01-PRV-001, HDR-001/002, SHT-002/003 | No Camera-owned HTTP route | CameraContract, CameraController, CameraScreen, CameraCoordinator |
| SCR-001-01-SHT-001 | Local Gallery/Photo persistence | GalleryTab, Photo, PhotoRepository |
| SCR-001-01-OVL-002, HDR-003, BS-007–014 | FEAT-008 preparation/handoff; pose collection contract not owned by Camera | PreparedPoseReference, PoseServiceLocator, FEAT-008 |
| SCR-001-01-POP-001–012 | CameraSnapshot / persisted camera settings | PersistedCameraSettings, PersistedPoseIdentity, FEAT-012 |
| SCR-001-01-OVR-001–008 | RevenueCat and premium entitlement | PurchaseGateway, PurchaseSnapshot, FEAT-011 |

**Unresolved**

1. Native presentation, data source, and verified handoff for the Pose picker.
2. FEAT-012 durable cold-relaunch restore for pose and camera settings.
3. FEAT-011 exact Camera gate timing; current native gating and feature wording
   do not fully align.
4. Android camera runtime parity for FEAT-001.

## 8. Bottom sheet — Pose picker

<a id="scr-001-01-camera-bs-pose-picker"></a>

The user comes here to choose one pose for the current Camera context. This is a
camera-local bottom sheet, not a Basic Design screen, not Home, and not a route
through the Poses screen.

The sheet consumes the existing pose-library collection and reuses its cream
surface, pose visualizations, title labels, and two-column staggered rhythm. It
has no Home dock or category tabs. The app bar uses Close, not Back. The former
pose-guide.html path is a compatibility redirect to this sheet.

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-001-01-BS-007 | Pose picker shell | BottomSheet | Req | Keep Camera visible behind a scrim; preserve the initiating Camera context — **Observed** prototype, native presentation **Unresolved**. |
| 2 | SCR-001-01-BS-008 | Pose picker app bar | Sheet app bar | Req | Title is Choose a pose; use an explicit Close action, not Back; return focus to SCR-001-01-HDR-003 — **Observed** prototype. |
| 3 | SCR-001-01-BS-009 | Search poses | Search field | Req | Visible local title search with clear action when non-empty; target is touch-safe — **Observed** prototype, native query ownership **Unresolved**. |
| 4 | SCR-001-01-BS-010 | Pose collection | Two-column staggered collection | Req | Read the visible Poses collection; use stable pose identity and no Home tabs/dock — **Observed** prototype, native data source **Unresolved**. |
| 5 | SCR-001-01-BS-011 | Pose card | Selectable pose card | Req | Show visualization and title; tap selects the pose and does not open pose detail — **Observed** prototype. |
| 6 | SCR-001-01-BS-012 | Loading / empty / error / offline | Inline state | Req when applicable | Keep the sheet recoverable, retain search context, and never fabricate an unavailable pose — **Normative** FEAT-008 principle, native UI **Unresolved**. |
| 7 | SCR-001-01-BS-013 | Dismissal | Backdrop / Escape target | Req | Close on backdrop, Escape, or local Back without changing selection; restore focus to Choose pose — **Observed** prototype. |
| 8 | SCR-001-01-BS-014 | Select pose | Card action / replace return | Req | Return pose identity to Camera without adding a picker route; only a verified reference may become an overlay — **Normative** FEAT-008, **Observed** prototype. |

State lifecycle: content is shown after the collection is available; query,
loading, empty, error, and offline states remain inside the sheet and do not
obscure the app bar.

## 9. Popup — Camera Tools

<a id="scr-001-01-camera-pop-tools"></a>

Camera Tools is a short local configuration task shown as a popup anchored to
the More button. The More button sits above Choose pose in the lower-right
camera controls. The popup preserves the live Camera context, opens upward when
space is limited, and dismisses before Camera Back is consumed. Native exposes
the same surface through `CameraMorePopup`.

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-001-01-POP-001 | Tools menu shell | PopupMenu | Req | Open from More; anchor to the lower-right More control, preserve Camera context, and expose a compact surface without a bottom-sheet scrim — **Observed** native/prototype. |
| 2 | SCR-001-01-POP-002 | Dismissal | Outside/Escape/Back | Req | Tap outside, Escape, or local Back closes the popup and restores focus to More without changing the Camera route — **Observed** native/prototype. |
| 3 | SCR-001-01-POP-003 | Flash | Setting row | Req | Cycle the supported values `Off` → `Auto` → `On` → `Off`; update the value immediately and persist where FEAT-012 applies — **Observed** native/prototype. |
| 4 | SCR-001-01-POP-004 | Grid | Toggle row | Req | Toggle the rule-of-thirds grid and update the preview immediately — **Observed** native/prototype. |
| 5 | SCR-001-01-POP-005 | Pose guide visibility | Toggle row | Opt when a pose is selected | Show or hide the selected pose reference without clearing its identity — **Observed** native/prototype. |
| 6 | SCR-001-01-POP-006 | Pose opacity | Range slider | Opt when a pose is selected | Adjust overlay opacity from 10% to 100%, defaulting to the restored snapshot value (50% when no snapshot exists) — **Observed** native/prototype. |
| 7 | SCR-001-01-POP-007 | Pose line color | Choice buttons | Opt when a pose is selected | Choose Black or White and reflect the selected state on the overlay — **Observed** native/prototype. |
| 8 | SCR-001-01-POP-008 | Clear pose | Secondary action | Opt when a pose is selected | Remove the current pose reference and its pose-specific controls; remain in Camera — **Observed** native/prototype. |

Frame ratio is passed through a native callback but is not currently rendered as
a user-facing row in `CameraMorePopup`; its product placement is **Unresolved**
and remains outside this popup contract.

## 10. Popup — Scale factor slider

<a id="scr-001-01-camera-pop-scale-factor"></a>

Scale is a local anchored popup above the numeric value. It does not change the
Camera route.

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-001-01-POP-009 | Current scale value | Output text | Req | Match the value shown by the Camera control — **Observed** prototype/native, range **Unresolved**. |
| 2 | SCR-001-01-POP-010 | Scale slider | Range slider | Req | Update scale and expose the current value to assistive technology — **Normative/Observed**. |
| 3 | SCR-001-01-POP-011 | Visibility lifecycle | Local interaction state | Req | Open on value tap; Escape/Back dismisses; restore focus to the value control — **Observed** prototype. |
| 4 | SCR-001-01-POP-012 | Reveal/dismiss motion | Opacity/transform | Req | Keep motion subtle and disable the transition under reduced motion — **Observed** prototype. |

## 11. Overlay — PaywallScreen (canonical)

<a id="scr-001-01-camera-ovr-paywall"></a>

This is Camera's canonical Paywall occurrence. Other screens cross-reference
these items instead of duplicating the Paywall contract.

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-001-01-OVR-001 | Paywall shell | Full-screen overlay | Req | Block the gated Camera operation until premium is confirmed — **Normative** FEAT-011, **Observed** native. |
| 2 | SCR-001-01-OVR-002 | Title + close | Heading + close | Req | Explain premium context; dismiss without granting access — **Normative/Observed**. |
| 3 | SCR-001-01-OVR-003 | Value proposition | Text block | Req | Explain the gated operation without implying entitlement — **Observed** native. |
| 4 | SCR-001-01-OVR-004 | Offering states | Loading/error content | Req | Handle loading, no-offering, and retryable errors truthfully — **Normative** FEAT-011. |
| 5 | SCR-001-01-OVR-005 | Subscribe | Primary button | Req | Start purchase only for a valid Account and product — **Normative** FEAT-011. |
| 6 | SCR-001-01-OVR-006 | Purchase outcome | Inline result | Req when applicable | Cancellation/failure keeps entitlement unchanged; success follows confirmation — **Normative** FEAT-011. |
| 7 | SCR-001-01-OVR-007 | Restore purchases | Button | Req | Restore the current Account entitlement without duplicate purchase — **Normative** FEAT-011. |
| 8 | SCR-001-01-OVR-008 | Legal links | Text buttons | Req | Terms and Privacy remain reachable — **Normative** FEAT-011. |

## 12. Rationale

| Quyết định | Lý do |
| --- | --- |
| Preview-first hierarchy | FEAT-001's outcome is one usable local Photo; preview and shutter therefore remain dominant. |
| Pose picker as a bottom sheet | Selection is short and contextual. Keeping Camera behind the sheet makes the parent context clear and makes Close unambiguous. |
| Camera Tools as a popup | Configuration is short and contextual. Keeping Camera visible and anchoring the menu to More preserves context without turning a small task into a full-width sheet. |
| Shared Poses language, separate surface | Reusing pose data, search, cards, and staggered rhythm gives familiarity without turning the picker into Home or Poses. |
| Minimal local feedback | Capture progress and failure stay beside the shutter so the UI does not claim success before persistence. |

### Accessibility and verification

- Reuse the shared light neo-brutalist tokens and contrast rules; maintain
  safe-area handling, large-text resilience, and touch targets of at least 44dp.
- Label Camera controls, the Pose picker dialog, search field, Close action, and
  each pose identity. Return focus to Choose pose after dismissal.
- Keep custom motion limited to sheet/popup state changes and provide a reduced
  motion path.
- The prototype was exercised for Camera ready state, Pose picker open/search/
  empty/select/close/Escape flows, legacy URL redirect, Tools, Scale, and
  capture feedback. Native presentation, Android parity, entitlement E2E, and
  cold-relaunch restore remain unverified.
