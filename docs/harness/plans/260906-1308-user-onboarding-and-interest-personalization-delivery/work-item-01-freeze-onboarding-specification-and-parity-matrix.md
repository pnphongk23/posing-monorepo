---
work_item: 1
title: Freeze Onboarding Specification and Parity Matrix
status: pending
priority: P2
effort: S
dependencies: []
decision_dependencies: []
---

# Work Item 1: Freeze Onboarding Specification and Parity Matrix

## Kind

`docs` / `technical`

## Goal

Freeze the observable behavior contracts, prototype parity matrix, and domain models for FEAT-016 User Onboarding and Interest Personalization.

## Tasks

- [ ] Reconcile `FEAT-016` requirements against the interactive prototype in `docs/prototype/screens/onboarding.html`.
- [ ] Define the canonical `PoseVibe` enum (`PORTRAIT`, `CAFE`, `TRAVEL`, `STREET`, `FITNESS`, `COUPLES`, `PROFESSIONAL`) and default interest selections.
- [ ] Freeze the 5-stage state transitions and validation constraints (minimum 1 interest selected, alignment slider tolerance window ±8 units).
- [ ] Specify the permission primer boundary and verify non-blocking "Maybe Later" semantics.

## Scope and affected files

- `docs/harness/features/FEAT-016-user-onboarding-and-interest-personalization.md`
- `docs/harness/plans/260906-1308-user-onboarding-and-interest-personalization-delivery/design.md`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/onboarding/OnboardingContract.kt`

## Success criteria

- `FEAT-016` behavior contracts, data structures, and edge cases are 100% frozen.
- Parity matrix verifies 1:1 match between prototype stages and Compose Multiplatform component requirements.
- Zero unresolved domain ambiguity before implementation.

## Risks

- Divergence between prototype HTML/CSS interaction models and Compose Multiplatform capabilities.
  - *Mitigation:* `design.md` specifies standard Compose primitives (`RangeSlider`, `FlowRow`, `AnimatedContent`) that directly replicate prototype behavior.

## Required evidence

- `ckh workflow check FEAT-016` passes with zero errors.
- Parity matrix table documented in `design.md`.
