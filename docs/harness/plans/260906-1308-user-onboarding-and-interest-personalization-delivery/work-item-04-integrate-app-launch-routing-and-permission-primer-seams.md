---
work_item: 4
title: Integrate App Launch Routing and Permission Primer Seams
status: pending
priority: P2
effort: M
dependencies:
  - 3
decision_dependencies: []
---

# Work Item 4: Integrate App Launch Routing and Permission Primer Seams

## Kind

`technical`

## Goal

Wire `OnboardingScreen` into app launch routing in `App.kt`, connect platform permission primer actions, and hook up the Settings replay entry point (`FEAT-015`).

## Tasks

- [ ] Modify `App.kt` to inspect `has_completed_onboarding` on launch.
- [ ] Route uninitialized users to `OnboardingScreen` and initialized users to `TabNavigator(tab = PosesTab)`.
- [ ] Implement `OnboardingScreen` completion callbacks:
  - Launch Camera: sets tab to `CameraTab`.
  - Browse Poses / Skip: sets tab to `PosesTab` with selected vibe filters applied.
- [ ] Wire platform permission seams: tap on "Enable Camera Access" triggers camera permission request via `CameraContract.ios.kt`; Photo Library permission remains deferred to contextual in-app actions; tap on "Maybe Later" defers gracefully.
- [ ] Wire the "Replay onboarding" trigger in `SettingsScreen` to push `OnboardingScreen(isReplay = true)`.

## Scope and affected files

- `mobile/composeApp/src/commonMain/kotlin/com/aipose/App.kt`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/platform/ExternalActions.kt`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/settings/SettingsScreen.kt`

## Success criteria

- Cold launch on fresh install displays `OnboardingScreen` without flashing `PosesTab`.
- Completing or skipping onboarding transitions directly to the selected target without back-stack leaks.
- Replaying from Settings pushes onboarding and pops back cleanly to Settings.
- Permission deferral allows full guest navigation into `PosesTab`.

## Risks

- Flash of main tab content before onboarding check resolves.
  - *Mitigation:* Hold a neutral splash / loading container until the initial `hasCompletedOnboarding` state emits.

## Required evidence

- `AppLaunchTest` verifying routing to `OnboardingScreen` on `hasCompleted = false` and `PosesTab` on `true`.
