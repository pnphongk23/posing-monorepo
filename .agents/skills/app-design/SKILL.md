---
name: app-design
description: Design, review, implement, or polish mobile screens and flows with explicit product patterns, navigation, states, visual systems, motion, performance, assets, and running-device verification.
---

# Mobile app design

Use this skill when a request changes a mobile experience—not merely when it
adds UI components. The target is a coherent, platform-aware flow that works
under real interaction and failure conditions.

## Operating contract

For any meaningful screen or flow:

1. State the user's dominant goal: `The user comes here to ___`.
2. Research comparable shipping products or platform conventions when the
   pattern is established. Extract principles and variations; do not copy
   pixels. Record the adopted pattern and why it fits.
3. Model the information hierarchy, destination relationship, Back behavior,
   and applicable state lifecycle before styling.
4. Define the smallest visual system needed by the work: semantic colors,
   spacing, shapes, typography, elevation, and iconography.
5. Define interaction and motion purpose, accessibility alternatives, and any
   performance risks.
6. Implement in the project's existing stack and conventions. Do not assume a
   framework or replace project architecture without evidence.
7. Run the real target, inspect rendered screens, exercise the flow, and fix
   observed defects. Code inspection alone is not verification.

If research, a device, a measurement, or another required tool is unavailable,
use the best available evidence and state the limitation. Never invent sources,
screenshots, device results, or performance numbers.

## Research routing

When using Mobbin, treat the filter families as research dimensions rather than
decorative refinements:

- `Screens` identifies the screen intent, `Categories` identifies the product
  domain, `UI Elements` identifies the structural component, and `Flows`
  identifies the behavior or transition.
- Start with one broad screen-pattern branch, then add the domain and UI
  element that match the product task. Run at least one contrasting domain
  branch so the conclusion is not anchored to one visual category.
- Under a constrained/free account, use the result grid for breadth and spend
  detailed opens on distinct products, interaction models, and states. Do not
  count repeated screens from the same product as independent evidence.
- Record the exact filter URL, visible result count, product/screen or flow
  name, and research date. A count or ranking is time-scoped evidence, not a
  product fact.
- After selecting a filter, verify that the URL and visible result count
  changed. If the grid is temporarily blank, wait for one load cycle before
  treating it as an empty result. Use `See similar` to branch from a strong
  anchor, not to collect near-duplicates.

Keep the Mobbin evidence log separate from the design decision: first write
what is visibly present, then derive the principle, then translate it through
the product's content model and platform behavior. The detailed workflow and
recording template live in `references/mobbin-research.md`.

## Decision rules

- Solve the task before decorating it; establish the skeleton before cards,
  colors, shadows, or effects.
- Prefer established platform behavior and system-owned controllers for sharing,
  web, photo picking, permissions, and file picking.
- Push into subordinate content; use a separate context for self-contained
  tasks; use a sheet for a short interruption; use an overlay when the underlying
  context remains relevant; replace or dismiss obsolete one-way states.
- Treat tabs as peer destinations, not sequential steps. Preserve each tab's
  context where appropriate.
- Back should work by default. Consume Back for transient local state first;
  block it only for unsaved work or a concrete integrity risk, with confirmation
  when appropriate. Preserve the initiating feature across auth, purchase, or
  permission interruptions.
- Keep remote, shared application, and local interaction state separate and
  close to the behavior that consumes it. Design applicable initial, loading,
  content, empty, error, updating, success, and offline states.
- Give every custom animation a purpose (feedback, continuity, state change,
  orientation, explanation, or rare delight). Keep frequent interactions subtle,
  make gestures interruptible, and provide a reduced-motion alternative.
- Use semantic design tokens and a coherent spacing/radius/elevation/icon system.
  Reject unexplained gradients, glow, glass effects, mixed neutral families,
  arbitrary radii, emoji-as-chrome, and duplicate labels unless product rationale
  supports them.
- Measure the exact performance problem before optimizing. Prefer visible-content
  rendering for growing collections, right-sized images, responsive input paths,
  and deferred non-critical startup work; do not claim improvement without
  before/after evidence.

## Progressive references

Read only the reference needed for the current work:

    - [Product patterns, information structure, and navigation](references/product-structure.md)
      for research artifacts, hierarchy, density, presentation semantics, and Back.
    - [Mobbin research guide](references/mobbin-research.md)
      for collection search, anchor selection, `See similar` expansion, evidence capture, and flow synthesis.
    - [Visual system, state, motion, and performance](references/visual-interaction-performance.md)
      for token rules, lifecycles, gesture behavior, reduced motion, and measurement.
- [Assets and verification](references/assets-verification.md) for art direction,
  adversarial testing, device coverage, and the completion checklist.

## Completion gate

Do not declare the work complete until the applicable items are true:

- adopted pattern, primary goal, hierarchy, and navigation semantics are explicit;
- loading, empty, error, offline, long-content, and interruption behavior are covered;
- supported themes, safe areas, large text, contrast, target sizes, and reduced motion are checked;
- custom motion and performance claims have a purpose or measurement;
- actual rendered UI and the complete flow were exercised on a running target;
- defects found during observation were fixed and re-verified.

When a criterion is not applicable, say why. When it cannot be verified, say
exactly what remains unverified.
