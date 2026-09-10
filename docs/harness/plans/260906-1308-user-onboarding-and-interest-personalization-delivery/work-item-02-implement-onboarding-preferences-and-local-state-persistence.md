---
work_item: 2
title: Implement Onboarding Preferences and Local State Persistence
status: pending
priority: P2
effort: M
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 2: Implement Onboarding Preferences and Local State Persistence

## Kind

`technical`

## Goal

Implement the persistent key-value / SQLDelight storage layer to track `has_completed_onboarding` and store the user's `selected_pose_categories`.

## Tasks

- [ ] Define the `OnboardingPreferencesRepository` interface in `commonMain`.
- [ ] Implement local persistence using SQLDelight `AppPreferences` or platform Key-Value adapter (`NSUserDefaults` on iOS).
- [ ] Ensure coroutine-friendly reactive observation via Kotlin `StateFlow` / `Flow<Boolean>` and `Flow<Set<PoseVibe>>`.
- [ ] Write unit tests with an in-memory test repository verifying persistence roundtrips, default fallback values, and edge-case error recovery.

## Scope and affected files

- `mobile/composeApp/src/commonMain/kotlin/com/aipose/onboarding/OnboardingPreferencesRepository.kt`
- `mobile/composeApp/src/commonTest/kotlin/com/aipose/onboarding/OnboardingPreferencesRepositoryTest.kt`
- `mobile/shared/src/commonMain/sqldelight/com/aipose/Pose.sq` (if schema extension needed)

## Success criteria

- `has_completed_onboarding` returns false on fresh install and true after `setCompletedOnboarding(true)`.
- `selected_pose_categories` accurately persists and retrieves sets of `PoseVibe` enums.
- Unit tests pass with 100% determinism.

## Risks

- Corrupted local storage crashing app cold launch.
  - *Mitigation:* Implement defensive try-catch wrappers returning safe defaults (`hasCompleted = false`, `defaultVibes = [PORTRAIT, CAFE]`) on read/write failures.

## Required evidence

- `./gradlew :mobile:composeApp:testDebugUnitTest --tests com.aipose.onboarding.OnboardingPreferencesRepositoryTest` or equivalent multiplatform test command exits with code 0.
