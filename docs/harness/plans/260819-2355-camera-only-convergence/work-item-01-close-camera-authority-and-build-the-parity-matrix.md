---
work_item: 1
title: Close Camera authority and build the parity matrix
status: pending
priority: P1
effort: M
dependencies: []
decision_dependencies: []
---

# Work Item 1: Close Camera authority and build the parity matrix

**Kind:** docs

## Tasks

1. Obtain Maintainer decisions for:
   - Approach B (coordinator with ports) versus A or C.
   - iOS-only delivery slice.
   - Grid default OFF.
   - Static composition/face guide as optional decorative element.
   - Frame ratio scope (developer-visible only vs. user control).
   - Three production parity corrections (shutter capture-only, hardware flip,
     grid default OFF) with the prototype as read-only reference.
2. Update `design.md` with confirmed decisions and mark resolved.
3. Document prototype mismatches as evidence in `design.md` “Prototype mismatch
   evidence” table — the prototype is **never modified**. For each mismatch
   (shutter redirect, flip navigation, grid checked default), record:
   - The prototype behavior (evidence with file:line reference).
   - The FEAT-001 intended behavior.
   - The production parity correction (what the app implements).
4. Confirm FEAT-001 is approved and no blocking Camera Decision remains.
5. Build and publish the complete parity matrix in `plan.md` Section “Authority/
   parity matrix” with zero unresolved conflicts.
6. Add capture→Gallery pipeline evidence: document the end-to-end flow
   (capture → file → metadata → thumbnail → Gallery) in `plan.md` and
   `design.md` with acceptance criteria.
7. Run `ckh validate` and `ckh workflow check` on the plan.

## Scope and affected files

- `docs/harness/plans/260819-2355-camera-only-convergence/plan.md`
- `docs/harness/plans/260819-2355-camera-only-convergence/design.md`
- `docs/harness/features/FEAT-001-capture-a-photo-on-mobile.md` (if updates needed)
- `docs/prototype/**` — **READ-ONLY reference only**; no files created, edited,
  or deleted. Prototype evidence is documented in `design.md`, not in the
  prototype itself.

## Success criteria

- FEAT-001 is approved; no blocking Camera Decision remains.
- Every Camera control/state has one approved behavior and visual mapping; zero
  unresolved parity conflicts remain in the matrix.
- Prototype mismatches documented as evidence (shutter redirect, flip navigation,
  grid checked default) with intended behavior and production parity correction.
- Prototype is never modified; it remains a static read-only reference.
- Document versus prototype precedence is explicit and Maintainer-confirmed.
- Capture→Gallery pipeline is documented with end-to-end acceptance criteria.
- FEAT-002 ownership/deletion boundary is defined (write-side contract).

## Risks

- Calling an iOS slice complete must not imply Android FEAT delivery.
- Capture→Gallery pipeline acceptance depends on WI-02 through WI-06.

## Required evidence

- Maintainer decision records (inline in design.md or separate Decision files).
- Prototype mismatch evidence table in `design.md` (read-only, no prototype edits).
- Capture→Gallery pipeline documented in `plan.md` and `design.md`.
- FEAT-002 ownership/deletion boundary documented.
- `ckh validate` and `ckh workflow check` output.
- `git diff` proving documentation-only scope (no prototype or source edits).
- Parity matrix with zero unresolved rows.
