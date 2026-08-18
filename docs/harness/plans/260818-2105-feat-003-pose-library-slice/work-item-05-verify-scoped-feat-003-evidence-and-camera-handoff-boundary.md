---
work_item: 5
title: Verify scoped FEAT-003 evidence and camera handoff boundary
status: pending
priority: P1
effort: M
dependencies:
  - 2
  - 4
decision_dependencies: []
---

# Work Item 5: Verify scoped FEAT-003 evidence and camera handoff boundary

**Kind:** verification / evidence gate

## Tasks

- Run iOS simulator / compose tests for WI-02–04.
- Capture manual or MCP evidence for browse, detail, Create Pose → Camera, Try Pose emit.
- Build DEC-003 evidence matrix with **per-row IDs** (below).
- Confirm `CameraScreen.kt:173` overlay remains disabled.
- Run harness validation; **do not** `ckh plan approve`.

## DEC-003 evidence matrix

| DEC-003 row | Evidence ID | WI | Pass criterion |
| --- | --- | --- | --- |
| Create Pose (+) | **E-CAM-ENTRY** | 2 | Create Pose → `CameraTab`; no `extractPose` |
| Empty My → Create Pose | **E-CAM-ENTRY** | 2 | Same callback as toolbar `+` |
| Search toolbar absent | **E-SEARCH-NEG** | 3 | No search button; no SearchScreen route |
| FR-002 / search code | **E-2112-DEFER** | — | SearchScreen/Provider/server untouched |
| FEAT-004 extraction | **E-EXTRACT-DEFER** | — | No acceptance calls `extractPose` |
| Browse My/Community | **E-BROWSE-REG** | 3 | Coordinator + tab regression green |
| Detail / delete / E2 | **E-DETAIL-REG** | 4 | Detail regression tests green |
| Try Pose prepare+emit | **E-TRY-EMIT** | 4 | `preparedReference` set; tab switch |
| Try Pose overlay | **E-2241-BOUNDARY** | — | `if (false)` unchanged; 2241 owns |
| Android / FEAT-008 Save | **E-OUT-NEG** | — | Not exercised |

## Scope and affected files

- Plan directory + test outputs under `mobile/shared/...Test/` and `composeApp/...Test/`

## Success criteria

- All **Gap** rows closed; **Boundary** / **Excluded** rows evidenced per matrix.
- `ckh workflow check` passes.
- Evidence packet separates Camera entry vs extraction-deferred vs search-negative
  vs 2241 overlay-deferred.

## Risks

- Conflating REP-003 delivery with this scoped re-verification.

## Required evidence

- Test run log (simulator).
- Completed evidence matrix table (above) in delivery notes.
- `ckh workflow check docs/harness/plans/260818-2105-feat-003-pose-library-slice --workspace .`
- `ckh validate docs/harness/plans/260818-2105-feat-003-pose-library-slice/plan.md --workspace .`
