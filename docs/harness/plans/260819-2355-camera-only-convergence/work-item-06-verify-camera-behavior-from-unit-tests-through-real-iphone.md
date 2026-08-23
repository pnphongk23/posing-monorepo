---
work_item: 6
title: Verify Camera behavior from unit tests through real iPhone
status: pending
priority: P1
effort: L
dependencies:
  - 5
decision_dependencies: []
---

# Work Item 6: Verify Camera behavior from unit tests through real iPhone

**Kind:** verification

## Tasks

1. Run all Camera-related tests:
   ```bash
   ./gradlew :composeApp:allTests
   ./gradlew :shared:iosSimulatorArm64Test
   ```
   Repair only Camera-plan or explicitly approved prerequisite failures.
2. Build/sign/install the exact app revision through the iPhone testing workflow
   and execute the full FEAT-001/parity scenario matrix on a real iPhone.
3. Exercise the complete scenario matrix:
   | Scenario | Expected outcome |
   | --- | --- |
   | First launch (permission not determined) | Permission request shown |
   | Permission denied | Capture disabled, "Open Settings" shown |
   | Permission authorized | Preview live, controls enabled |
   | Single capture | Flash → file + metadata → thumbnail updated |
   | Rapid double-tap capture | Only one capture completes; second ignored |
   | Capture timeout | Error state, no stuck capture |
   | Background during capture | Capture cancelled, preview stopped |
   | Foreground re-entry | Preview restarted, controls restored |
   | Flash toggle (OFF/ON/AUTO) | Native flash state matches UI |
   | Flip facing (BACK ↔ FRONT) | Camera feed switches; no navigation |
   | Grid toggle | 3×3 overlay appears/disappears |
   | Zoom 1× → 2× → 3× | Preview zoom changes; label updates |
   | Gallery thumbnail tap | Navigates to Gallery tab |
   | Capture → Gallery display | Captured photo appears in Gallery grid |
   | Poses/users button tap | Navigates to Poses tab |
   | Capture failure (inject if possible) | Error message shown, no false success |
   | Failure → no Gallery phantom | Failed capture does not appear in Gallery |
   | Offline capture | Capture succeeds without network |
4. Compare app checkpoints to the approved prototype checklist across target
   device sizes (iPhone SE, iPhone 15, iPhone 15 Pro Max or equivalent).
5. Capture evidence:
   - Accessibility state (test tags, content descriptions).
   - Screenshots at each scenario checkpoint.
   - Screen recording of full scenario matrix.
   - Crash delta (zero new crashes expected).
   - File system evidence (captured files exist, correct naming).
   - Database evidence (Photo records correct, no orphans).
6. Publish a delivery report mapping every FEAT-001 requirement to evidence:
   - FR-001: Permission gating → evidence reference.
   - FR-002: One capture → one outcome → evidence reference.
   - Capture→Gallery pipeline: capture → file → metadata → thumbnail →
     Gallery display → evidence reference.
   - FEAT-002 ownership boundary: write-side contract → evidence reference.
   - BR-001: No false success on failure → evidence reference.
   - Production parity checklist (shutter capture-only, hardware flip,
     grid default OFF) → evidence reference.
7. Run whole-Plan consistency and Harness checks:
   ```bash
   ckh validate docs/harness/plans/260819-2355-camera-only-convergence/plan.md --workspace .
   ckh workflow check docs/harness/plans/260819-2355-camera-only-convergence --workspace .
   ```

## Scope and affected files

- Test/evidence/report artifacts only; implementation failures return to their
  owning Work Item rather than being patched opportunistically here.
- Delivery report at `reports/` directory.

## Success criteria

- Every in-scope FEAT-001 acceptance item is Passed or the plan remains
  incomplete with a precise Failed/Blocked result.
- **Capture→Gallery proof:** a successful capture provably appears in the
  Gallery (photo record exists, file readable, Gallery grid shows it).
- **Failure never claims success:** failed captures do not appear in Gallery;
  no false thumbnail updates.
- No unexplained document/app divergence, new crash, stuck capture, duplicate
  record/file, orphan artifact, or unreadable thumbnail remains.
- The report says iOS slice rather than claiming Android or full cross-platform
  FEAT delivery.

## Risks

- Hardware flash/camera/interruption scenarios can be environment-dependent;
  record capabilities and do not weaken expected results after observing them.
- Personal content may appear in Camera evidence; use a controlled scene and
  approved retention/redaction.
- Build/sign/install workflow may have external dependencies; document any
  blocking issues.

## Required evidence

- All native/unit command logs (test runner output).
- Signed build identity (bundle ID, version, commit hash).
- Mobile MCP scenario trace (if available).
- Semantic snapshots (accessibility tree at key checkpoints).
- Screenshots and screen recording at each scenario.
- Crash delta (build × run comparison).
- File system assertions (captured files exist, correct naming convention).
- Database assertions (Photo records correct, no orphans).
- **Capture→Gallery evidence:** screenshot of Gallery showing captured photo,
  file system proof, database proof.
- **Failure-never-claims-success evidence:** failed capture scenario showing
  no Gallery phantom, no false thumbnail.
- Production parity checklist (shutter capture-only, hardware flip, grid
  default OFF — all controls verified).
- `ckh validate` and `ckh workflow check` output.
- Delivery report with requirement-to-evidence mapping.
