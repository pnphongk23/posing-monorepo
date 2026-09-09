---
name: harness-plan
description: Create or update an ordered Harness implementation plan under the canonical plan directory.
---

# Harness Plan

Follow `docs/harness/workflows/plan.md`. Use `docs/harness/plans/YYMMDD-HHmm-kebab-slug/plan.md`, optional sibling `design.md`, and ordered `work-item-XX-kebab-name.md` files.

At every supported boundary, the agent must run the appropriate CLI command before reasoning about or mutating state:
- Use `ckh plan create` to scaffold.
- Use `ckh workflow status` to inspect status.
- Use `ckh workflow check` to validate.
- Use `ckh plan approve` to record Repository Maintainer approval.
- Use `ckh plan request-changes` to handle change requests.

For full lifecycle semantics, targets, validation, manual fallback, and the recovery boundary, refer to `docs/harness/workflows/plan.md`.

Apply local `scout`, `ask`, and `brainstorm` behavior for evidence, unresolved material choices, and adversarial review. Verify ownership, paths, symbols, dependencies, links, coverage, commands, and success criteria; finish a whole-Plan consistency sweep before requesting approval. Make no application change while planning.
