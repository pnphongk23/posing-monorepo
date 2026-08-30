---
phase: 3
title: "Try Pose promotion wiring"
status: pending
priority: P0
effort: "3h"
dependencies: ["phase-02"]
---

# Phase 3: Try Pose Promotion Wiring

## Mục tiêu

Sau prepare OK, **promote** transient → durable rồi mới handoff Camera (Harness WI-03 extension). Session emit (`REP-006` `E-TRY-EMIT`) đã có — phase này thêm durable layer.

## Goals

- Detail prepare pipeline (local + community) unchanged verify step.
- On success: write `ActivePoseReference` + managed cache; then navigate `CameraTab`.
- Never open Camera if promote fails.
- Deprecate sole reliance on `PoseServiceLocator.preparedReference` as long-lived owner (có thể giữ transient emit tạm trong cook).

## Non-goals

- Reimplement overlay draw (Phase 4).
- Search/list Try Pose shortcuts.

## Contracts

- Transient: `PreparedPoseReference` per `prepared-pose-reference.md`.
- Durable: promotion output `ActivePoseReference` (Phase 2).
- API: community skeleton via catalogue — canonical `Pose` / `MediaAsset`, không DTO entity mới.

## UI

- Loading on Try Pose during prepare **and** promote/cache write.
- Error stays on detail with retry.

## Tasks

1. Hook promote step after existing prepare (`PoseDetailScreen.kt` paths).
2. Navigation tests: durable record exists before `CameraTab`.
3. Negative: offline, corrupt cache write, promote failure → no Camera.

## Acceptance (future cook)

- [ ] `TryPoseCameraHandoffTest` + new promotion tests green.
- [ ] Camera not shown without durable `ready` state.

## Verification

- Extend `TryPoseCameraHandoffTest`; manual Try Pose → Camera.

## Risks

- Double-tap Try Pose → disable while preparing/promoting.

## Rollout / Rollback (future execution)

Revert promote hook → current session-only `E-TRY-EMIT` behavior.

## Gate

Phase 2 store merged in cook branch.
