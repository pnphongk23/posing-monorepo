---
work_item: 3
title: Integrate select replace clear and relaunch behavior
status: pending
priority: P2
effort: TBD
dependencies:
  - 2
decision_dependencies: []
---

# Work Item 3: Integrate select replace clear and relaunch behavior

## Tasks

- Tích hợp snapshot với existing Try Pose select/replace flow sau verify; giữ nguyên settings khi replace.
- Tích hợp explicit clear để gỡ pose overlay/selection, giữ settings, không tác động source Pose ownership.
- Bootstrap Camera từ snapshot khi relaunch và giữ capture/gallery semantics, overlay rendering, và verify-before-emit.

## Scope and affected files

- Existing `Navigation`, `PoseDetailScreen`, `CameraScreen`, camera state/controller và snapshot API từ WI-02; không mở rộng domain.

## Success criteria

- Integration evidence chứng minh select/replace/clear/relaunch; replace giữ settings và clear không save/publish/delete.
- Capture sau restore vẫn ghi gallery theo baseline; Try Pose vẫn verify trước handoff.

## Risks

- `remember(preparedReference)` có thể cạnh tranh với persisted bootstrap; phải có một initial-state owner rõ ràng.

## Required evidence

- Integration test names/paths, behavior logs/screenshots nếu có, và `ckh workflow check` pass.
