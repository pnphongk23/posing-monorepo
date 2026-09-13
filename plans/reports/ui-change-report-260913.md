---
report_id: UI-CHANGE-260913
title: Prototype UI change report — Snap Pose
date: 2026-09-13
status: draft
scope: docs/prototype and related Basic Design documentation in the current worktree
---

# Prototype UI change report — Snap Pose

## 1. Executive summary

This report consolidates the UI changes made in the current worktree. The
changes are prototype and design-document changes only; no production Compose
or backend implementation was changed.

The work has four main outcomes:

1. Camera is now a capture-first surface with a camera-local pose picker sheet
   and an anchored Camera Tools popup.
2. The pose library is now one `Poses` collection: no `My poses` tab, `Create
   Pose` action, or visible pose count.
3. The former standalone `pose-guide.html` is now a compatibility redirect to
   the Camera pose picker.
4. Empty, loading, offline, warning, success, and recoverable error states use
   one shared prototype component across the relevant screens.

## 2. Screen-to-Basic-Design mapping

Each prototype surface below has one owning Basic Design reference. A row marked
`shared slice` has no standalone `basic-design/screens/scr-*` file yet; the
linked design document is the current canonical reference and the gap is called
out rather than inventing a new screen contract.

| Prototype screen / surface | Consolidated UI change | One Basic Design reference |
| --- | --- | --- |
| Home / app-entry shell | Documented the current root composition as `App → PosesTab → PosesListScreen → PosesScreen + MainDock`; no separate `HomeScreen` is invented. | [SCR-000-01 Home](../../docs/harness/designs/basic-design/screens/scr-000-01-home.md#scr-000-01-home-posestab-poseslistscreen-posesscreen) |
| [`camera-live.html`](../../docs/prototype/screens/camera-live.html) | Camera hierarchy, pose overlay, More placement, Camera Tools popup, and capture-local behavior updated. | [SCR-001-01 Camera](../../docs/harness/designs/basic-design/screens/mobile/scr-001-01-camera.md#scr-001-01-camera-camerascreen) |
| [`pose-guide.html`](../../docs/prototype/screens/pose-guide.html) | Removed as an independent guide screen; redirects to the Camera pose picker. | [SCR-001-01 Camera — Pose picker](../../docs/harness/designs/basic-design/screens/mobile/scr-001-01-camera.md#scr-001-01-camera-bs-pose-picker) |
| [`poses-list.html`](../../docs/prototype/screens/poses-list.html) | Visible title is `Poses`; removed `My poses`, `Community` tabs, `Create Pose`, and visible count; kept the staggered published-pose collection. | [SCR-003-01 Poses](../../docs/harness/designs/basic-design/screens/scr-003-01-community-browse.md#scr-003-01-community-browse-poseslistscreen-posesscreen) |
| [`search.html`](../../docs/prototype/screens/search.html) | Search states now use the shared state component; query, filter, result, no-match, loading, offline, and retry feedback remain local to Search. | [SCR-003-02 Search](../../docs/harness/designs/basic-design/screens/scr-003-02-search.md#scr-003-02-search-searchscreen) |
| [`pose-detail.html`](../../docs/prototype/screens/pose-detail.html) | Unavailable-pose presentation now uses the shared recoverable error state and returns to `Poses`. | [SCR-003-03 Pose Detail](../../docs/harness/designs/basic-design/screens/scr-003-03-pose-detail.md#scr-003-03-pose-detail-posedetailscreen) |
| [`gallery.html`](../../docs/prototype/screens/gallery.html) | Empty gallery/filter states now use the shared component; the all-photos empty state can open Camera. | [SCR-002-01 Gallery](../../docs/harness/designs/basic-design/screens/mobile/scr-002-01-gallery.md#scr-002-01-gallery-galleryscreen) |
| [`gallery-detail-v2.html`](../../docs/prototype/screens/gallery-detail-v2.html) | Missing/deleted photo states now use the shared state component while preserving the media placeholder geometry. | [SCR-002-01 Gallery](../../docs/harness/designs/basic-design/screens/mobile/scr-002-01-gallery.md#scr-002-01-gallery-galleryscreen) |
| [`gallery-detail.html`](../../docs/prototype/screens/gallery-detail.html) | Unavailable-photo state now uses the shared error state with a return-to-Gallery action. | [SCR-002-01 Gallery](../../docs/harness/designs/basic-design/screens/mobile/scr-002-01-gallery.md#scr-002-01-gallery-galleryscreen) |
| [`saved-list.html`](../../docs/prototype/screens/saved-list.html) | Loading, initial error, offline, empty, refresh error, load-more loading/error, and retry states now share one component. | [FEAT-013 Saved list design](../../docs/harness/designs/feat-013-saved-poses/saved-list.md) *(shared slice)* |
| [`pose-detail-saved.html`](../../docs/prototype/screens/pose-detail-saved.html) | Unavailable and Saved mutation-error states now share the same state surface. | [FEAT-013 Pose detail/auth design](../../docs/harness/designs/feat-013-saved-poses/pose-detail-auth.md) *(shared slice)* |
| [`account.html`](../../docs/prototype/screens/account.html) | Signed-out feedback now renders through the shared success state. | [Basic Design screen inventory — FEAT-014 mapping](../../docs/harness/designs/basic-design/screens/README.md#feature-mapping) *(no dedicated Account screen)* |
| [`sign-in-prompt.html`](../../docs/prototype/screens/sign-in-prompt.html) | Sign-in failure and retry now render through the shared error state. | [FEAT-013 Pose detail/auth design](../../docs/harness/designs/feat-013-saved-poses/pose-detail-auth.md) *(shared auth slice)* |

## 3. Detailed changes by screen

### 3.1 Home / app-entry shell

The Home contract was added because the repository has an app-entry shell but no
production `HomeScreen` or `HomeTab` class. The Basic Design now documents the
shell without duplicating the Poses catalogue.

- Root mapping: `App()` → `PosesTab` → `PosesListScreen` → `PosesScreen` +
  `MainDock`.
- The visible collection is `Poses`; its published catalogue remains owned by
  FEAT-003 / SCR-003-01.
- Search, Saved, Settings, Gallery, Camera, and Pose Detail are documented as
  owner handoffs rather than Home-owned business behavior.
- `Create Pose` is intentionally not part of the current Home/Poses surface.
  FEAT-004 remains out-of-slice until its entry point is decided.
- The prototype/native title mismatch is recorded: prototype/basic-design uses
  `Poses`, while native evidence still exposes `Community`.

Files:

- New: [`scr-000-01-home.md`](../../docs/harness/designs/basic-design/screens/scr-000-01-home.md)
- Updated: [`basic-design/README.md`](../../docs/harness/designs/basic-design/README.md)
- Updated: [`screens/README.md`](../../docs/harness/designs/basic-design/screens/README.md)

### 3.2 Camera — `camera-live.html`

#### Main surface

- Removed the static four-corner framing overlay from the live preview and from
  its camera-specific CSS/documentation.
- Kept the live preview, shutter, thumbnail, zoom, and flip controls as the
  primary capture hierarchy.
- Moved the More/Camera Tools button from the top-right controls to the lower
  right, immediately above the Choose pose button.
- Changed the Choose guide action into a Camera-local Choose pose button.
- Added a pose reference overlay that renders the selected fixture pose with
  configurable visibility, opacity, and line color.

#### Camera Tools popup

The former full-width bottom sheet is now a compact anchored popup opened from
More. It has no sheet handle, app-bar Close button, or modal scrim.

Controls included:

- Flash: `Off` → `Auto` → `On` → `Off`.
- Grid: rule-of-thirds toggle.
- Pose guide: show/hide selected pose.
- Opacity: 10–100%, default 50% in the prototype.
- Line color: Black or White.
- Clear pose: removes the selected reference and pose-specific controls.

Dismissal is outside tap, Escape, or local Back, with focus returned to More.
The popup remains hidden when no pose is selected except for the general Flash and
Grid controls.

#### Pose picker bottom sheet

- Camera remains visible behind the sheet as the parent context.
- Sheet is taller, uses a Close action in its app bar, and has no Back button.
- Reuses the Poses data/visual language: local title search and two-column
  staggered cards.
- Supports loading, no-match/empty, error/retry, offline, clear-search, and
  selection states.
- Selecting a pose returns directly to Camera using `pose` and `source` query
  parameters; it does not create a picker route in the Back stack.

Related files:

- [`camera-live.html`](../../docs/prototype/screens/camera-live.html)
- [`camera-viewport.css`](../../docs/prototype/styles/components/camera-viewport.css)
- [`camera-guide.css`](../../docs/prototype/styles/components/camera-guide.css)
- [`modal.js`](../../docs/prototype/scripts/modal.js)
- [`guide-picker.js`](../../docs/prototype/scripts/guide-picker.js)
- [`app.js`](../../docs/prototype/scripts/app.js)
- [`camera-design-notes.md`](../../docs/prototype/camera-design-notes.md)
- [`scr-001-01-camera.md`](../../docs/harness/designs/basic-design/screens/mobile/scr-001-01-camera.md)

#### Explicit boundary

Native evidence passes a frame-ratio callback but does not currently render a
frame-ratio row in `CameraMorePopup`; this remains unresolved and was not
invented in the prototype popup.

### 3.3 Former guide screen — `pose-guide.html`

The former standalone guide chooser was removed from the visual/navigation
contract. The file now provides a compatibility redirect to
`camera-live.html?guide-picker=open`, so old links still land in the Camera pose
picker. It has no separate Basic Design screen identity.

### 3.4 Poses library — `poses-list.html`

- Header now shows one title: `Poses`.
- Removed the `My poses` / `Community` tablist.
- Removed the `Create Pose (+)` toolbar action.
- Removed the visible `23 poses`/catalogue count.
- The grid remains a two-column staggered collection of published Community
  fixtures, presented as the single visible Poses collection.
- Removed category-switching logic and personal-collection rendering from this
  screen.
- Empty state no longer offers a personal Create CTA; it explains that poses
  will appear when available.
- Pose detail returns to the Poses list rather than a removed tab query.

### 3.5 Search — `search.html`

Search keeps its own discovery/result surface and mixed-source filter behavior,
but all transient states now use the shared state renderer:

- loading hides the result grid and announces progress;
- error keeps the query and offers retry;
- no-match hides the grid and gives concise recovery copy;
- offline keeps available results and explains freshness;
- result count remains contextual to Search and is not the removed Poses-list
  catalogue count.

### 3.6 Pose Detail — `pose-detail.html`

- Unavailable pose content is rendered by the shared error state.
- The recovery action is `Return to Poses`.
- Existing metadata, Try Pose, delete behavior, and detail ownership remain in
  place.
- The existing Basic Design file was retained; only its cross-reference to the
  canonical Camera Paywall section was updated when Camera section numbering was
  normalized.

### 3.7 Gallery surfaces

The three prototype gallery surfaces share the Gallery Basic Design reference:

- `gallery.html`: filter-empty and all-gallery-empty states use the shared
  component; the all-gallery state provides `Open Camera`.
- `gallery-detail-v2.html`: missing/deleted photo states use the shared
  component and preserve the existing image-placeholder visual geometry.
- `gallery-detail.html`: unavailable detail uses the shared error state and
  returns to Gallery.

The existing Gallery design remains the owner of list/detail/delete behavior;
these changes standardize state presentation rather than creating a new Gallery
flow.

### 3.8 Saved and auth surfaces

- `saved-list.html`: initial/loading/error/offline/empty/refresh/load-more states
  use the same component and consistent Retry/Browse/Load more actions.
- `pose-detail-saved.html`: unavailable pose and failed save/unsave update states
  use the same component while preserving the Saved detail actions.
- `account.html`: signed-out feedback is a shared success state.
- `sign-in-prompt.html`: failed Google sign-in is a shared error state with
  Retry; the existing auth navigation is unchanged.

These are shared FEAT-013/FEAT-014 surfaces, not newly invented standalone
Basic Design screen IDs.

## 4. Shared UI component and state rules

### `nb-empty-state`

Added [`empty-state.js`](../../docs/prototype/scripts/empty-state.js) and
[`empty-state.css`](../../docs/prototype/styles/components/empty-state.css).
The component exposes:

- `<nb-empty-state>` as the reusable element;
- `window.NBEmptyState.render(target, options)`;
- `window.NBEmptyState.clear(target)`.

Supported tones are `empty`, `error`, `loading`, `offline`, `success`, and
`warning`. The renderer owns title/copy/action structure, safe text insertion,
state classes, `role`, `aria-live`, `aria-atomic`, and hidden/clear behavior.
Actions can be buttons or links. Media-specific placeholders can preserve a
marked visual while adopting the shared text/state semantics.

The shared stylesheet is imported by
[`components.css`](../../docs/prototype/styles/components.css) and uses new
error/warning/success surface tokens in
[`tokens.css`](../../docs/prototype/styles/tokens.css). The old state-message
rules were removed from [`grid.css`](../../docs/prototype/styles/components/grid.css)
to prevent duplicate ownership.

## 5. Basic Design/documentation changes

- Added the Home screen contract and added it to the Basic Design inventory.
- Renamed SCR-003-01 from `Community Browse` to `Poses` at the visible-screen
  level; retained the Community API/model wording where it is evidence.
- Removed SCR-003-01 Create Pose and count items to match the current Poses UI.
- Rewrote the Camera Basic Design around one main Camera surface plus a Camera
  pose-picker bottom sheet, Camera Tools popup, Scale popup, and canonical
  Paywall overlay.
- Recorded Camera Tools as popup rather than bottom sheet, including the full
  native-observed pose configuration.
- Normalized Camera sub-surface section numbering to the template order:
  §8 Pose picker, §9 Camera Tools, §10 Scale, §11 Paywall, §12 Rationale.
- Updated Gallery/Pose Detail cross-references from the old Paywall section number
  to §11.
- Updated prototype README and camera notes so the current navigation and popup/
  sheet semantics are not described as the former standalone guide flow.

## 6. Verification and boundaries

Verified in the current worktree:

- `node --check` passes for `app.js`, `modal.js`, and `toggle.js`.
- `git diff --check` passes; no trailing-whitespace findings in the new/changed
  design documents.
- `srcwalk deps` resolves Home, Camera, and Pose Detail design links with no
  external/unresolved local dependencies.
- Fresh local-browser render shows Camera Tools as an accessible popup menu with
  Flash, Grid, Pose guide, opacity, line color, and Clear pose; More is above
  Choose pose.
- Fresh local-browser render shows the Poses title with no My poses, Community
  tab, Create Pose, or `poses-count-label`.
- Fresh camera and Poses tabs report no browser console errors or warnings.

The repository-wide `harness validate --all` command still reports two unrelated
pre-existing unresolved source paths:

- `.agents/skills/mobile-mcp-iphone-testing`
- `TODO.md`

Those paths are outside this UI change set. Native production behavior, Android
parity, frame-ratio presentation, and durable cold-relaunch settings restore
remain unresolved unless separately implemented and verified.

