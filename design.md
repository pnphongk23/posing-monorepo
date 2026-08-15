# Design System: AI Pose Mobile UI

**Project ID:** N/A — local static prototype
**Source of truth:** `docs/prototype/`
**Primary token file:** `docs/prototype/styles/tokens.css`
**Visual language:** Neo-brutalist mobile interface

This document translates the current prototype tokens and component CSS into semantic design guidance. Preserve the visual tension between soft pastel fills and rigid black geometry when extending the product.

## 1. Visual Theme & Atmosphere

AI Pose is playful, tactile, and graphic rather than glossy. The interface uses a warm cream canvas, heavy black contours, flat pastel accents, and hard offset shadows to make controls feel physical and pressable.

- **Mood:** energetic, friendly, hands-on, and slightly editorial.
- **Surface treatment:** flat fills with strong outlines; do not introduce gradients, glassmorphism, blur, or soft diffuse shadows.
- **Visual hierarchy:** importance is communicated through color, uppercase typography, border weight, and shadow offset rather than large visual effects.
- **Density:** compact mobile layout with deliberate whitespace. Content is dense enough for browsing, while 16px page gutters and 16–24px section spacing prevent the screens from feeling cramped.
- **Frame:** on desktop, the 390 × 844 phone is centered on a slate desk background. At viewport widths of 480px or less, the phone frame becomes a full-bleed app surface with no outer border, radius, or shadow.

## 2. Color Palette & Roles

### Core palette

| Semantic token | Value | Role |
| --- | --- | --- |
| Warm Cream Canvas (`--nb-color-bg`) | `#FBF6EF` | Primary app background, modal surface, cream button variant, shutter tray, and navigation surfaces. |
| Ink Black (`--nb-color-border`) | `#000000` | All structural borders, hard shadows, active outlines, and key icon strokes. |
| Near-Black Text (`--nb-color-dark`) | `#121212` | Primary text, headings, button labels, and dark dropdown surfaces. |
| White Surface (`--nb-color-white`) | `#FFFFFF` | Cards, default buttons, input surfaces, camera controls, and the tab-bar pill. |
| Muted Gray (`--nb-color-gray`) | `#6B7280` | Secondary text, inactive tabs, placeholders, and less prominent metadata. |
| Light Gray (`--nb-color-light-gray`) | `#E5E7EB` | Tab dividers, low-emphasis separators, and gallery placeholders. |
| Slate Desk Backdrop | `#E2DDD5` | Desktop-only background surrounding the phone frame. On mobile it is replaced by the cream canvas. |

### Pastel accents

| Semantic token | Value | Role |
| --- | --- | --- |
| Shutter Pink (`--nb-color-accent-pink`) | `#E89CAE` | Primary actions, camera shutter, camera entry action, likes, and high-attention CTA surfaces. |
| Action Blue (`--nb-color-accent-blue`) | `#7FBBE6` | Active tabs, selected navigation item, toggles, progress fill, view selection, and secondary controls. |
| Signal Yellow (`--nb-color-accent-yellow`) | `#FED766` | Notices, camera/pose status badges, compact toolbar actions, dropdown values, and selected pose joints. |
| Success Green (`--nb-color-accent-green`) | `#B5E2B9` | Success tags, informational pills, and positive state indicators. |

### Context-specific visual colors

These colors are present in the current pose overlay and camera fallback styles but are not promoted to global tokens. Keep them scoped to those visualizations unless a future design decision promotes them:

- Camera fallback surface: `#333333`.
- Pose eyes: `#85C7F2`.
- Pose shoulders: `#F28482`.
- Pose wrists: `#7FE5F0`.
- Pose hips: `#E07A5F`.
- Modal scrim: `rgba(0, 0, 0, 0.4)`.
- Camera face-guide fill: `rgba(255, 255, 255, 0.1)`.
- Dark-dropdown separators: `rgba(255, 255, 255, 0.12)`.

Use dark text on pastel fills. Yellow is primarily a filled accent; use its text value on dark surfaces such as the camera settings dropdown rather than as a general body-text color.

### Canonical geometry and interaction tokens

