---
name: app-design
description: Design and polish native-feeling mobile app screens and flows. Use for onboarding, tabs, settings, paywalls, forms, sheets, empty states, navigation, motion, theming, accessibility, and perceived performance.
license: MIT
metadata:
  version: 1.0.0
---

# App Design

Build interfaces that feel intentional, native, and complete—not pages placed
inside a phone frame. Use this skill for both visual design and implementation.

## 1. Study before designing

When the screen type is common, inspect several high-quality real apps or
platform examples before writing UI code. Extract the pattern, not the pixels:

- information hierarchy and layout skeleton;
- primary action, spacing rhythm, and control choices;
- navigation/presentation grammar;
- loading, empty, error, and long-content behavior.

Adapt proven conventions to the product's voice. Do not copy a competitor 1:1
and do not ignore conventions users already understand.

## 2. Native fidelity baseline

Unless the project already specifies otherwise, assume React Native/Expo with
TypeScript. Adapt package choices to the existing stack.

- Use semantic color tokens and verify light and dark themes from day one.
- Prefer platform controls, menus, pickers, sheets, symbols, and navigation
  titles over hand-built imitations.
- Use safe-area insets; never hard-code notch or home-indicator values.
- Follow the platform type ramp and support larger text sizes. Use tabular
  numerals for values, times, and prices; make useful data selectable.
- Establish one spacing unit, one corner-radius scale, one elevation system,
  and one accent color. Use continuous corners where the platform supports it.
- Use flexbox `gap` where possible and put scroll padding in the content
  container. Use responsive dimensions rather than cached screen constants.
- Format numbers like a product (`1.4M`, `38k`, `$4.99`) and localize dates.
- Haptics are feedback, not decoration: one meaningful haptic per action,
  never on scroll or in animation loops.

## 3. Navigation is part of the design

For every destination, explicitly decide what it is and what Back means.

- Push when the user should return here; replace/dismiss when a state is
  complete or the old state must not be re-entered.
- Use a modal for a self-contained task, a sheet for a short interruption, an
  overlay for temporary context, and a system controller for share/web/photo
  picking. A multi-step task needs its own stack.
- Tabs are peer destinations with independent stacks. Full-attention flows
  such as composing, checkout, or playback belong above the tab bar.
- Preserve the user's place when authentication or a paywall interrupts an
  action; return to the initiating feature after completion.
- Block Back only for an irreversible operation in progress or unsaved work
  after asking for confirmation. Otherwise preserve edge-swipe and hardware
  Back behavior.
- Deep links should land in a meaningful stack. Hold the splash until session
  state is known; never flash the wrong route.

## 4. Avoid template-looking UI

Treat these as defaults to reject unless the product has a clear reason:

- generic purple/blue gradients, glow, glassmorphism, or decorative confetti;
- emoji used as chrome or icons;
- mixed grey families, arbitrary radii, or multiple accent hues;
- duplicate labels for the same intent;
- polished happy-path screens with missing loading, empty, or error states.

Before simulator verification, mechanically check: one accent hue, radii from
the declared scale, no emoji in chrome, no unjustified gradients, and one
label per intent.

## 5. Motion and interaction

Every animation needs a purpose: feedback, spatial continuity, state change,
clarity, or rare delight. Start with no animation when the platform default is
stronger.

- Frequent interactions (tabs, keyboard, scroll, Back) use platform behavior.
- Press feedback is subtle and quick; occasional sheets, modals, and toasts
  use standard motion. Entrances are ease-out and exits are faster.
- Touch-driven motion follows the finger and settles with a spring seeded by
  release velocity. Timing-based animation is for system-driven transitions.
- Keep gesture work on the UI thread. Animate transform/opacity where
  possible; avoid per-frame layout changes and JS callbacks during gestures.
- Make gestures interruptible and handle distance or velocity thresholds.
- Respect Reduce Motion by replacing spatial motion with cross-fades.

## 6. State and perceived performance

- Keep server state in the project's query/data layer, client state in small
  atomic stores, and ephemeral UI state local to the component.
- Prefer optimistic interaction with explicit rollback on failure.
- Use uncontrolled inputs for high-frequency typing when profiling shows
  controlled-input re-render cost.
- Virtualize growable lists, use stable keys, right-size images, and preload
  likely next-screen data on intent (such as press-in).
- Use skeletons only when content shape is known; otherwise progressively
  reveal content. Never hide partial-update work behind a full-screen spinner.
- Measure before optimizing: FPS/TTI/typing latency/re-render counts should
  be compared before and after the change. Do not prescribe memoization on
  intuition alone.

## 7. Assets

Choose one visual language per app (for example flat, collage, 3D, or
photographic), define its palette and lighting, and keep every asset in that
system. Generate at a large size and downscale; never upscale. Avoid baked-in
text, branding artifacts, halos, and mismatched backgrounds. Check assets in both
themes and keep screen-level decorative assets reasonably small.

## 8. Definition of done

- [ ] The adopted pattern and navigation presentation are documented.
- [ ] Push/modal/sheet/overlay/replace and Back behavior are correct on iOS
      and Android.
- [ ] Light/dark theme, safe areas, Dynamic Type, and contrast are checked.
- [ ] Loading, empty, error, offline, and long-content states are designed.
- [ ] Tap targets are at least 44pt, controls have native feedback, and
      Reduce Motion is respected.
- [ ] The flow has been run in a simulator/emulator, not judged from code only.
- [ ] Screenshots were inspected at normal and large text sizes; the full flow
      was recorded when motion or gestures are involved.
- [ ] Performance claims have a measurement; lists and inputs are profiled
      where relevant.

## Verification loop

1. Implement a small slice.
2. Launch on the primary simulator/emulator and inspect the actual screen.
3. Exercise controls, Back, keyboard, long text, loading/error states, and
   background/foreground transitions.
4. Record gesture-heavy flows and inspect at full speed and frame-by-frame.
5. Fix, relaunch, and repeat until no defect is found; then run the checklist
   once more on a small device and the other supported platform.
