---
work_item: 5
title: Verify Onboarding Delivery Across Unit Tests and iOS Baseline
status: pending
priority: P2
effort: M
dependencies:
  - 1
  - 2
  - 3
  - 4
decision_dependencies: []
---

# Work Item 5: Verify Onboarding Delivery Across Unit Tests and iOS Baseline

## Kind

`verification`

## Goal

Execute the verification matrix across unit tests, Compose component tests, and iOS build baseline to validate complete delivery of FEAT-016.

## Tasks

- [ ] Execute `OnboardingViewModelTest` and `OnboardingPreferencesRepositoryTest` in `commonTest`.
- [ ] Run Compose Multiplatform tests covering the 5 stages and interaction boundaries.
- [ ] Verify clean iOS compilation via `./gradlew :mobile:composeApp:compileKotlinIosX64`.
- [ ] Run Harness validation (`ckh validate --all` and `ckh workflow check`).
- [ ] Rebuild Harness index and graph (`ckh index build`, `ckh graph build`).

## Scope and affected files

- `mobile/composeApp/src/commonTest/kotlin/com/aipose/onboarding/`
- `docs/harness/plans/260906-1308-user-onboarding-and-interest-personalization-delivery/plan.md`

## Success criteria

- All unit and integration tests pass with 0 failures.
- Zero regression on existing camera or navigation test suites.
- Harness validation commands exit with code 0.

## Risks

- Platform-specific iOS linking issues with new Compose animations or assets.
  - *Mitigation:* Bounded vector math and native system font stack with zero external binary font dependencies.

## Required evidence

- Test logs showing 100% test pass rate.
- `ckh workflow check` passing for FEAT-016 and Plan.
