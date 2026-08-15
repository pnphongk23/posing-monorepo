# Selected Pose Camera Handoff Design

## Approaches considered

### A — Pass image path directly through callbacks

Set Camera-local state immediately before changing tabs. This is a small change,
but tab recreation, source identity, missing community data, and clear/replace
behavior become implicit and difficult to test.

### B — Session-only app-scoped active reference store

Keep an injected store at the application/tab-navigation composition boundary.
It holds a source-qualified key plus immutable render descriptor, exposes a
state flow, and is consumed by the Camera coordinator. Detail screens dispatch
`Select(reference)` before switching tabs; Camera renders, toggles, replaces, or
clears the reference explicitly. This does not satisfy the approved relaunch
persistence requirement.

### C — Persistent active reference with managed render cache (approved)

Persist a source-qualified key plus validated immutable render descriptor and a
managed local copy of the decoded transparent pose image. This survives relaunch
without trusting remote URL lifetime. Persistence and cache updates are treated
as one recoverable operation; invalid or corrupt persisted state is cleared
without affecting Camera capture or the source pose.

## Recommended invariants

- One active reference or none; selecting a new pose replaces the previous one.
- The active reference survives app termination/relaunch until replaced or
  cleared. Clear removes persisted selection/cache only, never the source pose.
- Source-qualified identity prevents local/community ID collision and prohibits
  community deletion through the personal path.
- The existing transparent pose image is downloaded/read, decoded, placed in the
  managed cache, and durably committed before Camera navigation. Any failure
  leaves the user on detail with a recoverable error rather than showing the
  wrong overlay.
- Overlay rendering is visual-only and must not block preview gestures, shutter,
  lifecycle, or offline capture.
- Clear/toggle affects the overlay, not the underlying pose record.
- Remote URLs are not assumed permanently available or usable during relaunch.
- Camera renders at 50% default opacity. Toggle and clear use the approved
  prototype placement/presentation; overlay layout follows viewport orientation
  and preserves aspect ratio without intercepting preview or shutter input.

## Approved Maintainer choices

1. **Lifetime:** persist across app termination and relaunch until replaced or
   cleared; test this as a named FEAT-003 acceptance scenario.
2. **Render payload:** use the existing transparent pose image, not a fabricated
   vector/joint skeleton model.
3. **Community preparation:** download and decode successfully, then cache and
   commit, before navigating to Camera. Failure remains on detail with recovery.
4. **Overlay controls:** default opacity is 50%; toggle/clear placement and visual
   presentation follow the approved prototype, while documented behavior remains
   authoritative. Rotation follows viewport orientation, preserves aspect ratio,
   and does not alter Camera controls or capture.

The Camera Plan deliberately excludes selected-pose overlay behavior, so this
Plan owns integration without silently rewriting Camera capture contracts.
