---
phase: 2
title: "Active pose reference state"
status: pending
priority: P0
effort: "4h"
dependencies: ["phase-01"]
---

# Phase 2: Active Pose Reference State

## Mục tiêu

Introduce shared persistent active pose reference + managed render asset (Harness WI-02).

## Goals

- Typed state: source identity (local vs community), poseId/mediaId, cache path.
- Atomic persist; corrupt state recovery; cache cleanup on clear/replace.

## Non-goals

- UI overlay rendering (Phase 4).
- Server SavedEntry.

## Contracts

### Data

- Align `PreparedPoseReference` → durable active reference promotion rules.
- File cache naming collision-resistant (learn from REP-002 GAP-005 pattern).

### API

- Community image fetch uses existing community URLs; no new endpoints.

## UI / Admin / Ops

- N/A implementation in docs phase; cook targets `mobile/shared` state + persistence.

## Tasks

1. Define state machine: empty → preparing → ready → error.
2. Map storage keys and migration from session-only patterns.
3. Unit test matrix: select, replace, clear, relaunch restore, corrupt file.

## Acceptance

- [ ] State store tests pass (Harness WI-02 success criteria).
- [ ] terminate/relaunch restores ready reference.
- [ ] Clear removes managed cache best-effort.

## Verification

- `./gradlew :shared:iosSimulatorArm64Test` (target tests TBD at cook).
- Review against `prepared-pose-reference.md`.

## Risks

| Risk | Mitigation |
| --- | --- |
| Disk full | Fail prepare with user-visible error |
| Stale community URL | TTL re-fetch on prepare |

## Rollout / Rollback

Ship behind existing app version bump; rollback clears new storage keys (document migration note at cook).

## Gate

Phase 1 parity matrix approved.
