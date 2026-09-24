# Camera redesign notes

## Product intent

The user comes here to capture a usable pose photo with the least visual
friction possible.

The redesigned prototype makes that intent explicit: the live preview is the
dominant content, the capture action is the only primary action, and pose
selection, gallery access, camera flip, zoom, and tools remain secondary.

This work is scoped to the camera prototype. The existing search surface was
not used as a visual reference or a structural template.

## Reference study

Research was performed in Mobbin's [Camera & Scanner screen collection](https://mobbin.com/search/apps/ios?content_type=screens&sort=popularity&filter=screenPatterns.Camera+%26+Scanner), including Google Pay, Apple Home, Wise, Snapchat, Luma, LINE, Revolut, Lime, Cash App, Cal AI, Grab, Lapse, Uber, Instagram, Microsoft Copilot, Coinbase, Locket, BeReal., and Klarna.

Detailed screens inspected:

- [Google Pay scanner](https://mobbin.com/screens/9020d962-0825-49b8-947f-6e0e6e36153e)
- [Apple Home accessory scanner](https://mobbin.com/screens/e25145c0-7af1-4c26-9103-fd71e6566afd)
- [Wise ID capture](https://mobbin.com/screens/926b23ed-df57-4906-82a9-98951363936e)
- [Snapchat creator camera](https://mobbin.com/screens/cc44df5b-bab7-443b-aa72-fcd820d8f9fa)
- [Luma QR check-in](https://mobbin.com/screens/a779f7d7-ecb5-4080-8bcd-b05cc92b30d4)

### Common patterns

- Preview or scan target occupies most of the screen.
- One prominent capture/confirm action is visually unmistakable.
- Guidance stays short and contextual when the target is already clear.
- Secondary controls stay at the preview edges or in a compact sheet.
- Gallery/history and camera switching are separate from the primary capture.

### Meaningful variations

- Scanner products may use a target box and short task copy.
- ID capture uses a stricter document frame and a single instruction.
- Creator cameras expose more frequent controls around the bottom edge.
- QR/check-in flows surface the result as a contextual card after detection.

## Adopted pattern

posing uses a camera-first composition with a quiet live preview. The bottom rail keeps the thumbnail,
shutter, and camera flip in a stable position. `Choose pose` is an icon-only
image action because selecting a pose is secondary and must not compete with
capture.

Mobbin's camera examples keep frequent controls as small edge icons and use a
separate subordinate surface when the next action is browsing. The image action
opens a camera-local pose picker bottom sheet: the Camera remains the parent
context, while the sheet reuses the same pose data, two-column staggered cards,
and search behavior as the pose library. The sheet has a `Close` button in its
app bar, backdrop/Escape dismissal, and returns the selected pose to Camera
without adding a picker route to the Back stack. It is visually aligned with
the Home/Poses library without being the Home screen or routing through it.

Apple's [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)
and [Searching](https://developer.apple.com/design/human-interface-guidelines/searching)
guidance supports this scoped-task relationship: keep the parent context, make
the dismissal affordance explicit, and provide a prominent local search field.

Tools are an anchored popup menu because flash, grid, and pose-reference
settings are short local configuration tasks. It opens from More above Choose
pose, keeps the live preview visible, dismisses on outside tap or Escape, and
returns focus to More. When a pose is selected, the menu also exposes pose
visibility, opacity, line color, and clear-pose controls to match the native
`CameraMorePopup` configuration.

Scale stays quiet in its default state as the current numeric value inside a
circular card, starting at `1x`. Clicking the value reveals the slider above it;
the panel dismisses after 2 seconds of inactivity and resets that timer on slider
interaction. The reveal uses a subtle opacity/translate transition and becomes
instantaneous under reduced motion.

## Hierarchy and navigation

1. Navigation context: close Camera returns to the initiating library context.
2. Primary content: live camera preview.
3. Supporting content: zoom and latest capture.
4. Primary action: capture photo.
5. Secondary actions: choose pose, open Gallery, switch camera, open tools.

Back behavior is local-first: an open tools popup closes before Camera is
dismissed. Capturing stays on Camera, disables the shutter during the local
operation, and returns it to ready state; it does not pretend to be pose
extraction.

## States covered by the prototype

- Ready: live preview, current scale value, and capture rail.
- Scale active: slider opens above the numeric value, then auto-dismisses after 2
  seconds without interaction.
- Pose picker: `camera-live.html` opens a camera-local bottom sheet; it reuses
  visible pose-library fixtures, filters them by title, and choosing a pose
  returns to Camera without adding the picker to the Back stack. The former
  `pose-guide.html` path is a compatibility redirect that opens this sheet.
- Tools open: anchored popup with flash and grid; selected-pose sessions also
  show visibility, opacity, line color, and clear-pose controls.
- Capture feedback: disabled shutter with inline loading spinner, then a ready
  shutter and thumbnail update without a success toast.
- Permission denied: `camera-live.html?state=permission-denied` shows a blocked
  capture surface with Settings guidance.
- Preview loading: `camera-live.html?state=loading` shows a starting status.
- Capture error: `camera-live.html?state=error` shows a retry-oriented status.
- Offline: camera capture itself is local; no network state is invented here.

## Visual system

The redesign reuses the prototype token system: cream capture rail, dark
preview, pink primary shutter, blue pose action, yellow state accents, 2px
black borders, and hard tactile shadows. The new camera-only rules are scoped
under `.nb-camera-screen` so the historical pose-overlay screen is not silently
restyled.

Motion has three purposes: the hard-shadow press gives tactile feedback, the
scale panel reveal communicates a temporary state change, and the popup/spinner
transitions communicate camera state. The scale and tools reveals animate only
opacity and transform, and `prefers-reduced-motion` makes them instantaneous.

## Implementation boundary

- Layout: `screens/camera-live.html`, `screens/pose-guide.html`,
  `styles/components/camera-viewport.css`, and
  `styles/components/camera-guide.css`.
- Pose picker interaction: `scripts/guide-picker.js`.
- Camera tools, flip, and zoom simulation: `scripts/modal.js` and
  `scripts/toggle.js`.
- Capture feedback and prototype state hooks: `scripts/app.js`.

This is still a static prototype: it does not claim real camera permission,
hardware lens switching, local file persistence, or native haptics. The real
Camera feature remains governed by FEAT-001 and the native camera contract.
