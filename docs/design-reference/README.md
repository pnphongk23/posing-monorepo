# AI Pose - Design Reference Documentation

This directory contains comprehensive design system documentation for the Compose Multiplatform migration.

## Files

### 1. `design_exploration_summary.md`
**Comprehensive design system specification**
- Color scheme analysis (Subframe vs Web app)
- Typography system mapping
- Compose theme requirements
- Component patterns from spec
- Platform-specific considerations
- Implementation checklist

**Use this for:** Understanding the overall design system and requirements

### 2. `final_design_summary.txt`
**Complete implementation reference with code examples**
- Design references found
- Color scheme with Kotlin hex values
- Typography system and TextStyle examples
- Spacing and dimensions
- Neo-brutalism component patterns with modifiers
- Animation keyframes
- Component library patterns
- Compose Multiplatform setup structure
- Quick reference design tokens table

**Use this for:** Implementation, copy-paste color/spacing values, code examples

### 3. `color_palette_visual.txt`
**Visual color palette and component styling reference**
- Main brand colors visualization
- Accent and semantic colors
- Text and neutral colors
- Badge color mapping
- Component styling examples (buttons, cards)
- Brand color interaction states
- Typography hierarchy
- Spacing reference
- Neo-brutalism visual effects

**Use this for:** Visual reference, design validation, showing stakeholders

## Quick Start

### Essential Colors
```kotlin
val brandPink = Color(0xFFE7A1B0)      // Primary brand
val bgPrimary = Color(0xFFF6F1E8)      // Background
val bgDark = Color(0xFF171717)         // Dark elements/borders
val accentBlue = Color(0xFF87CEEB)     // Secondary accent
val accentYellow = Color(0xFFF4C542)   // Tertiary
```

### Essential Spacing
```kotlin
4dp → xs (minimal)
8dp → sm (small)
12dp → md (medium)
16dp → lg (standard) ← MOST USED
24dp → xl (large)
32dp → xxl (extra large)
```

### Neo-Brutalism Signature
- Hard offset shadows: 2-6px, no blur
- Stark 2px borders in dark (#171717)
- UPPERCASE labels with 0.08em tracking
- Press effect: shadow collapses to 0px, translate 2px

## References

- **Subframe Project:** https://app.subframe.com/6f0b27e61709/design/54e0d2b4-5e3d-4793-9f09-dddb5544874b/edit
- **Web App Theme:** `src/app/globals.css`

## Implementation Phases

### Phase 1: Foundation & Design System ← YOU ARE HERE
- [ ] Initialize KMP project
- [ ] Create Theme.kt with colors, typography, shapes
- [ ] Implement button composables
- [ ] Create modifier extensions (ghostBorder, cardChrome, badgeChrome)
- [ ] Setup string resources (EN/VI)
- [ ] Create Badge, TabSwitcher, NavButton components
- [ ] Verify iOS simulator build

### Phase 2-6: See main architecture spec for details

## Key Tokens Summary

| Category | Token | Hex | Usage |
|----------|-------|-----|-------|
| Brand | Pink | #E7A1B0 | Primary buttons, accents |
| Background | Primary | #F6F1E8 | App fill |
| Background | Surface | #FAF8F3 | Cards, containers |
| Text | Primary | #171717 | Text, borders |
| Accent | Blue | #87CEEB | Secondary |
| Semantic | Success | #DFF5D0 | Positive states |
| Semantic | Error | #D42828 | Errors |

## Notes for Implementers

1. **Always use CompositionLocal** for theme access across the app
2. **Hard shadows, not soft:** Offset 4px with no blur radius
3. **Stark borders:** 2px solid #171717, no transparency
4. **Wide tracking on UI text:** 0.08em for labels and badges
5. **Touch-friendly:** Minimum 44x44dp, recommended 48x48dp
6. **iOS safe areas:** Use env constants for padding

---

Generated: 2026-04-14
Status: Phase 1 Ready for Implementation
