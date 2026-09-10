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

> **Template v2** — `docs/harness/designs/basic-design/screens/TEMPLATE.md`.
> This slice describes the Camera surface and its camera-local sub-surfaces:
> the dedicated guide picker direction, Camera Tools bottom sheet, Scale factor
> popup, and the canonical paid-access overlay.
>
> **Evidence boundary:** Harness Features and `docs/harness/specs` define product
> behavior. Native Compose is implementation evidence. `docs/prototype/` is an
> exploratory visual/interaction reference and is labeled separately wherever it
> differs from native evidence.

<a id="scr-001-01-camera-camerascreen"></a>

## 1. Screen identity

| Field | Value |
| --- | --- |
| Screen ID | SCR-001-01 |
| Screen name | Camera |
| Related feature | FEAT-001 (primary); FEAT-008, FEAT-011, FEAT-012 (cross-slice) |
| Compose / Voyager | `CameraScreen` via `CameraTab.Content()` (`Navigation.kt:153-170`) |
| Primary user goal | The user comes here to frame a subject and capture one usable local photo. |
| Stable anchor | `scr-001-01-camera-camerascreen` |
| Template version | `2` |

## 2. Purpose

Camera is the focused capture surface for a Photographer. The live preview is
the dominant content; the shutter is the only primary action. The user may make
small camera adjustments, choose a pose guide, open Gallery, or switch the camera
without leaving the capture context.

The redesign direction is intentionally minimal:

- full-bleed preview with a lightweight framing guide;
- compact Back/Tools controls at the top edge;
- latest photo, shutter, and flip controls in a stable capture rail;
- a circular numeric Scale factor value (`1x` by default), with the slider hidden
  until invoked;
- an icon-only image action for choosing a guide;
- local inline capture progress, with no success toast.

The existing Search surface is not a visual or structural reference for this
screen. Camera research is recorded in the reusable [Mobbin research guide](../../../../../../.agents/skills/app-design/references/mobbin-research.md)
and the applied camera decisions are summarized in the [camera prototype notes](../../../../../prototype/camera-design-notes.md).

## 3. Scope and ownership

This screen owns the **mobile capture leg** of FEAT-001. It owns camera preview
lifecycle, local capture coordination, the capture rail, camera-local settings,
and recoverable permission/capture feedback.

| Area | Ownership and evidence |
| --- | --- |
| Capture and local Photo | FEAT-001; local file and `Photo` metadata through `CameraCoordinator` and `PhotoRepository` — **Normative** contract, **Observed** implementation. |
| Pose guide handoff/overlay | FEAT-008 and FEAT-012; verified `PreparedPoseReference`, overlay rendering, and snapshot settings — **Observed** with unresolved lifecycle/persistence gaps. |
| Guide selection surface | Dedicated subordinate-screen direction in `docs/prototype/screens/pose-guide.html` — **Observed prototype**; native route and library contract are **Unresolved**. |
| Gallery | FEAT-002 local gallery leg; Camera only owns the thumbnail entry — Gallery is **out-of-slice**. |
| Paid access | FEAT-011; Paywall is canonical in this file as an OVR occurrence host. |
| Search / browse | Not owned by Camera. Do not route a contextual guide choice through the old Search/Home surface. |

**Related feature status (evidence-backed):**

| Feature | Harness status | Screen evidence | Notes |
| --- | --- | --- | --- |
| FEAT-001 | approved | **Observed** — `CameraScreen`, `CameraCoordinator`, native camera contract, `PhotoRepository` | Android camera parity remains **Unresolved**. |
| FEAT-008 | draft | **Observed** — verified pose preparation, `PreparedPoseReference`, overlay UI paths | Final overlay lifecycle and account-backed saved state are not fully proven. |
| FEAT-011 | approved | **Observed** — `PaywallScreen` gates Camera before main content | Roadmap/code discrepancy remains **Unresolved**. |
| FEAT-012 | approved | **Observed** — camera snapshot load/save paths and settings state | Feature document still marks durable restore as **Unresolved**; see §7. |

## 4. Data contract and evidence

### Data in

