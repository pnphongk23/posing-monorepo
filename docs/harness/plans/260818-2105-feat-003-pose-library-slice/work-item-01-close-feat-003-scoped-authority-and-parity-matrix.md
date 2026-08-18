---
work_item: 1
title: Close FEAT-003 scoped authority and parity matrix
status: pending
priority: P1
effort: S
dependencies: []
decision_dependencies: []
---

# Work Item 1: Close FEAT-003 scoped authority and parity matrix

**Kind:** decision/authority gate

## Tasks

- Confirm FEAT-003 approval (2026-08-18) and Maintainer **Option A**: Create Pose
  = Camera capture entry only — **not** FEAT-004 extraction.
- Document [DEC-003](../../decisions/DEC-003-feat-003-scoped-parity-matrix.md) with
  search **removed from product surface** (WI-03), Option A Create Pose row, and
  Plan 2241 prepare+emit seam. DEC-003 remains **proposed** until Maintainer
  approves separately; this WI records the matrix only.
- Record prototype authority: `poses-list.html`, `pose-detail.html`,
  `camera-live.html`, `camera-pose-overlay.html` (overlay reference); **not**
  `search.html` (Plan 2112).
- Note Plan 2112 ordering: 2105 hides search; 2112 reintroduces when approved.
- Link Plan 2241 WI-03 stale description vs `Navigation.kt:152-156` in design/plan.

## Scope and affected files

- `docs/harness/decisions/DEC-003-feat-003-scoped-parity-matrix.md`
- `design.md`, `scout-summary.txt`, `plan.md`

## Success criteria

- No acceptance claims FEAT-004 extraction wired.
- Search removal is a **Gap** row (WI-03), not "may stay visible".
- Parity matrix labels every row with owning WI or Plan 2241/2112.

## Risks

- DEC-002 / REP-003 search rows mistaken as in-scope without DEC-003 override.

## Required evidence

- Checked-in DEC-003 and updated design/plan.
- `ckh validate docs/harness/plans/260818-2105-feat-003-pose-library-slice/plan.md --workspace .`
