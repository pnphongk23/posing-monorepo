---
work_item: 1
title: Close FEAT-002 authority and parity matrix
status: completed
priority: P1
effort: S
dependencies: []
decision_dependencies: []
---

# Work Item 1: Close FEAT-002 authority and parity matrix

**Kind:** decision/authority gate

> **Closed at Cook start (WI-01, 2026-08-19).** The authority gate recorded in
> Tasks below is **superseded**: FEAT-002 `approved` (Product Authority,
> phongpn, 2026-08-19), DEC-004 `approved` (Repository Maintainer,
> 2026-08-19), Plan `260819-0735` review `approved` (Repository Maintainer,
> 2026-08-19). Draft/proposed wording below is historical — see
> [Evidence](#evidence-wi-01-2026-08-19).

## Tasks

- Record the **execution prerequisite**: FEAT-002 is `draft`
  (`docs/harness/features/FEAT-002-manage-a-local-photo-gallery.md`, no
  `approved` date). This Plan cannot be execution-approved until **Product
  Authority** approves the Feature. Repository Maintainer approves the Plan
  template/sequence; the two authorities are distinct and neither is inferred
  by this Plan. — *superseded at Cook start: FEAT-002 was approved
  2026-08-19 (phongpn, Product Authority); no Cook started while `draft`.*
- Document **recommended FEAT-002 updates** (proposed at plan time; not
  applied by this WI — **superseded at Cook start**: Repository Maintainer
  applied FR-003 / BR-002 / BR-003 to FEAT-002 on 2026-08-19; see
  Evidence):
  1. Add a gallery **search** requirement (title-tag filter per
     `app.js:348-352`).
  2. Clarify the **deletion contract**: Photo row + owned `imagePath` file +
     linked `PersonalPose` cascade (extend BR-001 wording beyond a singular
     "owned file").
  3. Clarify **export scope**: Save to Photos only (no share sheet / generic
     file export), delivered on **iOS** in this Plan.
  4. **Defer Android platform parity** to a future FEAT-002 slice (iOS-first
     per Maintainer 2026-08-19; Android planned only after an Android KMP
     target exists).
  5. Note FK `ON DELETE SET NULL` (`Photo.sq:5`) is **not** a cascade —
     explicit orchestration required.
  6. Record **search mapping Option A** and **last-reference cascade**
     (Maintainer 2026-08-19) in DEC-004 and plan verification ledger.
- Document the **Maintainer iOS-first decision (2026-08-19)**: this Plan
  delivers FEAT-002 on iOS only; Android is deferred to a future slice.
- Document [DEC-004](../../decisions/DEC-004-feat-002-gallery-parity-matrix.md)
  (`status: proposed` at plan time; **approved 2026-08-19 by Repository
  Maintainer** — superseded) with search IN scope, deletion cascade
  (last-reference, Maintainer 2026-08-19),
  Save to Photos only (iOS), dense-grid parity, and Android **Excluded** /
  deferred. DEC-004 records the **iOS-scoped** matrix. This WI records the
  matrix; it was **proposed** until FEAT-002 approval — **closed at Cook
  start** (2026-08-19).
- Record the Plan `260809-1806` relationship (documented only; **no
  `blockedBy`**) and the completed `260809-2240` WI-05 deletion pattern as
  read-only reference.
- Record prototype authority: `gallery.html`, `gallery-detail.html`,
  `app.js:343-352` (filter), `fixtures.js` `GALLERY_FIXTURES`, `card.css`,
  `grid.css`.

## Scope and affected files

- `docs/harness/decisions/DEC-004-feat-002-gallery-parity-matrix.md`
- `design.md`, `scout-summary.txt`, `plan.md`

## Success criteria

- FEAT-002 approval prerequisite is recorded; no Cook starts while the Feature
  is `draft`.
- Recommended FEAT-002 updates are enumerated (not silently applied).
- DEC-004 labels every row Aligned / Gap / Partial / Boundary / Excluded /
  Resolved with an owning WI or Maintainer decision.
- Search mapping (Option A) and last-reference cascade recorded as **Resolved**
  (Maintainer 2026-08-19); ledger **0 Unresolved**.
- Plan 260809-1806 relationship is documented without a `blockedBy` edge.

## Risks

- Inventing or inferring Product Authority approval for FEAT-002.
- Treating the Android build-target gap as in-scope for this Plan (it is
  deferred — Maintainer 2026-08-19).
- Confusing DEC-004 `proposed` with an approved parity matrix. — *resolved
  2026-08-19: DEC-004 is `approved` (Repository Maintainer).*

## Required evidence

- Checked-in DEC-004 and updated design/plan/scout.
- `ckh validate docs/harness/plans/260819-0735-feat-002-local-photo-gallery/plan.md --workspace .`

## Evidence (WI-01, 2026-08-19)

### Authority closed

| Artifact | Status | Authority | Decided |
| --- | --- | --- | --- |
| FEAT-002 | `approved` | Product Authority (phongpn) | 2026-08-19 |
| DEC-004 | `approved` | Repository Maintainer | 2026-08-19 |
| Plan `260819-0735` | `approved` (review) | Repository Maintainer | 2026-08-19 |

Authority gate **closed** at Cook start; no Cook started while FEAT-002 was
`draft`. The draft/proposed statements in Tasks above are superseded.

### FEAT-002 updates applied by Maintainer (2026-08-19)

Applied to `docs/harness/features/FEAT-002-manage-a-local-photo-gallery.md` by
Repository Maintainer (reference-only for this WI — no Cook edits, no duplicate
content):

- **FR-003** — gallery search filters photos by case-insensitive substring on
  `Photo.poseName` and linked `Pose.name` when `poseId` is set (prototype
  title/tag semantics map to pose-name text; Plan `260819-0735` Option A).
- **BR-002** — cascade delete of linked `PersonalPose` + owned assets occurs
  only when no other `Photo` rows reference that `poseId` after the delete
  (last-reference rule; explicit orchestration — FK `ON DELETE SET NULL` is
  not relied upon).
- **BR-003** — export is Save to Photos only (no share sheet / generic file
  export); iOS delivery in scope for this Plan, Android parity deferred to a
  future slice.

### DEC-004 iOS-scoped matrix linked

DEC-004 is linked from Plan `260819-0735` and FEAT-002
(`[[DEC-004-feat-002-gallery-parity-matrix|DEC-004]]`); every row is labeled
Aligned / Gap / Partial / Boundary / Excluded / Resolved with an owning WI or
Maintainer decision. Search mapping (**Option A**) and last-reference cascade
are recorded **Resolved** (Maintainer 2026-08-19).

### Verification ledger

`plan.md` ledger: 8 Verified · 1 Excluded · 2 Resolved · **0 Unresolved**
(11 claims). Ledger closed by Maintainer 2026-08-19.

### iOS-first / Android deferred

Android parity is **Excluded** from this Plan (`E-ANDROID`, `E-ANDROID-TARGET`)
and deferred to a future FEAT-002 slice, planned only after an Android KMP
target exists (Maintainer 2026-08-19, iOS-first).

### `ckh validate` (2026-08-19)

```
Harness validation passed
```

### `ckh workflow check` (2026-08-19)

```
Harness validation passed
```
