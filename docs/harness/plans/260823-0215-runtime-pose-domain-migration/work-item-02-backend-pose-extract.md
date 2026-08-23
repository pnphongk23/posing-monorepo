---
work_item: 2
title: Backend Pose-Extract runtime
status: completed
priority: P1
effort: M
dependencies: []
decision_dependencies: []
---

# WI-02 — Backend Pose-Extract runtime

- Keep extraction submission as `202` job start with no persisted Pose.
- Materialize one Pose as `201` only after a succeeded job, with all three media roles and ownerAccountId.
- Use PoseStore and published CommunityPose projection; isolate legacy schema compatibility.
- Acceptance: route, worker, store, schema, and API tests pass.
