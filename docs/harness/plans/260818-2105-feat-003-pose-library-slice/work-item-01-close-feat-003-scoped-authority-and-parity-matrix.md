---
work_item: 1
title: Close FEAT-003 scoped authority and parity matrix
status: completed
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
  search **retained / wired** on poses-list (WI-03 verifies the affordance), Option A
  Create Pose row, and Plan 2241 prepare+emit seam. DEC-003 is **approved**
  (2026-08-18); this WI records the matrix only.
- Record prototype authority: `poses-list.html`, `pose-detail.html`,
  `camera-live.html`, `camera-pose-overlay.html` (overlay reference); **not**
  `search.html` (Plan 2112).
- Note Plan 2112 ordering: 2112 owns search behavior (SearchScreen/provider/server `q`);
  2105 retains and verifies the search icon stays wired; no hide/unwire by 2105.
- Link Plan 2241 WI-03 stale description vs `Navigation.kt:152-156` in design/plan.

## Scope and affected files

- `docs/harness/decisions/DEC-003-feat-003-scoped-parity-matrix.md`
- `design.md`, `scout-summary.txt`, `plan.md`

## Success criteria

- No acceptance claims FEAT-004 extraction wired.
- Search affordance retention is a **verify** row (WI-03): icon visible + navigates to
  SearchScreen — not "may be removed".
- Parity matrix labels every row with owning WI or Plan 2241/2112.

## Risks

- DEC-002 / REP-003 search rows mistaken as in-scope without DEC-003 override.

## Required evidence

- Checked-in DEC-003 and updated design/plan.
- `ckh validate docs/harness/plans/260818-2105-feat-003-pose-library-slice/plan.md --workspace .`

## Evidence (WI-01, 2026-08-19)

### Authority alignment

- **DEC-003** (`status: approved`, 2026-08-18): parity matrix rows label owning WI or
  Plan 2112/2241; search row = **Aligned — verify WI-03** (`E-SEARCH-WIRED`); Create
  Pose = **Gap WI-02** (Camera capture entry, Option A); FEAT-004 `extractPose` =
  **Excluded** (`E-EXTRACT-DEFER`); Plan 2112 owns search behavior; Plan 2241 WI-03
  stale vs `Navigation.kt:152-156` noted in DEC-003 §3 and `design.md` §3.
- **design.md** + **scout-summary.txt** + **plan.md** frontmatter aligned with
  Maintainer Option A (search icon retained+wired, not removed).
- Prototype authority: `poses-list.html`, `pose-detail.html`, `camera-live.html`,
  `camera-pose-overlay.html`; **not** `search.html` (Plan 2112).

### `ckh validate` (2026-08-19)

```
Harness validation passed
```

### `ckh workflow check` (2026-08-19)

```
Harness validation passed
```
