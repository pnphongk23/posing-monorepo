---
work_item: 5
title: Harness validation and index/graph build
status: completed
priority: P1
effort: M
dependencies:
  - 4
decision_dependencies: []
---

# Work Item 5: Harness validation and index/graph build

## Tasks

1. Run `ckh validate --all` and resolve any new failures introduced by this
   refactor (distinguish from pre-existing out-of-scope failures in plan
   `260816-2240-higgsfield-cli-parallel-extract-provider`).
2. Run `ckh index build` then `ckh index check`.
3. Run `ckh graph build` then `ckh graph check`.
4. Mark Work Items 1–4 completed once checks pass; set plan status to completed.

## Scope and affected files

- No new source files. May touch the generated
  `docs/harness/graph-out/retrieval-index.json` via `ckh index build`.

## Success criteria

- `ckh validate --all`, `ckh index build`/`check`, and `ckh graph build`/`check`
  all exit cleanly (no refactor-introduced defect).
- All Work Items and the plan are marked completed.

## Risks

- Pre-existing validation failures in out-of-scope plan `260816-2240` block a
  fully green `ckh validate --all`/`ckh index build` — documented as a blocker
  if it persists.

## Required evidence

- Exact output of `ckh validate --all`, `ckh index build`, `ckh index check`,
  `ckh graph build`, `ckh graph check` recorded in the delivery report.