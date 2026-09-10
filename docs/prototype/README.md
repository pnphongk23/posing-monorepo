# Snap Pose Match - Mobile UI Prototype

A static HTML/CSS/JS mobile user interface prototype running directly as a standalone web application. This prototype serves as a design and layout reference. It does not connect to a real database or replicate production business flows.

## 📱 Design System (Neo-brutalism)

Canonical token values live in `styles/tokens.css` and are summarized in repo-root [`design.md`](../../design.md). Production Compose/web styling follows [`docs/harness/specs/ui-ux-system.md`](../harness/specs/ui-ux-system.md) — do not copy prototype hex values into mobile or admin without that spec.

- **Borders**: Primary `2px` solid black contours (`var(--nb-border-thick)`) and `1.5px` secondary lines (`var(--nb-border-thin)`).
- **Shadows**: Rigid, hard offset shadows (`3px 3px 0 #000` default; `1.5px` compact; `5px` large) that simulate tactile elevation.
- **Accents**: Soft pastel color tokens for visual variety:
  - Pink (`#E89CAE`) — Primaries like shutter, tries, and saves.
  - Blue (`#7FBBE6`) — Secondary filters, toggles, and tracks.
  - Yellow (`#FED766`) — Notices, warnings, and badges.
  - Green (`#B5E2B9`) — Success tags and info pills.
- **Backgrounds**: Curated cream base tone (`#FBF6EF`) contrasted against a slate desk backing (`#E2DDD5`).
- **Typography**: Exact SF Pro/system web target for fast loading without external CDNs:
  `-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", system-ui, "Segoe UI", Roboto, Helvetica, Arial, sans-serif`

---

## 📂 Project Directory Structure

```text
docs/prototype/
├── index.html                  # App entry redirecting directly to Poses list
├── README.md                   # Setup details and screen inventory
├── screens/                    # Mobile Screen Views
│   ├── camera-live.html        # Camera-first capture surface with pose framing guide and tools sheet
│   ├── pose-guide.html         # Dedicated pose-guide picker entered from Camera
│   ├── camera-settings.html    # Redirects to camera live feed with settings open
│   ├── camera-extracting.html  # Joint detection progress card (0 to 78%)
│   ├── camera-pose-overlay.html# Semi-transparent pose matching skeleton aligner
│   ├── poses-list.html         # Tabbed poses inventory list with category filters, a link to search, Account shortcut, and main navigation
│   ├── account.html            # Account overview, Premium CTA, Saved shortcut, and sign-out prototype
│   ├── search.html             # Dedicated search screen dynamically filtering mock poses by title
│   ├── pose-detail.html        # Source-aware pose detail, personal delete, and bounded handoff
│   ├── saved-list.html         # FEAT-013 Saved collection state prototype
│   ├── pose-detail-saved.html  # FEAT-013 saved detail/save/try states
│   ├── sign-in-prompt.html     # FEAT-013 shared auth gate simulation
│   ├── gallery.html            # Captured matches history with list/grid toggle and main navigation
│   ├── gallery-detail.html     # Legacy source-aware captured photo detail
│   └── gallery-detail-v2.html  # Current gallery photo detail redesign
├── styles/                     # Design System & Component Outlines
│   ├── tokens.css              # Custom properties layer (colors, spacing, radii)
│   ├── reset.css               # Normalize standard browser styling overrides
│   ├── base.css                # Universal accessibility focus & motion configurations
│   ├── utilities.css           # Helper classes (background colors, alignments)
│   ├── components.css          # Main entry aggregator for component styles
│   └── components/             # Reusable UI Patterns (BEM prefixed with `nb-`)
│       ├── button.css          # Tactile buttons with press shadow transitions
│       ├── card.css            # Image and stick figure panel frames
│       ├── tab.css             # Filter buttons with active pastel states
│       ├── toggle.css          # Accessible check slider switches
│       ├── tag.css             # Mini badges (Mine, Hot, New, Joint counts)
│       ├── progress.css        # Extraction meter with terminal handle
│       ├── modal.css           # Options popovers and dialog templates
│       ├── nav-bar.css         # Title headers and action touch targets
│       ├── grid.css            # Multicolumn scrolling lists and masonry items
│       ├── camera-viewport.css # Grids, alignment guides, & shutter panels
│       ├── pose-overlay.css    # SVG bone line links & joint node decorators
│       └── view-toggle.css     # Gallery grid/list layout controllers
│   ├── saved-poses.css         # Token-based FEAT-013 prototype additions
│   └── account.css             # Account screen layout and action styles
└── scripts/                    # Modular Interaction Code
    ├── icons.js                # DOM injector for reusable SVG symbol definitions
    ├── fixtures.js             # Local mock pose/photo catalog and session-only pose state
    ├── account.js              # Account sign-out and re-authentication simulation
    ├── button-press.js         # Accessible keyboard active button triggers
    ├── toggle.js               # Settings flash rotation & grid outline toggles
    ├── tabs.js                 # Categories filter listener bindings
    ├── progress.js             # Dynamic percentage tick-count & fill interpolation
    ├── modal.js                # Open/close overlay bindings
    ├── view-toggle.js          # Gallery grid-to-list layout swapping
    ├── app.js                  # Main orchestrator initializing components
    ├── saved-list.js            # Saved pagination and list state simulation
    ├── pose-detail-saved.js     # Saved detail mutation/auth state simulation
    └── sign-in-prompt.js        # Auth prompt intent and outcome simulation
```

---