| Token | Value | Meaning |
| --- | --- | --- |
| `--nb-border-width-thick` / `--nb-border-thick` | `2px` / `2px solid #000000` | Primary component contour. |
| `--nb-border-width-thin` / `--nb-border-thin` | `1.5px` / `1.5px solid #000000` | Badges, progress tracks, and secondary outlines. |
| `--nb-border-width-hairline` / `--nb-border-hairline` | `1px` / `1px solid #000000` | Dense gallery media and fine separators. |
| `--nb-shadow-offset` / `--nb-shadow` | `3px` / `3px 3px 0 #000000` | Default tactile lift. |
| `--nb-shadow-offset-small` / `--nb-shadow-small` | `1.5px` / `1.5px 1.5px 0 #000000` | Compact controls and navigation dock. |
| `--nb-shadow-offset-large` / `--nb-shadow-large` | `5px` / `5px 5px 0 #000000` | Shutter and high-emphasis controls. |
| `--nb-shadow-pressed` | `0 0 0 #000000` | Pressed state with no remaining lift. |
| `--nb-radius-phone` | `40px` | Desktop phone shell. |
| `--nb-radius-large` | `14px` | Cards, modals, viewport, and pills. |
| `--nb-radius-medium` | `10px` | Buttons, inputs, and compact surfaces. |
| `--nb-radius-small` | `6px` | Tags, badges, and banners. |
| `--nb-radius-circle` | `50%` | Circular controls and status handles. |
| `--nb-icon-stroke` / `--nb-line-stroke` | `2` / `2px` | Shared icon and pose-line stroke weight. |
| `--nb-touch-min` | `44px` | Minimum interactive touch target. |
| `--nb-z-index-base` / `--nb-z-index-overlay` | `1` / `10` | Base visuals and viewport overlays. |
| `--nb-z-index-sticky` / `--nb-z-index-dropdown` / `--nb-z-index-modal` | `20` / `100` / `200` | Dock, dropdown, and modal stacking levels. |
| `--nb-transition-fast` | `0.1s cubic-bezier(0.16, 1, 0.3, 1)` | Presses, toggles, and small state changes. |
| `--nb-transition-normal` | `0.25s cubic-bezier(0.16, 1, 0.3, 1)` | Overlay entrances and larger state changes. |
| `--nb-font-family` | System sans-serif stack | The canonical typeface family for all UI. |

## 3. Typography Rules

### Typeface

Use the system sans-serif stack for fast loading and native-feeling rendering:

```text
system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif
```

### Weight, size, and rhythm

| Token | Value | Intended use |
| --- | --- | --- |
| `--nb-font-weight-normal` | `500` | Body copy and low-emphasis supporting text. |
| `--nb-font-weight-semibold` | `600` | Reserved intermediate emphasis. |
| `--nb-font-weight-bold` | `700` | Headings, buttons, tabs, tags, nav labels, and metadata. |
| `--nb-font-size-2xs` | `10px` | Compact tags and tab-bar labels. |
| `--nb-font-size-xs` | `11px` | Captions, metadata, badges, and pose banners. |
| `--nb-font-size-sm` | `12px` | Secondary labels, progress labels, and pose names. |
| `--nb-font-size-md` | `13px` | Compact controls and search input text. |
| `--nb-font-size-base` | `14px` | Body text, buttons, and status-bar text. |
| `--nb-font-size-lg` | `16px` | Emphasized body copy. |
| `--nb-font-size-xl` | `20px` | Centered navigation titles. |
| `--nb-font-size-2xl` | `24px` | Page-level titles such as Search and Gallery. |

Line-height tokens are intentionally tight for the graphic UI: `--nb-line-height-tight: 1.15` for controls and labels, `--nb-line-height-snug: 1.25` for compact text, and `--nb-line-height-normal: 1.4` for readable body copy.

Use tracking deliberately:

- `--nb-tracking-tight: 0.02em` for headings and compact UI text.
- `--nb-tracking-label: 0.04em` for uppercase controls, tabs, tags, and metadata.
- `--nb-tracking-wide: 0.06em` for the smallest all-caps bottom-navigation labels.

Buttons, tags, nav titles, progress labels, and most navigation metadata are uppercase. The Poses toolbar tabs (`My Poses`, `Community`) intentionally use title case and a slightly larger `15px` label size.

## 4. Component Stylings

### Buttons and controls