- Camera permission and lifecycle state from `CameraController`/
  `CameraCoordinator`: `NOT_DETERMINED`, `AUTHORIZED`, `DENIED`, or
  `RESTRICTED`; foreground/background lifecycle is also observed — **Observed**.
- Native preview frames after authorization — **Normative** platform behavior,
  **Observed** through `CameraPreview`.
- Optional verified `PreparedPoseReference` from Try Pose or a restored pose
  identity — **Observed**; invalid assets must not become an active overlay.
- Camera settings snapshot: facing, flash, grid, guide visibility/opacity/line
  color, overlay offset/scale, and zoom — **Observed** in the current state and
  FEAT-012 contract. `frameRatio` has no approved user-facing control.
- Current paid-access snapshot from `PurchaseGateway` — **Observed**; an
  unentitled user is handled by the canonical Paywall overlay before main Camera.

### Data out

- Accepted shutter request starts one capture identity and transitions through
  `Capturing` and `Persisting` before a valid local `Photo` outcome — **Normative**
  FEAT-001 and **Observed** in `CameraCoordinator`.
- A successful write updates the latest thumbnail. A failed or unreadable file or
  metadata write must not be presented as a valid capture — **Normative**.
- Camera settings and, when applicable, pose identity are written to the local
  `CameraSnapshot` path — **Observed**; cold-relaunch completion remains
  **Unresolved** in FEAT-012.
- Gallery thumbnail navigation opens `GalleryTab`/FEAT-002 — **Observed**.
- Guide selection should return to Camera with the selected guide while retaining
  the initiating context. The dedicated picker and replace-style return are
  **Observed prototype** behavior, not yet a native navigation contract.

### Navigation contract

- Camera is a standalone `CameraTab` surface with the main dock hidden —
  **Observed**.
- Close/Back from the ready Camera surface returns to the initiating Poses/library
  context through `onDismiss` — **Observed**.
- Back is local-first: an open Tools sheet or Scale factor popup is dismissed
  before leaving Camera — **Normative design rule**, **Observed** for Tools/
  popup dismissal paths where implemented.
- Choosing a guide is a subordinate selection task. It must not send the user to
  Home or the Home Poses list as an intermediate destination — **Observed
  prototype direction**; native parity **Unresolved**.

### Evidence labels

| Label | Meaning in this slice |
| --- | --- |
| **Normative** | Behavior/data contract from Harness Features and `docs/harness/specs`; not inferred from code. |
| **Observed native** | Current Compose/shared/native implementation evidence; does not replace the feature contract. |
| **Observed prototype** | Rendered `docs/prototype/` exploration used to define the redesign direction. |
| **Unresolved** | Conflict, missing native route, or behavior not yet proven E2E. |

## 5. Screen items (main surface)

<a id="scr-001-01-camera-main"></a>