## ⚡ Prototype Screen Inventory & Limitations

The prototype features several interactive controls. However, due to its static, serverless nature, many features operate as limited simulations or contain historical placeholders:

1. **Direct Mobile Flow**: Opening `index.html` loads the app and starts on the Poses tab. The bottom navigation bar allows switching between **Poses**, **Camera**, and **Gallery**. Header back buttons allow returning from sub-flows.
2. **Camera Tools Sheet**: Open options by tapping the tools button in `camera-live.html`. Flash cycles through Auto/On/Off, while the Grid switch toggles the composition grid. The sheet can be dismissed with the close button, backdrop, or Escape.
3. **Capture Feedback (Prototype Simulation)**: Clicking the pink shutter button disables the capture control and shows an inline loading spinner, then returns the control to its ready state and updates the latest thumbnail. No success toast is shown. This mirrors FEAT-001's capture boundary; `camera-extracting.html` remains a separate historical extraction demo.
4. **Joint Extraction Meter & Manual Save (Simulated)**: Opening `camera-extracting.html` triggers a mock progress meter animation counting from `0%` to `78%`. It also exposes a manual 'Save Pose' button to navigate back to `poses-list.html`. *Note: This is a prototype-only interaction. In the production app, the extraction is auto-saved and routes automatically to the list on completion; the prototype does not cover auto-save and deviates from this product behavior.*
5. **Camera Facing Switch (Prototype Simulation)**: The flip button stays on the Camera surface and toggles front/back labels. It represents the native facing action without claiming to flip hardware in this static prototype.
6. **Pose Guide Picker**: The image icon on Camera opens the dedicated `pose-guide.html` screen. Selecting a guide returns to Camera with a guide query parameter without leaving the picker in the Back stack; the picker does not reuse the Home/Poses list surface.
7. **Pose Library Browsing (Mock)**: `poses-list.html` keeps My Poses and Community as distinct tab states. Cards show their source, Community only shows published mock fixtures, and personal deletion is available only from My Poses.
8. **Dedicated Title Search (Mock/Deferred)**: Tapping the search icon opens `search.html`, which filters fixture titles across both sources. The screen labels community matches as illustrative mock data; a production community title-search adapter is deferred.
9. **Recoverable Library States**: Refresh briefly shows a retained-content loading state. For repeatable demonstrations, use `?state=loading`, `?state=error`, `?state=refresh-error`, or `?state=empty` on the list; search accepts the same loading/error/empty hooks. Empty and error states provide a next action or retry.
10. **Source-aware Details**: Cards route with `source` and `id` query parameters. Detail only renders metadata present in the fixture, handles missing/unavailable records with a return path, and confirms personal deletion before removing it from the current `sessionStorage` prototype session.
11. **Bounded Try Pose Handoff**: `Try Pose` records a mock handoff notice on the detail screen only. It does not navigate to or render `camera-pose-overlay.html`; Camera overlay persistence, rendering, controls, and extraction remain deferred to the pending handoff plan.
12. **Existing Camera/Gallery Shortcuts**: The standalone `camera-pose-overlay.html` and the camera-facing shortcut remain historical prototype screens outside this Pose Library update. Gallery opens the current `gallery-detail-v2.html` photo detail redesign and keeps a full uncapped staggered photo collection; `gallery-detail.html` remains available as the legacy detail reference. The gallery layout toggle remains **inert** because its buttons are missing from `gallery.html`; camera settings still use `camera-live.html?settings=open`.

### Account screen prototype

The Account screen provides the Gmail profile entry, Premium CTA, Saved poses
shortcut, and a sign-out/re-authentication simulation. It does not persist a
real auth session.

### FEAT-013 Saved Poses prototype

These screens are prototype-only visual/navigation simulations; they do not call
the Saved API, persist account data, or implement production authentication.

- [Saved list](./screens/saved-list.html): `?state=loading`, `ready`, `empty`, `error`, `refresh-error`, `load-more-loading`, `load-more-error`, `offline-stale`, or `offline-no-cache`; inspect pagination with `?page=1&limit=20`. Removed/unavailable is demonstrated on [Saved pose detail](screens/pose-detail-saved.html?id=dancing&state=unavailable), not as a list tombstone.
- [Saved pose detail](screens/pose-detail-saved.html?id=dancing): `?state=unsaved`, `pending-save`, `pending-unsave`, `error`, `offline`, `unavailable`, or the default confirmed saved state. Add `auth=guest` to gate Save/Try.
- [Sign-in prompt](screens/sign-in-prompt.html?intent=saved): use `intent=saved`, `save`, or `try`; `state=fail` simulates a retryable auth failure. Continue resumes Saved or the encoded `return` detail URL; Not now keeps the gated context.

---

## 🚀 How to Run Locally

### Method 1: Direct File Launch
Simply double click `docs/prototype/index.html` or open it from your web browser file manager (`file://` path).

### Method 2: Local HTTP Server (Recommended)
To run a local server in the project root:

```bash
# Python 3
python3 -m http.server 8000

# Node.js
npx http-server -p 8000
```
Then visit: `http://localhost:8000/docs/prototype/` in your browser.

---

## ♿ Accessibility (A11y) Focus
- Interactive bounds have a min touch target of `44px` for mobile compliance.
- Outlines use `focus-visible` styles with offset spacing for high visibility.
- Tabs, progress meters, checkboxes, and modals include semantic ARIA attributes.
- Layouts listen for `prefers-reduced-motion` media queries and skip animations when activated.