- Default buttons are white with a `2px` solid black border, `10px` medium rounding, and a rigid `3px 3px 0 #000` shadow.
- Button labels are bold, `14px`, tightly line-spaced, uppercase, and tracked at `0.04em`.
- Every normal interactive control has a minimum `44px` touch target.
- Pressed or active controls translate by the shadow offset (`3px`) and remove the shadow, making the control appear to land on the surface.
- Square icon buttons are `44 × 44px`; circular icon buttons are `48 × 48px`.
- The shutter is a `72 × 72px` pink control with a `14px` radius and the large `5px` hard shadow.
- Use the semantic variants `pink`, `blue`, `yellow`, `green`, `white`, `cream`, and `dark`. The dark variant switches text to white.
- Compact toolbar actions retain a `44px` hit area but render a smaller `32 × 32px` inner surface. Create uses a yellow outlined surface; Search is intentionally plain and transparent.

### Cards and containers

- Standard cards use a white surface, `2px` black border, `14px` large rounding, and the regular hard shadow.
- Pose grid and pose detail cards keep the same outline and rounding but intentionally remove the shadow to keep the browsing surface calm. Pose grid cards are square; pose detail cards use a `1:1.1` aspect ratio.
- Pose masonry supports tall (`1:1.25`), square (`1:1`), and short (`1.25:1`) cards to create a controlled editorial rhythm.
- Gallery cards use cover-cropped imagery. The dense gallery variant is deliberately quieter: `1px` border, `6px` small rounding, and no shadow.
- Heart badges are pink, outlined, compact, and positioned in the top-right corner. Tags sit in the lower-left corner unless explicitly promoted to top-right.

### Inputs and forms

- Search fields use a white surface, `2px` black border, `10px` rounding, and `8px 12px` internal padding.
- Search text is bold, uppercase, `13px`, with placeholder text in muted gray.
- Switches are `48 × 26px`, white with a `1.5px` black outline and large rounding. The checked track is blue; the `16px` white circular thumb moves `20px` to the right.
- Form controls must preserve the `44px` minimum interactive area even when the visible control is smaller.

### Tabs

- Standard tabs sit above a `2px` light-gray divider. Inactive labels are muted gray; the active label is near-black.
- The active marker is a blue `4px` bar with a `1.5px` near-black outline and subtly rounded top corners.
- Toolbar tabs are content-width rather than equal-width, have a `44px` minimum height, and use `8px` horizontal padding. Keep the underline inset to the tab content.
- Tabs are navigation/filter controls, not pill buttons; their default shape is squared-off with no enclosing border or shadow.

### Tags, pills, and status

- Default tags are compact uppercase labels at `10px`, with a `1.5px` black border and `6px` rounding.
- Badge tags increase to `11px` with `6px 10px` padding and an optional `14px` icon.
- Metadata pills use `14px` rounding, `8px 12px` padding, `11px` text, and a small icon-to-label gap. Use pastel fills only when the state needs emphasis.

### Progress

- Progress is a full-width vertical stack with an `8px` label-to-track gap.
- The track is `14px` high, white, outlined in `1.5px` black, and generously rounded.
- The fill is blue and ends in an outlined circular `18px` handle. The handle has no shadow.
- The fill transition uses the normal easing curve over `1.5s`; honor reduced-motion settings by disabling the animation.

### Modals and dropdowns

- Modal overlays use a `40%` black scrim and sit at the modal z-index.
- Modals are cream, `90%` wide up to `320px`, with a `2px` black border, `14px` rounding, `16px` padding, and the regular hard shadow.
- Camera settings dropdowns are dark with white text, the same border/radius/shadow language, `180px` width, and `8px 16px` padding. Values are yellow. Use subtle white separators at `12%` opacity.
- Entrances are short vertical translations plus opacity; do not use springy or diffuse effects.

### Camera viewport and pose overlay

- Camera viewports fill the available content height, use a dark `#333333` fallback, a `2px` black border, and `14px` rounding.
- The optional camera grid is a 3 × 3 overlay using white hairlines at `30%` opacity.
- Camera controls remain high-contrast white square buttons over the image. The zoom chip is circular (`36px`); the profile/browse action is a blue `48px` circle.
- The shutter tray is cream, `110px` high, and separated from the viewport by a `2px` black top border.
- Pose overlays are visual-only and must not intercept camera gestures. Primary bones are near-black, the skeleton is blue, and the lower skeleton is yellow. Joints use black outlines with role-specific pastel fills.
- The pose banner is a dark, compact, uppercase label with white text and a `1.5px` border.

### Bottom navigation dock

- The dock is fixed inside the phone, `16px` from the sides and above the safe-area bottom inset.
- The navigation pill is white, `48px` high, outlined in `2px` black, rounded to a compact pill (`24px`), and lifted with the small hard shadow.
- The active destination is blue with a thin black outline and small hard shadow; inactive destinations use muted gray.
- The camera action sits beside the pill as a pink `48px` circle with a black outline and small hard shadow.

