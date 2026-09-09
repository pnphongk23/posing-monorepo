---
name: harness-cook
description: Implement an approved harness plan Work Item by Work Item, verify results, and write a delivery report.
---

# Harness Cook

Follow `docs/harness/workflows/cook.md` and the approved plan. Work through one Work Item at a time, run its checks, review side effects, and write a report using `docs/harness/templates/report.md`.

At every supported boundary, the agent must run the appropriate CLI command before reasoning about or mutating state:
- Use `ckh workflow status` to determine eligibility.
- Use `ckh workflow check` to verify consistency.
- Use `ckh work-item set-status` to change Work Item status.
- Use `ckh plan set-status` to update aggregate Plan status.

For full lifecycle semantics, targets, validation, manual fallback, and the recovery boundary, refer to `docs/harness/workflows/cook.md`.

Never claim a check passed without direct evidence. Source-control and delivery operations require a separate explicit request.
