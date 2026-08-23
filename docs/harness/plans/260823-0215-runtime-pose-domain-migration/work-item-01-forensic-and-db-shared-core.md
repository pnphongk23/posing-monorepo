---
work_item: 1
title: Forensic review and DB/shared core
status: completed
priority: P1
effort: M
dependencies: []
decision_dependencies: []
---

# WI-01 — Forensic review and DB/shared core

- Record dirty-baseline provenance without reset or destructive cleanup.
- Align SQLDelight Pose/Photo schema and repository APIs to UUID `poseId`, required owner, and original/skeleton/thumbnail.
- Preserve only non-destructive, deprecated compatibility adapters.
- Acceptance: shared production compile succeeds and migration tests cover stable IDs, required media, and recoverable deletion.
