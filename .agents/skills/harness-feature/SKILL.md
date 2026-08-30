---
name: harness-feature
description: Discover, clarify, or reverse-engineer business behavior into a five-section Feature document; use for requirements before implementation.
---

# Harness Feature

Follow `docs/harness/workflows/feature.md` and `docs/harness/templates/feature.md`. Read `docs/harness/index.md` first.

At every supported boundary, the agent must run the appropriate CLI command before reasoning about or mutating state:
- Use `ckh feature create` to scaffold.
- Use `ckh workflow check` to validate.
- Use `ckh feature approve` to record Product Authority approval.
- Use `ckh feature request-changes` to handle change requests.

For full lifecycle semantics, targets, validation, manual fallback, and the recovery boundary, refer to `docs/harness/workflows/feature.md`.

Apply local `scout`, `ask`, and `brainstorm` behavior in that order where the workflow requires it. Stop at an approved Feature document. Keep observations, inferences, failures, and unresolved TBDs distinct; never choose a material variant for Product Authority. Do not modify application code or proceed into planning.
