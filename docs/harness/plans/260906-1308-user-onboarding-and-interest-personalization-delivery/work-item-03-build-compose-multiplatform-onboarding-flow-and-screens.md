---
work_item: 3
title: Build Compose Multiplatform Onboarding Flow and Screens
status: pending
priority: P2
effort: L
dependencies:
  - 1
  - 2
decision_dependencies: []
---

# Work Item 3: Build Compose Multiplatform Onboarding Flow and Screens

## Kind

`story` / `technical`

## Goal

Build the 5-stage Compose Multiplatform UI for `OnboardingScreen`, replicating the neo-brutalist styling, interaction mechanics, and animations proven in `docs/prototype/screens/onboarding.html`.

## Tasks

- [ ] Create `OnboardingScreen.kt` conforming to Voyager `Screen`.
- [ ] Build the neo-brutalist top bar with back navigation, animated progress bar (`20%` to `100%`), and skip action.
- [ ] Implement Stage 1: Welcome hero with animated stick-figure pose guide and key value cards.
- [ ] Implement Stage 2: Goal and vibe selection matrix with multi-select chips (`FlowRow`), dynamic counter badge, and reactive CTA enablement.
- [ ] Implement Stage 3: Interactive Pose Match Playground featuring a simulated camera viewfinder, model silhouette, movable ghost overlay, alignment slider, and green "MATCHED!" indicator when within tolerance.
- [ ] Implement Stage 4: Privacy and permissions primer card with Camera and Photo Library rationale and on-device AI privacy pledge.
- [ ] Implement Stage 5: Personalized launchpad displaying selected vibe pills, "Open Camera with Guide" primary CTA, and "Browse Recommended Poses" secondary CTA.
- [ ] Enforce repository neo-brutalist tokens (2px solid black borders, 3px hard offset shadows, `#E89CAE` pink, `#7FBBE6` blue, `#FED766` yellow, `#B5E2B9` green).

## Scope and affected files

- `mobile/composeApp/src/commonMain/kotlin/com/aipose/onboarding/OnboardingScreen.kt`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/onboarding/OnboardingComponents.kt`
- `mobile/composeApp/src/commonTest/kotlin/com/aipose/onboarding/OnboardingViewModelTest.kt`

## Success criteria

- All 5 stages render accurately on phone viewports with accessible touch targets (≥44dp).
- Slider interaction smoothly updates the ghost overlay position and triggers green aligned feedback within the sweet spot.
- Stage 2 correctly disables "Continue" when 0 interests are selected and enables when ≥1 selected.
- Unit and UI tests verify state progression across all 5 stages.

## Risks

- Layout overflow or clipping on smaller devices (e.g. iPhone SE / 375pt).
  - *Mitigation:* Wrap stage content in a vertical scroll container with sticky bottom dock for primary CTA buttons.

## Required evidence

- Compose preview / unit tests verifying state transitions and interactive alignment calculation pass cleanly.
