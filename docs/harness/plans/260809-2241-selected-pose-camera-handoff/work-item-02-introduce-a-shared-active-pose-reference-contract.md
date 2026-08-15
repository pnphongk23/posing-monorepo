---
work_item: 2
title: Introduce a shared active pose reference contract
status: pending
priority: P1
effort: M
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 2: Introduce a shared active pose reference contract

**Kind:** story

## Tasks

- Define source-qualified reference identity and the approved immutable render
  descriptor without leaking SQLDelight rows or network DTOs into Camera.
- Add an injected persistent active-reference store with atomic select/replace,
  clear, observe, relaunch restore, validation, and managed render-cache cleanup.
- Integrate the store at the application/navigation composition boundary so
  screen recreation does not create competing instances.
- Persist only source-qualified identity, immutable render metadata, and the
  managed decoded transparent image; never rely on a remote URL during restore.
- Adapt the Camera coordinator to consume active-reference state as an input and
  keep capture/lifecycle state ownership separate.
- Add tests for no selection, both sources, atomic replace, clear, duplicate
  selection, tab/screen recreation, terminate/relaunch restore, clear surviving
  relaunch, corrupt state/cache recovery, and interrupted persistence writes.

## Scope and affected files

- New common contracts/store, application composition/navigation wiring,
  `CameraState.kt`/coordinator input, and focused common tests.

## Success criteria

- Exactly one observable persistent active reference exists; Camera never
  reconstructs or guesses a pose from navigation globals or a remote URL.

## Risks

- A singleton hidden in screen code creates test leakage and stale state; inject
  ownership from one explicit composition root. Non-atomic metadata/cache writes
  can restore the wrong pose after relaunch and require fault-injection coverage.

## Required evidence

- Store/coordinator test output and a documented ownership/lifetime diagram.
