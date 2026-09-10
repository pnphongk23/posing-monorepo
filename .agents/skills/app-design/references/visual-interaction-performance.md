# Visual system, state, motion, and performance

Read this reference when implementing or polishing the behavior and visual rules
of a screen or flow.

## Visual system

Define semantic tokens rather than screen-specific colors:

```text
background, secondaryBackground, primaryText, secondaryText, separator,
accent, success, warning, error, disabled
```

Keep one accent family, one coherent neutral direction, a spacing rhythm (for
example `4/8/12/16/24/32`), a small semantic radius scale, and a small set of
meaningful elevation levels. Define typography roles (display, title, heading,
body, supporting, caption, data), use stable-width digits for changing values,
and keep one icon family per surface. Make useful information selectable where
the platform supports it.

Before verification, mechanically check: accent families, neutral families,
icon families, radius values, labels for the same intent, unexplained gradients,
and emoji used as chrome icons.

## State and feedback

Keep remote state in the project's data layer, shared state narrow, and
ephemeral interaction state local. For each applicable lifecycle, define the
user-visible response:

```text
Initial → Loading → Content
                 ↘ Empty / Error
Content → Updating → Success / Error
Any applicable state → Offline
```

Use skeletons when final geometry is predictable and progressive reveal when it
is not. Empty states explain why nothing is present and what to do next. Errors
are specific, local where possible, actionable, and recoverable where possible.
Use optimistic UI only for safe, reversible actions and always define rollback.
Haptics reinforce selection, snap, success, or error; never use them continuously,
on scroll, in loops, or as the only feedback.

## Interaction and motion

Name the purpose of every custom animation: feedback, continuity, state change,
orientation, explanation, or delight. Animation intensity should fall as
interaction frequency rises: platform-default for scrolling/tabs/keyboard/Back,
subtle feedback for taps/toggles, visible standard transitions for occasional
sheets/modals/toasts, and expressive motion only for rare moments.

Touch-driven motion follows the finger and settles using release velocity;
system-driven transitions use timing. Gestures must handle distance and velocity
thresholds, remain interruptible from the current visible position, and animate
transform/opacity where possible rather than per-frame layout. Provide a
cross-fade or similarly simpler alternative for Reduce Motion.

## Performance

Use `Measure → Diagnose → Fix one cause → Re-measure`. Measure the interaction
that feels slow: startup, transition, typing, scrolling, image appearance, or
feedback latency. Do not prescribe memoization, caching, virtualization, or an
architectural rewrite without evidence that it addresses that bottleneck.

Render only what growing collections need, use stable keys and right-sized
images, keep high-frequency input work local, preload on a reliable intent
signal, and defer non-critical startup work. A performance claim requires
before/after evidence and a named budget where practical.