The visual hierarchy is: preview and framing → primary shutter → secondary
controls → local state feedback. The prototype uses 44-point touch targets with
smaller visual surfaces where possible; the circular Scale factor card is a
36-point visual card inside a touch-safe control boundary in the intended native
design.

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-001-01-PRV-001 | Camera preview | `CameraPreview` | Req | Render preview only after permission is `AUTHORIZED`; stop on denied/restricted and stop/restart with app lifecycle — **Normative** FEAT-001; **Observed native** (`CameraScreen.kt:202-209`, `262-265`). |
| 2 | SCR-001-01-OVL-001 | Framing guide | Overlay graphics | Req | Prototype uses four lightweight framing corners; native currently uses `CenterCrosshair()` when no pose is active. The guide must not intercept capture gestures — **Observed prototype/native**; exact parity **Unresolved**. |
| 3 | SCR-001-01-OVL-002 | Rule-of-thirds grid | `CameraGridOverlay` | Opt | Default is OFF in native evidence; toggle from Camera Tools and persist the setting where FEAT-012 applies — **Observed native** (`CameraScreen.kt:274-278`). |
| 4 | SCR-001-01-OVL-003 | Pose guide image | `AsyncImage` overlay | Opt | Render only a verified `PreparedPoseReference`; support pan, pinch scale, opacity, and line color without changing capture semantics — **Observed native** (`CameraScreen.kt:280-318`); FEAT-008/012 lifecycle gaps remain **Unresolved**. |
| 5 | SCR-001-01-ST-001 | Pose guide unavailable | Inline state message | Opt | Invalid/missing guide asset is recoverable, does not crash, and does not block capture; never render a broken overlay as valid — **Normative** FEAT-008/012 and **Observed native** (`CameraScreen.kt:283-285`). |
| 6 | SCR-001-01-HDR-001 | Back / close | Icon button | Req | Compact close control at the top edge; on the ready surface, `onDismiss` returns to the initiating library context. Local transient surfaces consume Back first — **Observed native** (`CameraScreen.kt:322-327`) and **Normative design rule**. |
| 7 | SCR-001-01-HDR-002 | Camera Tools | Icon button | Opt | Compact Tools control opens the Camera Tools bottom sheet; disabled while capture is in flight or permission is unavailable — **Observed native** (`CameraScreen.kt:329-354`); sheet presentation is **Observed prototype** redesign direction. |
| 8 | SCR-001-01-HDR-003 | Choose pose guide | Icon-only image action | Opt | Use an image icon with an accessible name. Tap opens a dedicated guide picker, not Home/Poses; selection returns to Camera with the selected guide — **Observed prototype** (`camera-live.html`, `pose-guide.html`); native route is **Unresolved**. |
| 9 | SCR-001-01-ZOM-001 | Scale factor value | Circular numeric card | Req | Show current numeric value only (`1x` by default) inside a circular card. Tap reveals the slider above the card; current value updates to the selected scale. Native range is `1x–3x`; prototype currently demonstrates `0.5x/1x/2x` — range parity is **Unresolved**. |
| 10 | SCR-001-01-FX-001 | Capture flash veil | Full-bleed overlay | Opt | Native currently shows a short white veil after accepted capture (`CameraScreen.kt:241-247`, `420-426`). The minimal prototype omits it; keep or remove only after native interaction approval — **Observed native/prototype divergence**. |
| 11 | SCR-001-01-SHT-001 | Latest photo thumbnail | `GalleryThumbnailButton` | Opt | Show the latest valid local photo or an empty placeholder. Tap opens Gallery when controls are enabled; do not claim a new photo until persistence succeeds — **Normative** FEAT-001/002; **Observed native** (`CameraScreen.kt:441-444`). |
| 12 | SCR-001-01-SHT-002 | Shutter / capture | `CaptureButton` | Req | Enabled only in `PreviewReady` + active lifecycle + authorized permission. One accepted tap creates one capture identity; duplicate taps are ignored — **Normative** FEAT-001; **Observed native** (`CameraCoordinator.kt:112-128`, `CameraScreen.kt:446-454`). |
| 13 | SCR-001-01-SHT-003 | Flip camera | `FlipShortcutButton` | Opt | Switch front/back camera, update the facing value, and preserve it in camera settings where restore applies — **Observed native** (`CameraScreen.kt:172-177`, `456`). |
| 14 | SCR-001-01-ST-002 | Capture in progress | Disabled shutter + inline spinner | Req | During `Capturing`/`Persisting`, disable the shutter and show local loading feedback in the shutter; restore the normal shutter after completion. The prototype has no success toast — **Observed prototype**; native state machine is **Observed** (`CameraCoordinator.kt:40-68`), exact visual parity **Unresolved**. |
| 15 | SCR-001-01-ST-003 | Capture result/error status | Inline status | Req for failure; Opt for success | Persistence or native failure is specific, truthful, recoverable, and never presents success. The redesign restores the ready shutter without a `Saved to your Gallery` toast; native currently exposes `statusText()` including `Saved` — **Normative** failure semantics, **Observed native/prototype divergence**. |
| 16 | SCR-001-01-ST-004 | Permission denied | Blocking recovery overlay | Req when denied/restricted | Disable capture and camera controls, stop preview, and show Settings/request guidance. Never claim capture success — **Normative** FEAT-001 E1; **Observed native** (`CameraScreen.kt:470-472`). |
| 17 | SCR-001-01-ST-005 | Preview loading | Loading state | Req when applicable | Camera remains in a truthful loading state until the preview is ready; do not show a usable shutter before authorization/preview readiness — **Normative** lifecycle intent; native rendering detail is **Unresolved**. |

