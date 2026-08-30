---
phase: 3
title: "Try Pose navigation wiring"
status: pending
priority: P0
effort: "3h"
dependencies: ["phase-02"]
---

# Phase 3: Try Pose Navigation Wiring

## Mục tiêu

Wire local và community Try Pose flows (Harness WI-03): prepare → success → Camera tab only.

## Goals

- Detail screens call prepare pipeline before navigation.
- Never open Camera with missing/unresolvable reference.
- Preserve existing tab order and back stack.

## Non-goals

- Overlay draw logic.
- Search/list Try Pose shortcuts (future).

## Contracts

- Navigation: `PreparedPoseReference` emit already in REP-006 — extend to await ready state.
- API: community skeleton/thumbnail URLs from catalogue DTO.

## UI

- Loading indicator on Try Pose button during prepare.
- Error snackbar/dialog with retry on fetch/decode fail.

## Admin / Ops

- N/A.

## Tasks

1. Unify local file read vs community download in prepare use case.
2. Navigation tests: both detail variants set state before `CameraTab`.
3. Negative tests: offline, 404 image, corrupt bytes.

## Acceptance

- [ ] Navigation tests pass (Harness WI-03).
- [ ] Camera never shown with `empty` active reference after Try Pose tap.
- [ ] Community + local paths covered.

## Verification

- `TryPoseCameraHandoffTest` extended (existing test file per REP-006).
- Manual: Try Pose → observe loading → Camera.

## Risks

- Race: double-tap Try Pose → disable button while preparing.

## Rollout / Rollback

Revert navigation guard → prior tab-switch-only behavior.

## Gate

Phase 2 state store merged.