## 5. Layout Principles

### Frame and regions

- Design against a `390 × 844px` mobile frame.
- The phone frame uses a `2px` black border, `40px` radius, and an `8px 8px 0 #000` desktop shadow.
- The status/header region is `44px` high. The bottom home-indicator region is `24px` high, with a `120 × 4px` black indicator.
- Main content is a vertical flex region with horizontal `16px` padding and hidden scrollbars. Full-bleed camera content may opt out of that padding.
- Standard navigation bars are `52px` high with a `16px` bottom margin. Page titles align left at `24px`; detail titles remain centered at `20px`.

### Spacing scale

Use the prototype's 4px-based additive scale rather than introducing arbitrary gaps:

| Token | Value | Typical use |
| --- | --- | --- |
| `--nb-space-2xs` | `2px` | Micro offsets and compact insets. |
| `--nb-space-xs` | `4px` | Tight icon/label gaps and pose label spacing. |
| `--nb-space-sm` | `8px` | Control gaps, card metadata, and compact padding. |
| `--nb-space-compact` | `12px` | Control padding and medium-density rows. |
| `--nb-space-md` | `16px` | Page gutters, section gaps, and card padding. |
| `--nb-space-lg` | `24px` | Larger section separation and detail-card padding. |
| `--nb-space-xl` | `32px` | Major vertical separation. |

### Grids and browsing

- Pose browsing uses a two-column masonry layout with an `8px` column gap and `16px` item spacing.
- Regular two-column grids use a `16px` gap.
- Gallery dense mode uses three columns with a `3px` gap for a contact-sheet feel.
- Gallery list mode switches to one column and `16:10` media cards for scan-friendly rows.
- Preserve image aspect ratios and use `cover` cropping for gallery imagery.
- Scroll areas reserve `100px` plus the safe-area inset at the bottom so the fixed dock never obscures content.

### Layering, accessibility, and motion

- Layer order is semantic: base `1`, overlay `10`, sticky dock `20`, dropdown `100`, modal `200`.
- Keep focus-visible outlines as a `2px` blue dashed line with a `3px` offset.
- Maintain `44px` minimum touch targets and safe-area-aware bottom placement.
- Respect `prefers-reduced-motion`: collapse transitions and animations to near-instant updates and disable smooth scrolling.
- Use the fast transition (`0.1s cubic-bezier(0.16, 1, 0.3, 1)`) for press/state changes and the normal transition (`0.25s` with the same easing) for overlays and larger state changes.

## 6. Screen Composition Reference

The current prototype applies this system across these mobile compositions:

- **Poses:** toolbar tabs, two-column masonry pose cards, and the bottom dock.
- **Search:** page title, outlined search field, and the same masonry result surface.
- **Pose detail:** centered title, large white pose card, metadata pills, and pink primary CTA.
- **Camera live:** dark viewport, 3 × 3 guide grid, face guide, camera controls, and shutter tray.
- **Camera extracting:** centered extraction/progress state with the same outlined card and pastel progress treatment.
- **Camera pose overlay:** live camera viewport with non-interactive pose skeleton overlay.
- **Gallery:** page title and dense three-column capture history.

Use the prototype-only flow behavior in `docs/prototype/README.md` as interaction context, but treat this file as the visual contract. Production behavior may differ from the static demo shortcuts described there.

## 7. Implementation References

- Tokens: `docs/prototype/styles/tokens.css`
- Global layout and accessibility: `docs/prototype/styles/base.css`, `docs/prototype/styles/reset.css`
- Helpers: `docs/prototype/styles/utilities.css`
- Buttons: `docs/prototype/styles/components/button.css`
- Cards and media: `docs/prototype/styles/components/card.css`
- Navigation and dock: `docs/prototype/styles/components/nav-bar.css`, `docs/prototype/styles/components/tab-bar.css`
- Browsing surfaces: `docs/prototype/styles/components/grid.css`, `docs/prototype/styles/components/tab.css`, `docs/prototype/styles/components/tag.css`
- Camera and pose visuals: `docs/prototype/styles/components/camera-viewport.css`, `docs/prototype/styles/components/pose-overlay.css`
- Feedback and overlays: `docs/prototype/styles/components/progress.css`, `docs/prototype/styles/components/modal.css`
