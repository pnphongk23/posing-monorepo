---
work_item: 3
title: Mobile shared and Compose
status: completed
priority: P1
effort: L
dependencies: []
decision_dependencies: []
---

# WI-03 — Mobile shared and Compose

- Replace runtime PoseReferenceKey/PersonalPose branching with String UUID poseId.
- Align navigation, repositories, ViewModels, gallery, search, and camera handoff with canonical Pose media roles.
- Keep old transport fixtures only as deprecated adapters during test migration.
- Acceptance: common and iOS simulator tests pass; framework link succeeds.
