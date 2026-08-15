# Camera Design and Brainstorm

## Exact requirements

- **Expected output:** an iOS Camera screen whose behavior follows approved
  Harness documents and whose visual/interaction states match the reconciled
  prototype, with real-iPhone evidence.
- **Acceptance:** FEAT-001 FR-001 through FR-006, BR-001, NFR-001, lifecycle and
  persistence failure cases, plus an approved parity matrix with no unexplained
  app/prototype divergence.
- **Explicit exclusions:** video, cloud backup, Android implementation in the
  recommended slice, pose extraction, and selected-pose overlay behavior owned
  by FEAT-003.
- **Non-negotiable constraints:** offline capture; iOS 15+; no duplicate capture;
  one readable file plus one metadata record or complete compensation; no app
  implementation treated as authority; real iPhone for physical Camera claims.
- **Affected touchpoints:** Camera Compose UI/state/contract, iOS native bridge,
  local image/database lifecycle, prototype Camera artifacts, tests and
  accessibility semantics.

## Authority model

Recommended precedence:

1. Approved FEAT-001 and linked specs own behavior, error handling, persistence,
   accessibility constraints, and exclusions.
2. The approved Camera prototype owns composition, control placement, sizing,
   visual tokens, and visible interaction states.
3. A parity matrix resolves every conflict before implementation. If documents
   and prototype disagree, neither current app behavior nor developer preference
   breaks the tie; the Repository Maintainer decides and both authorities are
   updated in the same Work Item.
4. Current app code supplies implementation constraints and gap evidence only.

Known conflicts requiring reconciliation:

| Area | Document | Prototype | Recommendation |
| --- | --- | --- | --- |
| After shutter | Stay on Camera, save to Gallery | Redirect to extraction | Document wins; update prototype to stay and refresh thumbnail |
| Flip control | Switch physical facing | Link to pose-overlay page | Convert prototype to an actual flip interaction |
| Grid default | Optional control; default unspecified | Checked/visible | Decide explicitly; recommend off to avoid surprising persisted state |
| Face guide | Selected pose overlay excluded | Static face guide visible | Treat as optional static composition guide, not FEAT-003 pose overlay |
| Frame ratio | Must apply selected configuration | No visible ratio control | Add approved ratio state to prototype or narrow FR-004 before approval |

## Approaches

### A — Patch the current composable in place

Keep permission, UI, native callbacks, persistence, and feedback inside
`CameraScreen`; fill gaps with local flags and callbacks.

- Advantages: smallest diff and fastest first screenshot match.
- Disadvantages: callback races, timeout/late-callback behavior, atomic
  persistence, and lifecycle recovery remain hard to test deterministically.
- Risk: visual convergence can mask fragile delivery semantics.
- Validation: mostly real-device E2E; insufficient isolation for failure paths.

### B — Testable Camera coordinator with the existing Compose/native bridge

Keep Compose UI and Swift/Mijick camera integration, but introduce a small
state/action coordinator and explicit ports for native Camera, image storage,
photo metadata, clock/ID, and timeout. Make `CameraScreen` render state and emit
actions; native callbacks return success/failure with capture identity.

- Advantages: preserves working platform investment, isolates device-specific
  behavior, makes permission/capture/lifecycle/persistence tests deterministic,
  and supports prototype-aligned UI without a platform rewrite.
- Disadvantages: medium refactor; requires carefully defined compensation and
  callback threading/late-result rules.
- Migration: move behavior incrementally behind current entry point; retain
  bundle/navigation contracts.
- Validation: unit state-machine tests, storage/repository integration tests,
  bridge build checks, then Mobile MCP real-iPhone scenarios.

### C — Move the Camera surface entirely to native SwiftUI

Let SwiftUI own preview, controls, capture, and persistence, exposing only final
gallery events to Compose.

- Advantages: direct iOS lifecycle/camera APIs and potentially simpler native UI
  tuning.
- Disadvantages: duplicates design system/navigation/data boundaries, abandons
  common UI reuse, increases migration scope, and does not help Android parity.
- Risk: two UI architectures and harder cross-feature ownership.
- Validation: extensive native UI/unit rewrite plus integration bridge tests.

## Recommendation

Choose Approach B. It is the smallest design that satisfies the failure-mode
acceptance criteria rather than only matching screenshots. Approach A is weaker
because the current composable already couples every failure boundary; Approach
C expands scope without a demonstrated platform blocker.

## Proposed state and invariants

Core states: `PermissionRequired`, `PreviewReady`, `Capturing(captureId)`,
`Persisting(captureId)`, `CaptureSucceeded(photo)`, and recoverable `Error`.
Lifecycle is an orthogonal active/inactive input. Only the active capture ID may
complete; timeout, backgrounding, or cancellation invalidates it, and late
callbacks are ignored and cleaned up.

Persistence uses collision-resistant IDs and one orchestration boundary:

1. receive non-empty encoded bytes;
2. atomically write a uniquely named file;
3. verify the file is readable;
4. insert metadata and obtain the inserted record;
5. on any failure after file creation, delete the file; never publish thumbnail
   state until both file and record are valid.

If database insertion succeeds but subsequent observable validation fails, the
coordinator removes both record and file or reports a repairable invariant error;
the exact repository transaction/compensation contract is specified in Work
Item 5.

## UI convergence boundary

Match the prototype's full-bleed preview, safe areas, more/settings placement,
zoom affordance, poses shortcut, distinct shutter bar, latest thumbnail, shutter,
and flip placement. Replace dead `if (false)` overlay code with explicit UI
states. Keep a static composition/face guide separate from a selected pose
overlay, which remains out of scope.

Critical controls receive stable accessibility labels and test tags. Dynamic
type, VoiceOver order, contrast, and reduced-motion behavior are checked rather
than inferred from labels.

## Material choices awaiting Maintainer confirmation

1. Approve Approach B (recommended) versus A or C.
2. Approve an iOS-only delivery slice; Android remains an explicit FEAT-001 gap
   and the Feature cannot be called fully delivered.
3. Approve authority conflict resolutions above, especially shutter behavior,
   grid default, static face guide, and how frame ratio appears in the prototype.

Until these answers and FEAT-001 approval exist, this Plan is grounded but not
implementation-ready.
