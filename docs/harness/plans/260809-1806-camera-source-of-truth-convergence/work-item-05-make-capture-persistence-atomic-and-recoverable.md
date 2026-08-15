---
work_item: 5
title: Make capture persistence atomic and recoverable
status: pending
priority: P1
effort: L
dependencies:
  - 4
decision_dependencies: []
---

# Work Item 5: Make capture persistence atomic and recoverable

**Kind:** technical

## Tasks

- Replace second-resolution filenames with collision-resistant capture IDs and
  define one image ownership/lifecycle contract shared with FEAT-002.
- Atomically write image bytes, verify readability, insert metadata, and return
  the inserted record rather than requerying an ambiguous latest path.
- Compensate file/database partial failures and make cleanup idempotent for
  timeout, cancellation, backgrounding, termination recovery, and late callbacks.
- Expose typed errors suitable for truthful Camera UI recovery; never publish a
  thumbnail before both file and metadata are valid.
- Add storage/repository/orchestration tests for collision, low/write failure,
  unreadable file, database failure, duplicate callback, and cleanup failure.

## Scope and affected files

- `mobile/shared/src/commonMain/kotlin/com/aipose/data/ImageStorage.kt`
- `mobile/shared/src/iosMain/kotlin/com/aipose/data/ImageStorage.kt`
- `mobile/shared/src/commonMain/kotlin/com/aipose/data/PhotoRepository.kt`
- SQLDelight schema/queries and related tests only as required by the approved
  file-plus-record transaction/compensation contract.
- Camera coordinator integration from Work Item 2.

## Success criteria

- Successful capture produces exactly one unique readable file and exactly one
  matching metadata record, returned directly to UI state.
- Every injected failure leaves no newly broken record or orphan file; cleanup
  failure is observable and repairable rather than hidden.
- Two rapid captures cannot overwrite each other.

## Risks

- Filesystem and SQL database cannot share a native atomic transaction; the
  compensation order and crash-recovery marker must be explicit.
- FEAT-002 deletion owns the reverse lifecycle; avoid incompatible duplicate
  policies and link follow-up work if outside this Plan.

## Required evidence

- Focused unit/integration test output, temporary-storage artifact inspection,
  SQL row assertions, two-rapid-capture test, and real-device readable-file plus
  metadata proof.