## 6. Screen flow and feature links

### Primary flow

```text
Enter Camera
  ├─ Permission request / authorized preview
  ├─ Frame subject → Capture
  │    ├─ Capturing → Persisting → ready + thumbnail
  │    └─ Capture error → inline recovery → ready
  ├─ Choose guide → dedicated guide picker → select → Camera
  ├─ Camera Tools → bottom sheet → dismiss / Back → Camera
  ├─ Scale factor card → slider popup → adjust → Camera
  ├─ Latest thumbnail → Gallery (FEAT-002)
  └─ Close / Back → initiating Poses/library context
```

### Transition table

| Transition | Target / result | Evidence and rule |
| --- | --- | --- |
| Camera entry, permission authorized | Preview-ready Camera | Preview starts; shutter is enabled only when coordinator says `captureEnabled` — **Normative/Observed native**. |
| Camera entry, permission not determined | Native permission request | No capture until authorization — **Normative** FEAT-001. |
| Permission denied/restricted | Permission recovery overlay | Keep Camera context; Settings/request guidance; no false success — **Normative/Observed native**. |
| Tap SCR-001-01-HDR-003 | Dedicated Choose a guide screen | Do not route through Home; **Observed prototype**, native route **Unresolved**. |
| Select a guide | Camera with selected guide | Replace the picker return so Back does not reopen the picker; verified pose handoff remains governed by FEAT-008 — **Observed prototype**, native **Unresolved**. |
| Tap SCR-001-01-HDR-002 | Camera Tools bottom sheet | Short local configuration task; dismiss outside/Escape/close returns to Camera — **Observed prototype**, native currently Popup. |
| Tap SCR-001-01-ZOM-001 | Scale factor popup above numeric card | Slider is hidden by default, auto-dismisses after 2 seconds without action, and resets the timer on interaction — **Observed prototype**, native timeout **Unresolved**. |
| Tap SCR-001-01-SHT-001 | Gallery | Navigate to FEAT-002 only when controls are enabled — **Observed native**. |
| Tap SCR-001-01-SHT-002 | Capturing/Persisting | Disable shutter, show inline busy feedback, ignore duplicate taps, and preserve a truthful failure path — **Normative/Observed native**. |
| Tap SCR-001-01-SHT-003 | Facing changes | Switch native camera and update facing state — **Observed native**. |
| Tap SCR-001-01-HDR-001 from ready Camera | Initiating Poses/library context | Close does not clear the current prepared reference unless the user explicitly clears it — **Observed native/FEAT-012**. |
| Camera opened without entitlement | Canonical Paywall overlay | Main Camera items do not render until paid access is confirmed — **Observed native**, gate semantics discrepancy is recorded in §7. |

**FEAT-001 flow links:**

