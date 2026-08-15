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

- Run coordinator, layout, storage, repository, and bridge tests; repair only
  Camera-plan or explicitly approved prerequisite failures.
- Build/sign/install the exact app revision through the dependent iPhone testing
  workflow and execute the full FEAT-001/parity scenario matrix.
- Exercise permission recovery, controls, rapid taps, successful capture,
  thumbnail/Gallery, offline operation, background/foreground, interruption,
  native failure, and persistence failure where safely injectable.
- Compare app checkpoints to the approved prototype checklist across target
  device sizes; capture accessibility state, recording, crash delta, file, and
  database evidence.
- Publish a delivery report mapping every requirement to evidence and preserving
  Android and other excluded gaps; run whole-Plan consistency and Harness checks.

## Scope and affected files

- Test/evidence/report artifacts only; implementation failures return to their
  owning Work Item rather than being patched opportunistically here.

## Success criteria

- Every in-scope FEAT-001 acceptance item is Passed or the Plan remains
  incomplete with a precise Failed/Blocked result.
- No unexplained document/prototype/app divergence, new crash, stuck capture,
  duplicate record/file, orphan artifact, or unreadable thumbnail remains.
- The report says iOS slice rather than claiming Android or full cross-platform
  FEAT delivery.

## Risks

- Hardware flash/camera/interruption scenarios can be environment-dependent;
  record capabilities and do not weaken expected results after observing them.
- Personal content may appear in Camera evidence; use a controlled scene and
  approved retention/redaction.

## Required evidence

- All native/unit command logs; signed build identity; Mobile MCP scenario trace;
  semantic snapshots; screenshots and recording; crash delta; file/database
  assertions; prototype checklist; `ckh workflow check` and graph/index checks.
