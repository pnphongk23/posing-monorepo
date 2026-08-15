---
work_item: 1
title: Close FEAT-003 authority and freeze library contracts
status: completed
priority: P1
effort: M
dependencies: []
decision_dependencies: []
---

# Work Item 1: Close FEAT-003 authority and freeze library contracts

**Kind:** decision/authority gate

## Tasks

- Verify the recorded Maintainer choices in `design.md`: iOS-first delivery,
  mock-first replaceable community search, nullable missing detail fields,
  local-only My Poses deletion, and document/prototype authority precedence.
- Build a requirement-to-prototype-to-code parity matrix for FR-001 through
  FR-010, BR-001, NFR-001, both named scenarios, and exception flows E1-E3.
- Keep FEAT-003 and linked specs/prototype aligned when behavior or visible
  interaction changes; remove social prototype elements from the canonical path
  or mark them explicitly non-authoritative.
- Define `PoseReferenceKey`, personal/community detail contracts, paging
  semantics, operation/error states, and deletion invariants before code work.
- Confirm FEAT-003 approval and keep dependent Plans pending if their separate
  authority remains incomplete.

## Scope and affected files

- `docs/harness/features/FEAT-003-browse-and-use-pose-references.md`
- Linked product, technical, and UI specs plus named prototype screens/scripts.
- `design.md` and a checked-in parity/decision artifact if needed.

## Success criteria

- No requirement depends on an unstated Android, search, metadata, storage, or
  prototype interpretation.
- FEAT-003 is approved by the Repository Maintainer and the Harness graph links
  both implementation Plans.

## Risks

- Scope drift can create incompatible adapters, fabricate nullable metadata, or
  claim Android/production-server delivery from iOS mock-backed evidence.

## Required evidence

- Approved Feature, completed parity matrix, recorded decisions, `ckh graph
  related FEAT-003`, and successful Harness validation/check output.
