---
schema_version: 1
type: spec
title: UI UX System
status: draft
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[product-feature-inventory]]"
  decisions: []
  plans: []
  reports: []
  rules: []
  features:
    - "[[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]"
    - "[[FEAT-002-manage-a-local-photo-gallery|FEAT-002]]"
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
  source_paths:
    - .rule/convention/neo-brutalism.md
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/theme
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/components
    - web/admin-ui/src/app/globals.css
    - docs/prototype
---

# UI UX System

## Scope

The production visual language is light neo-brutalism across Compose mobile and the Next.js admin UI. This document records shared design rules and explicitly notes places where platform tokens or screens currently diverge.

## Principles

- Use high-contrast, solid forms: 2 dp/px dark borders, opaque surfaces, and hard offset shadows.
- Interactive cards and buttons physically translate into their shadow on press; do not add ripples or soft elevation.
- Keep controls compact, legible, and direct. Show explicit loading, empty, success, and failure states rather than leaving a blank or static surface.
- Preserve platform safe areas and give icon-only controls accessible labels.
- Approved Harness Feature and specification documents are the authoritative source of truth for product behavior. Code is implementation/delivery evidence, and `docs/prototype/` is an exploratory UI visual reference. Production source files must be verified against Harness specs rather than acting as a behavior definition.

## Tokens

| Token | Compose | Web admin | Contract |
| --- | --- | --- | --- |
| Foreground/border | `#171717` | `#171717` | Shared |
| Primary pink | `#E7A1B0` | `#E7A1B0` | Shared |
| Accent blue | `#87CEEB` | `#87CEEB` | Shared |
| Warning yellow | `#F4C542` | `#F4C542` | Shared |
| Success green | `#DFF5D0` | `#DFF5D0` | Shared |
| Background | `#FAF8F3` | `#F6F1E8` | Known divergence; do not silently copy one value across platforms |
| Typeface | platform Compose default via `TextStyle` | Inter | Known divergence |
| Border | 2 dp | 2 px | Shared visual weight |
| Hard shadow | 2–4 dp typical | 2–6 px utilities | No blur |

Compose spacing uses 4, 8, 12, 16, 24, and 32 dp. Corner radii use 8, 12, 16, and pill. Components should consume `AiPoseColors`, `Spacing`, `CornerRadius`, and `AiPoseTypography`; web components should consume CSS/Tailwind theme variables instead of new literal colors.

## Interaction patterns

- Use `NeoBrutalismContainer` for pressable Compose cards/buttons so border, hard shadow, no-ripple behavior, semantics role, and pressed translation stay consistent.
- Provide `contentDescription` for meaningful icons and `testTag` for critical test targets.
- Camera keeps the preview dominant, places secondary controls around its edges, and separates the capture action from navigation.
- Gallery and pose libraries support explicit loading, empty, content, and detail states.
- Destructive actions (such as permanent deletion of local photos or personal poses) require confirmation in a dialog modal before execution.
- Pose extraction (FEAT-004) uses a dedicated visual processing screen that shows an honest estimated or indeterminate processing status (rather than a fake percentage progress meter or claiming live backend connection status) and displays an illustrative skeletal overlay animation on top of the source image. The screen must offer a clear, accessible cancel button. Error states (timeouts, pre-validation failures, missing human figures) and success states must navigate cleanly according to the defined feature flows.
- Admin secrets remain behind server-side proxy routes; UI copy must not imply client-side authentication that does not exist.

## Current inconsistencies

- Some Compose paths still use raw `Modifier.clickable`, Material `Button`, `AlertDialog`, or hard-coded dp/font values outside the shared component system.
- Mobile and web background colors differ.
- `BottomNavigation` exists but is not mounted by `App`; camera uses in-surface navigation controls instead.
- Prototype search and tab-bar designs are not proof of equivalent production behavior.
- Accessibility has labels on many icon controls, but no repository-wide audit proves dynamic type, contrast, VoiceOver order, or reduced motion coverage.

## Verification

- Verify visual styling and interaction flows for both Android and iOS targets; note that no Android build target currently exists to compile or execute the code today, so runtime checks are limited to the iOS simulator.
- Run the admin build and the existing Mobilewright camera test.
- Search for token bypasses with `rg -n 'Color\(0x|#[0-9A-Fa-f]{6}|Modifier\.clickable|elevation|\.shadow\(' mobile/composeApp web/admin-ui/src` and review each match rather than applying a mechanical rewrite.
- Validate this document and linked Features with `harness validate --all --workspace .`.
