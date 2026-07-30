# AI Pose Match - Mobile UI Prototype

A complete static HTML/CSS/JS mobile user interface prototype featuring a bold, playful **Neo-brutalist** design style, running directly as a standalone web application.

## 📱 Design System (Neo-brutalism)
- **Borders**: Thick `3px` solid black contours (`var(--nb-border-thick)`) and `2px` small lines (`var(--nb-border-thin)`).
- **Shadows**: Rigid, hard offset shadows (`4px 4px 0px #000`) that simulate tactile elevation.
- **Accents**: Soft pastel color tokens for visual variety:
  - Pink (`#E89CAE`) — Primaries like shutter, tries, and saves.
  - Blue (`#7FBBE6`) — Secondary filters, toggles, and tracks.
  - Yellow (`#FED766`) — Notices, warnings, and badges.
  - Green (`#B5E2B9`) — Success tags and info pills.
- **Backgrounds**: Curated cream base tone (`#FBF6EF`) contrasted against a slate desk backing (`#E2DDD5`).
- **Typography**: Responsive system sans-serif stack for fast loading without external CDNs:
  `system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif`

---

## 📂 Project Directory Structure

```text
docs/prototype/
├── index.html                  # App entry redirecting directly to Poses list
├── README.md                   # Setup details and screen inventory
├── screens/                    # Mobile Screen Views
│   ├── camera-live.html        # Camera Feed with grid, guides, settings popup, and main navigation
│   ├── camera-settings.html    # Redirects to camera live feed with settings open
│   ├── camera-extracting.html  # Joint detection progress card (0 to 78%)
│   ├── camera-pose-overlay.html# Semi-transparent pose matching skeleton aligner
│   ├── poses-list.html         # Tabbed poses inventory list with search filters and main navigation
│   ├── pose-detail.html        # Particular pose detail metrics and bookmarking
│   └── gallery.html            # Captured matches history with list/grid toggle and main navigation
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
│       ├── grid.css            # Multicolumn scrolling lists & list items
│       ├── camera-viewport.css # Grids, alignment guides, & shutter panels
│       ├── pose-overlay.css    # SVG bone line links & joint node decorators
│       └── view-toggle.css     # Gallery grid/list layout controllers
└── scripts/                    # Modular Interaction Code
    ├── icons.js                # DOM injector for reusable SVG symbol definitions
    ├── fixtures.js             # Local mock pose and matching photo catalog
    ├── button-press.js         # Accessible keyboard active button triggers
    ├── toggle.js               # Settings flash rotation & grid outline toggles
    ├── tabs.js                 # Categories filter listener bindings
    ├── progress.js             # Dynamic percentage tick-count & fill interpolation
    ├── modal.js                # Open/close overlay bindings
    ├── view-toggle.js          # Gallery grid-to-list layout swapping
    └── app.js                  # Main orchestrator initializing components
```

---

## ⚡ Interactive States Demoed
1. **Direct Mobile Prototype Flow**: Opening `index.html` loads the app directly, starting on the Poses tab. The bottom navigation bar allows switching between **Poses**, **Camera**, and **Gallery**. Detail pages (Pose Detail) and sub-flows (Extracting, Pose Overlay) use standard header back buttons.
2. **Camera Settings Popover**: Open options by tapping `...` in `camera-live.html`, or see it open by default on `camera-settings.html` (which acts as a shortcut redirect). Toggle the "Grid" switch to show/hide camera grid lines instantly.
3. **Capture Flash**: Clicking the pink shutter button triggers a visual flash blink and a mock camera shutter audio click, then seamlessly navigates to the extraction phase.
4. **Joint Extraction Meter**: Opening `camera-extracting.html` triggers a smooth progress width expansion and synchronizes the text percentage label counting from `0%` to `78%` matching the slider handle.
5. **Real-time Pose Filtering**: The `poses-list.html` parses fixtures, letting you filter between "My Poses" (e.g. Standing, Jumping, Arms Up) and "Community" (Dancing, Walking, Sitting) tabs.
6. **Live Title Search**: Type into the search bar in `poses-list.html` to filter matching stick figures dynamically.
7. **Detail Page Parameters**: `pose-detail.html` reads URL query parameters (e.g. `?id=jumping`). It extracts the corresponding SVG stick figure drawing and updates titles, author handles, and tries/saves metrics in real time.
8. **Interactive Likes & Bookmarks**: Increment detail likes, toggle bookmark ribbon styles, and tap hearts on gallery items.
9. **Gallery Layout Switcher**: Swap the layout in `gallery.html` between a 2-column card grid or wide row list mode.

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
