---
work_item: 4
title: Build mobile Saved UX and sign-in gating
status: completed
priority: P2
effort: M
dependencies:
  - 3
decision_dependencies: []
---

# Work Item 4: Build mobile Saved UX and sign-in gating

## Tasks

- Extend PoseApiService/PoseRepository with Saved API and existing error conventions.
- Add detail Save/Unsave toggle with sign-in gate and confirmed-response state.
- Add Saved list loading, empty, error, retry and pagination; tap item to existing detail.
- Gate Try Pose after sign-in and reuse verify/handoff.
- Stale detail/deep-link or use attempt after removal shows “đã xoá hoặc đã ẩn” and blocks Try Pose; do not delete SavedEntry.
- Offline reads stale only; never queue Save/Unsave or show false success.

## Scope and affected files

Existing mobile data/UI/navigation flow; excludes Album UI/API, Android, ownership/publish, FEAT-012 and camera relaunch.

## Success criteria

Signed-out actions request sign-in; state changes only after success; list states/pagination work; 401 clears/refreshes; unavailable message appears.

## Risks

Community-only navigation may need a minimal Saved entry point; avoid a second architecture or local-first queue.

## Required evidence

Exact mobile symbols, API/ViewModel/UI tests, iOS evidence for gating, Save/Unsave, list, pagination, detail, removal, 401 and offline.
