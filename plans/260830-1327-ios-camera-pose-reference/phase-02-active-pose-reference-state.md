---
phase: 2
title: "Active pose reference state"
status: pending
priority: P0
effort: "4h"
dependencies: ["phase-01"]
---

# Phase 2: Active Pose Reference State (durable)

## Mục tiêu

Introduce `ActivePoseReference` app-level + managed cache path (Harness WI-02). **Future cook handoff** — không ship từ docs lane.

## Goals

- Typed durable record: `poseId`, `mediaId`, `skeletonLocator` (managed cache path), `source`: `local` | `community`.
- Promotion rules: `PreparedPoseReference` → `ActivePoseReference` sau verify.
- Atomic persist; corrupt recovery; cache cleanup on clear/replace.
- Relaunch restore path (authority FEAT-008 / plan 2241).

## Non-goals

- Thay overlay render logic (Phase 4 chỉ rebind owner).
- Server `SavedEntry` / HTTP.

## Contracts

### Data (frozen)

| | PreparedPoseReference | ActivePoseReference |
| --- | --- | --- |
| Lifetime | Session / in-memory emit | Disk-backed until clear/replace |
| Authority | `prepared-pose-reference.md` | Harness 2241 `design.md` |
| Persist relaunch | **Forbidden** (BR-PREPREF-002) | **Required** (2241 / FEAT-008) |
| Entity terms | `Pose.poseId`, `MediaAsset.mediaId` | Same — không `CommunityPose` entity |

Managed cache path: collision-resistant file under app cache; `skeletonLocator` in durable record points to local file only (never remote URL post-promote).

### API

- Community fetch at prepare time only; durable store holds local cache path.

## Tasks

1. Define state machine: `empty` → `preparing` → `ready` → `error`; promotion edge from transient.
2. Storage schema + migration from `PoseServiceLocator.preparedReference`-only pattern.
3. Unit tests: select, replace, clear, relaunch restore, corrupt cache, evict on replace.

## Acceptance (future cook)

- [ ] Relaunch restores `ActivePoseReference` or explicit empty/recovery.
- [ ] Clear deletes durable record + managed cache best-effort.
- [ ] Field names align spec (`mediaId`, `skeletonLocator`) or documented shim.

## Verification

- `./gradlew :shared:iosSimulatorArm64Test` (tests added at cook).
- Cross-check `prepared-pose-reference.md` + 2241 design.

## Risks

| Risk | Mitigation |
| --- | --- |
| Disk full | Fail promote with user-visible error |
| Field shim drift | Migration table in cook PR |

## Rollout / Rollback (future execution)

Cook PR ships store; rollback clears new storage keys (document in cook PR).

## Gate

Phase 1 matrix + Maintainer approve 2241.