- Main flow: [[FEAT-001-capture-a-photo-on-mobile#main-flow|FEAT-001 Main flow]] · [FEAT-001 Main flow](../../../../features/FEAT-001-capture-a-photo-on-mobile.md#main-flow)
- Alternative A1 — Open Gallery: [[FEAT-001-capture-a-photo-on-mobile#alternative-flows|FEAT-001 Alternative A1]] · [FEAT-001 Alternative flows](../../../../features/FEAT-001-capture-a-photo-on-mobile.md#alternative-flows) (SCR-001-01-SHT-001)
- Exception E1 — Permission denied: [[FEAT-001-capture-a-photo-on-mobile#exception-flows|FEAT-001 Exception E1]] · [FEAT-001 Exception flows](../../../../features/FEAT-001-capture-a-photo-on-mobile.md#exception-flows) (SCR-001-01-ST-004)
- Exception E2 — Persistence fails: [[FEAT-001-capture-a-photo-on-mobile#exception-flows|FEAT-001 Exception E2]] · [FEAT-001 Exception flows](../../../../features/FEAT-001-capture-a-photo-on-mobile.md#exception-flows) (SCR-001-01-ST-003 / coordinator)

**FEAT-008 flow links:**

- Main flow: [[FEAT-008-use-published-poses#main-flow|FEAT-008 Main flow]] · [FEAT-008 Main flow](../../../../features/FEAT-008-use-published-poses.md#main-flow) (prepared reference handoff)
- Alternative A1 — Replace selection: [[FEAT-008-use-published-poses#alternative-flows|FEAT-008 Alternative A1]] · [FEAT-008 Alternative flows](../../../../features/FEAT-008-use-published-poses.md#alternative-flows) (guide selection direction)
- Exception E1 — Skeleton unavailable: [[FEAT-008-use-published-poses#exception-flows|FEAT-008 Exception E1]] · [FEAT-008 Exception flows](../../../../features/FEAT-008-use-published-poses.md#exception-flows) (SCR-001-01-ST-001)

**FEAT-011 flow links:**

- Main flow: [[FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases#main-flow|FEAT-011 Main flow]] · [FEAT-011 Main flow](../../../../features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md#main-flow)
- Alternative A1 — Capture/Try Pose gate: [[FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases#alternative-flows|FEAT-011 Alternative A1]] · [FEAT-011 Alternative flows](../../../../features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md#alternative-flows) (SCR-001-01-OVR-001)
- Alternative A5 — Returning Account: [[FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases#alternative-flows|FEAT-011 Alternative A5]] · [FEAT-011 Alternative flows](../../../../features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md#alternative-flows)
- Alternative A6 — Dismissal: [[FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases#alternative-flows|FEAT-011 Alternative A6]] · [FEAT-011 Alternative flows](../../../../features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md#alternative-flows) (return to Camera/initiating context)
- Exception E1/E3/E5: [[FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases#exception-flows|FEAT-011 Exception flows]] · [FEAT-011 Exception flows](../../../../features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md#exception-flows)

**FEAT-012 flow links:**

- Main flow: [[FEAT-012-restore-pose-and-camera-settings-across-relaunch#main-flow|FEAT-012 Main flow]] · [FEAT-012 Main flow](../../../../features/FEAT-012-restore-pose-and-camera-settings-across-relaunch.md#main-flow)
- Alternative A1 — Replace pose: [[FEAT-012-restore-pose-and-camera-settings-across-relaunch#alternative-flows|FEAT-012 Alternative A1]] · [FEAT-012 Alternative flows](../../../../features/FEAT-012-restore-pose-and-camera-settings-across-relaunch.md#alternative-flows)
- Alternative A2 — Clear overlay: [[FEAT-012-restore-pose-and-camera-settings-across-relaunch#alternative-flows|FEAT-012 Alternative A2]] · [FEAT-012 Alternative flows](../../../../features/FEAT-012-restore-pose-and-camera-settings-across-relaunch.md#alternative-flows)
- Exception E1/E2: [[FEAT-012-restore-pose-and-camera-settings-across-relaunch#exception-flows|FEAT-012 Exception flows]] · [FEAT-012 Exception flows](../../../../features/FEAT-012-restore-pose-and-camera-settings-across-relaunch.md#exception-flows)

## 7. Traceability and unresolved items

| Item | API / persistence | Model / implementation evidence |
| --- | --- | --- |
| SCR-001-01-PRV-001, HDR-001/002, SHT-002/003 | No mobile capture HTTP route | `CameraContract.kt`, `CameraController`, `CameraScreen.kt`, `CameraCoordinator.kt` |
| SCR-001-01-SHT-001 | None for thumbnail navigation; local gallery | `GalleryTab`; `Photo` — [models.md](../../models.md) |
| SCR-001-01-OVL-003 / HDR-003 | Try Pose/community preparation; no Camera-owned API | `PreparedPoseReference`; [FEAT-008](../../../../features/FEAT-008-use-published-poses.md); `PoseServiceLocator` |
| SCR-001-01-POP-* / SCR-001-01-BS-* | Local `CameraSnapshot` persistence | `PersistedCameraSettings`, `PersistedPoseIdentity`; [models.md](../../models.md) |
| SCR-001-01-OVR-* | RevenueCat SDK and purchase gateway | `PurchaseSnapshot`, `premium` entitlement; [FEAT-011](../../../../features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md) |
| Prototype camera surface | None; exploratory static HTML | [`camera-live.html`](../../../../../prototype/screens/camera-live.html), [`pose-guide.html`](../../../../../prototype/screens/pose-guide.html), [`camera-design-notes.md`](../../../../../prototype/camera-design-notes.md) |

**Unresolved / reconciliation register:**

1. **Native versus prototype Scale factor range:** native `CameraZoomUiState`
   clamps `zoomValue` to `1f..3f`; the current prototype demonstrates
   `0.5x/1x/2x`. Product must choose one range before native parity is accepted.
2. **Scale factor timeout:** prototype dismisses the slider after 2 seconds of
   inactivity and resets the timer on interaction. Native `CameraZoomUiState`
   only proves visibility toggle; timeout behavior is not yet proven.
3. **Camera Tools presentation:** native uses a focusable Compose `Popup`; the
   redesign direction uses a short bottom sheet with Flash and Grid. Decide the
   native presentation before implementation acceptance.
4. **Guide picker route:** native `CameraUsersButton` currently calls `onDismiss`
   toward the Poses context; the prototype uses a dedicated `pose-guide.html`
   screen and replace-style return. A native guide-library route and verified
   selection handoff are not yet proven.
5. **Capture success feedback:** native `statusText()` can expose `Saved` and the
   native composable has a capture flash veil. The minimal prototype uses an
   inline busy shutter, restores the shutter/thumbnail, and omits a success toast.
   The truthful failure contract is normative; the final success presentation is
   a design/implementation alignment item.
6. **FEAT-012 durable restore:** implementation has snapshot load/save evidence,
   while the Feature document still labels cold-relaunch restore unresolved. Do
   not mark all restore acceptance complete from this screen doc alone.
7. **FEAT-011 gate timing:** the Feature describes gated operations, while native
   `CameraScreen` currently gates the whole Camera body before rendering it.
   Confirm the approved product trigger and keep Paywall item ownership here.
8. **Frame ratio:** `frameRatio` exists in state, but no approved user-facing
   control exists and native wiring does not prove a capture preset change. It is
   excluded from the Camera Tools redesign.
9. **Android camera:** FEAT-001 has iOS/shared evidence; Android runtime parity is
   not proven.

## 8. Full-screen guide picker — design direction

<a id="scr-001-01-camera-dtl-pose-guide"></a>

This is a dedicated subordinate surface in the prototype, not a second Home
surface and not a popup. It is documented here to keep the Camera flow traceable.
It does not create a new Basic Design screen ID until the native guide-library
route is approved; all rows below are **Observed prototype** or **Unresolved**.

Prototype reference: [`pose-guide.html`](../../../../../prototype/screens/pose-guide.html).

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-001-01-DTL-001 | Back to Camera | Icon/text navigation control | Req | Returns directly to Camera and preserves the initiating Camera state — **Observed prototype**. |
| 2 | SCR-001-01-DTL-002 | Choose a guide title | Screen title | Req | Dedicated selection context; no Home tabs or Home Poses route — **Observed prototype**. |
| 3 | SCR-001-01-DTL-003 | Guide options | Selectable guide cards | Req | Show available guide choices with clear selected/available semantics; exact data source, loading, and empty states are **Unresolved native**. |
| 4 | SCR-001-01-DTL-004 | Select guide | Card/link action | Req | Select a guide, return to Camera, and do not leave the picker in the Back stack; native must still verify/prepare the guide before overlay use — **Observed prototype + Normative FEAT-008 constraint**. |
| 5 | SCR-001-01-DTL-005 | Picker failure recovery | Loading/empty/error state | Req when applicable | Do not open Camera with an invalid/unverified guide; remain recoverable in the picker or return safely to Camera — **Normative FEAT-008**, concrete native UI **Unresolved**. |

## 10. Bottom sheet — Camera Tools

<a id="scr-001-01-camera-bs-tools"></a>

Camera Tools is a short local interruption. It must preserve the live Camera
context and dismiss before Camera Back is consumed. The prototype presents a
solid, focusable sheet with a close control, backdrop dismissal, and Escape
dismissal. Native currently renders the same settings content in
`CameraMorePopup` as a focusable Popup; the bottom-sheet presentation is the
redesign direction.

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-001-01-BS-001 | Tools sheet shell | BottomSheet | Req | Opaque neo-brutalist surface; keep preview context behind a scrim; open from SCR-001-01-HDR-002 — **Observed prototype**, native presentation **Unresolved**. |
| 2 | SCR-001-01-BS-002 | Backdrop dismissal | Full-surface dismiss target | Req | Tap outside closes the sheet and returns to Camera without changing settings — **Observed prototype**. |
| 3 | SCR-001-01-BS-003 | Sheet close | Compact close control | Req | Close returns focus to Camera Tools and restores Camera context — **Observed prototype**; native Popup has focusable dismissal **Observed**. |
| 4 | SCR-001-01-BS-004 | Flash | Setting row | Req | Cycle `Auto → On → Off`/platform-equivalent, reflect the current value, update the camera controller, and persist when in restore scope — **Observed native** (`CameraScreen.kt:149-152`, `CameraMorePopup`). |
| 5 | SCR-001-01-BS-005 | Grid | Toggle row | Req | Toggle rule-of-thirds grid, update the preview immediately, and persist the setting where FEAT-012 applies — **Observed native** (`CameraScreen.kt:158-162`, `274-278`). |
| 6 | SCR-001-01-BS-006 | Pose-overlay advanced settings | Out-of-surface settings | Opt | Native currently exposes guide visibility, opacity, clear, line color, and developer-only ratio paths in `CameraMorePopup`; the minimal redesign does not place them in this sheet until their information architecture is approved — **Observed native / Unresolved design scope**. |

## 12. Popup — Scale factor slider

<a id="scr-001-01-camera-pop-scale-factor"></a>

The Scale factor control is a lightweight anchored popup above the circular
numeric value card. It is local to Camera and should not change the Camera route.
The popup is hidden in the ready state and appears only after the user taps the
value card.

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-001-01-POP-008 | Current scale value | Output text | Req | Show the same numeric value as the card (`0.5x`, `1x`, or `2x` in the prototype; native currently formats `1x–3x`) — **Observed prototype/native**, range parity **Unresolved**. |
| 2 | SCR-001-01-POP-009 | Scale slider | Range `Slider` | Req | Change scale continuously or by the approved discrete steps, update the preview/controller, and expose the current value to assistive technology — **Normative design requirement**, **Observed native** `CameraZoomSlider` (`CameraScreen.kt:646-674`). |
| 3 | SCR-001-01-POP-010 | Temporary visibility lifecycle | Local interaction state | Req | Open on card tap; reset a 2-second inactivity timer on slider action/focus/keyboard input; dismiss after no action; restore focus to the card; Escape/Back dismisses immediately — **Observed prototype**, native timeout **Unresolved**. |
| 4 | SCR-001-01-POP-011 | Reveal and dismiss motion | Opacity/transform transition | Req | Use a subtle `opacity + translate/scale` transition for a frequent control; make it interruptible and instantaneous under `prefers-reduced-motion` — **Observed prototype**, aligned with UI/UX motion rules. |

## 14. Overlay — `PaywallScreen` (canonical)

<a id="scr-001-01-camera-ovr-paywall"></a>

This is the canonical Paywall occurrence for Camera and for cross-referenced
mobile save/share gates. Camera replaces its main body with this overlay when
the current Account has not confirmed the `premium` entitlement. Gallery and
Pose Detail must cross-reference these items rather than duplicate them.

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-001-01-OVR-001 | Paywall shell | Full-screen overlay | Req | Blocks Camera until paid access is confirmed; `testTag=paywall` and offering load on enter — **Observed native** (`CameraScreen.kt:92-98`, `Paywall.kt:75-81`). |
| 2 | SCR-001-01-OVR-002 | Title + close | Heading + close control | Req | Show Premium access context; dismiss returns to the prior Camera/initiating context without granting access — **Normative** FEAT-011 A6; **Observed native**. |
| 3 | SCR-001-01-OVR-003 | Value proposition | Text block | Req | Explain the gated Camera/Try Pose/save-share value without implying access before entitlement confirmation — **Observed native** (`Paywall.kt:98-99`). |
| 4 | SCR-001-01-OVR-004 | Offering/loading/error states | Conditional content | Req | Handle loading, unconfigured/no-offering, and retryable offering errors; never fabricate a plan or entitlement — **Normative** FEAT-011 A3/E5; **Observed native**. |
| 5 | SCR-001-01-OVR-005 | Subscribe CTA | Primary button | Req | Start purchase only for a valid signed-in Account and selected product; disable while busy/no plan — **Normative** FEAT-011; **Observed native** (`Paywall.kt:131-141`). |
| 6 | SCR-001-01-OVR-006 | Purchase outcome | Inline result text | Req when outcome exists | Cancellation/failure keeps entitlement unchanged and offers truthful retry; confirmed purchase resumes the gated operation only after confirmation — **Normative** FEAT-011 E1. |
| 7 | SCR-001-01-OVR-007 | Restore purchases | Primary/secondary button | Req | Restore the current signed-in Account entitlement without creating a duplicate purchase — **Normative** FEAT-011 A4; **Observed native** (`Paywall.kt:146`). |
| 8 | SCR-001-01-OVR-008 | Legal links | Text buttons | Req | Terms of Use and Privacy Policy are reachable and do not imply a client-side entitlement authority — **Normative** FEAT-011 FR-005; **Observed native** (`Paywall.kt:148-157`). |

## 15. Rationale

| Quyết định | Lý do |
| --- | --- |
| Preview-first hierarchy | FEAT-001's outcome is one usable photo; the preview must remain the dominant decision surface. This also follows the shared UI/UX camera pattern. |
| Dedicated guide picker | Choosing a guide is a self-contained browse/selection task. Routing through Home would break Camera context and make Back ambiguous. The prototype proves the desired flow; native route remains a delivery item. |
| Circular numeric Scale factor card | The current scale is useful feedback, but the slider is not needed on every frame. The card preserves the value while keeping the ready Camera quiet. |
| Two-second temporary slider | Scale is a frequent but secondary adjustment. A short timeout keeps the preview unobstructed; resetting on input prevents dismissal during active adjustment. |
| Tools as a sheet | Flash and Grid are short settings. A local sheet keeps the initiating Camera visible and gives Back a predictable local-first behavior. |
| Inline capture progress, no success toast | The shutter owns the capture lifecycle. Disabling it prevents duplicate capture; a local spinner is honest progress feedback, while a generic success toast adds noise and can claim success before persistence is verified. |
| Prototype/native evidence separation | The prototype explores hierarchy and motion. Normative capture, permission, entitlement, data, and lifecycle semantics remain governed by FEAT-001/008/011/012 and the canonical specs. |

### Visual, motion, and accessibility contract

- Reuse the shared light neo-brutalist language: opaque surfaces, 2px/dp dark
  borders, hard offset shadows, one accent family, and platform system type —
  **Normative** [`ui-ux-system.md`](../../../../specs/ui-ux-system.md).
- Keep the preview full-bleed inside safe areas. Top controls use a minimum 44dp
  touch target with a smaller visual card; the Scale factor card is visually
  circular and must retain a touch-safe hit area in native implementation.
- Use meaningful `contentDescription`/accessibility labels for Close, Tools,
  Choose guide, Gallery, Capture, Flip, and the Scale factor value. The image
  icon must not be exposed as an unlabeled decorative control.
- Expose the slider's current numeric value and range to VoiceOver/TalkBack;
  expose `Saving photo`/equivalent during capture busy state and keep the failure
  message actionable.
- The Scale factor reveal is a frequent interaction: animate only opacity and
  transform with a subtle timing; do not animate per-frame layout. Under reduced
  motion, show/hide without the transform transition.
- Start/stop native preview with permission and app lifecycle; do not process or
  persist frames merely to render the UI. Capture and persistence remain behind
  `CameraCoordinator` ports.

### Verification boundary

The static prototype was exercised in a running browser for the ready Camera,
dedicated guide picker, Tools sheet, Scale factor open/close lifecycle, slider
value update, capture busy state, and no-success-toast behavior. This is
**Observed prototype** evidence only. Native iOS Compose verification, Android
camera parity, entitlement E2E, and cold-relaunch restore acceptance remain
separate verification work and are not claimed by this document.
