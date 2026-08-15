---
work_item: 5
title: Make personal pose deletion atomic and recoverable
status: completed
priority: P1
effort: L
dependencies:
  - 4
decision_dependencies: []
---

# Work Item 5: Make personal pose deletion atomic and recoverable

**Kind:** story

## Tasks

- Add an injected storage deletion/readability contract for each approved owned
  local asset field; distinguish owned filenames/paths from data URIs and remote
  URLs without attempting to delete non-owned references.
- Make no server delete request. Community references expose no delete action;
  only confirmed My Poses items enter the local deletion workflow.
- Implement the approved metadata/file ordering and compensation strategy so a
  reported success leaves neither metadata nor owned files, while a reported
  failure retains/restores a usable list item as FEAT-003 requires.
- Restrict delete UI/actions to personal references and retain the destructive
  confirmation dialog, in-flight protection, explicit failure message, and retry.
- Handle missing files idempotently according to the approved invariant and
  prevent double-confirm/double-delete races.
- Add repository/storage integration tests for success, missing record/file,
  embedded data, permission failure, metadata failure, and compensation failure.

## Scope and affected files

- `PoseRepository.kt`, common/actual `ImageStorage` contracts, personal detail
  state/UI, and platform integration tests.

## Success criteria

- Successful deletion removes metadata and every owned file exactly once.
- Failed local deletion never reports success, retains or restores a usable My
  Poses item, and never mutates community or server state.

## Risks

- Current storage returns only a filename while readers may resolve a different
  base directory; ownership and canonical-path checks must precede deletion.
- Cross-store atomicity requires explicit compensation and observable repair
  state; SQL transactions cannot roll back filesystem deletion.

## Required evidence

- Fault-injection test output, before/after database and filesystem evidence,
  confirmation/failure UI evidence, and BR-001 community snapshot comparison.
