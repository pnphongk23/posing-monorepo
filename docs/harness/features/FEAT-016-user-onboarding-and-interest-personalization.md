---
schema_version: 1
type: feature
id: FEAT-016
title: User Onboarding and Interest Personalization
status: proposed
created: 2026-09-06
relationships:
  specs:
    - "[[product-delivery-roadmap|Product Delivery Roadmap]]"
    - "[[product-feature-inventory]]"
    - "[[technical-architecture|Technical Architecture]]"
    - "[[ui-ux-system|UI/UX System]]"
  decisions: []
  plans: []
  reports: []
  rules: []
  features:
    - "[[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]"
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-012-restore-pose-and-camera-settings-across-relaunch|FEAT-012]]"
    - "[[FEAT-015-manage-app-settings-and-preferences|FEAT-015]]"
  source_paths:
    - docs/prototype/onboarding-research.md
    - docs/prototype/screens/onboarding.html
    - docs/prototype/styles/onboarding.css
    - docs/prototype/scripts/onboarding.js
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/App.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/platform/ExternalActions.kt
---

# FEAT-016: User Onboarding and Interest Personalization

## Introduction

**Purpose:** Provide a high-converting, value-first First-Time User Experience (FTUE) on mobile. The onboarding flow introduces the core value proposition of posing, allows users to personalize their pose catalog by selecting shooting interests (X and Reddit model), provides an interactive pose alignment trial (Duolingo Time-to-Value model), primes camera and photo permissions with transparent privacy disclosures, and hands off smoothly to the camera or personalized pose catalog.

**In scope:**
1. First-launch detection via local preference persistence (`has_completed_onboarding`).
2. Five-stage progressive onboarding experience:
   - Stage 1: Welcome & Value Hook (core benefit, visual stick-figure matching animation).
   - Stage 2: Interest & Vibe Personalization (multi-select neo-brutalist chips: Portrait, Cafe, Travel, Streetwear, Fitness, Couples, Professional).
   - Stage 3: Interactive Pose Match Playground (interactive alignment slider demonstrating ghost overlay locking onto a subject with real-time feedback).
   - Stage 4: Privacy & Permissions Primer (contextual explanation of Camera and Photo Library needs, on-device AI privacy pledge, dual action paths).
   - Stage 5: Personalized Launchpad & Handoff (summary of curated vibe matches with direct routing to Camera or Pose Catalog).
3. Non-blocking skip affordance accessible from early stages.
4. Local persistence of selected preferences (`user_selected_interests`) without requiring mandatory account creation.
5. Replayability via Settings hub (`FEAT-015`).

**Out of scope:**
- Redefining camera capture controls, shutter mechanics, or camera settings (`FEAT-001`, `FEAT-012`).
- Mandatory user registration, email sign-up, or identity management (`FEAT-014` owns Account; onboarding is 100% guest-accessible).
- Paywall presentation or hard subscription gating during first-launch onboarding (`FEAT-011` owns in-app purchases and paywall triggers).
- Backend pose extraction or operator tooling (`FEAT-004`, `FEAT-007`).

**Evidence summary:**
- **Observed:**
  - `mobile/composeApp/src/commonMain/kotlin/com/aipose/App.kt` initializes `TabNavigator(tab = PosesTab)` directly on startup without checking first-run onboarding state.
  - `docs/prototype/` contains complete neo-brutalist design tokens (`tokens.css`) and interactive screen simulations (`poses-list.html`, `camera-live.html`, `settings.html`).
  - `docs/prototype/onboarding-research.md` audits modern mobile onboarding patterns (X topic selection, Reddit cold-start mitigation, Duolingo interactive micro-wins, Apple HIG 5.1.1 permission guidelines).
  - An interactive prototype candidate is deployed in `docs/prototype/screens/onboarding.html`, `docs/prototype/styles/onboarding.css`, and `docs/prototype/scripts/onboarding.js`.
  - `docs/prototype/screens/settings.html` includes a "Replay onboarding" entry point.
- **Inferred:**
  - Onboarding state should be tracked through a lightweight key-value store or SQLDelight settings table in `commonMain` so Voyager navigation can conditionally present `OnboardingScreen` before mounting `TabNavigator`.
  - Selected vibe interests should feed directly into the default category/filter state of `FEAT-003` Pose Library.
- **Failed:**
  - Bounded inspection confirms there is currently zero onboarding implementation, first-run flag check, or category preference storage in `mobile/composeApp`.
  - No permission primer screen exists prior to invoking native iOS permission APIs in `CameraContract.ios.kt`.
- **Resolved (Product Authority):**
  - PA-016-01: Onboarding must not force account sign-up; guests must be allowed to complete onboarding and use the app immediately.
  - PA-016-02: Permission priming must precede system prompts; users who tap "Maybe Later" must still enter the app without camera lockouts.
  - PA-016-03: Selected interests must be editable later via Settings or Pose Library filter tabs.
  - PA-016-04: The entire onboarding flow must be replayable at any time from Settings.

---

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| First-time Photographer | Person / End User | Understand how posing works and quickly find poses matching their photography style | Complete or skip onboarding and explore poses |
| Returning User / Re-installer | Person / End User | Revisit the tutorial or re-configure preferred pose vibes | Trigger replay from Settings |
| Product Authority | Business role | Ensure user retention, minimize initial churn, and maintain Apple App Store compliance | Approve business boundary and acceptance criteria |

### User needs

1. **Immediate Clarity:** Understand what "Ghost Pose Matching" means before having to point their camera at anyone.
2. **Personalized Relevance:** Avoid browsing through hundreds of irrelevant poses by selecting preferred categories upfront.
3. **Privacy Assurance:** Verify that camera frames and captured personal photos are processed on-device and not sent to external servers.
4. **Freedom of Exploration:** Ability to skip the onboarding flow immediately if they want to jump straight to the app.

### Preconditions

1. For cold start: App is launched and local storage records `has_completed_onboarding != true`.
2. For replay: User taps "Replay onboarding" inside Settings (`FEAT-015`).

### Trigger

- First application launch after installation; or
- User navigation from `SettingsScreen` → "Replay onboarding".

### Main flow

1. **Actor:** The user launches the app on cold start. **System:** The system checks local storage and presents Stage 1 Welcome and Value Hook with the animated stick-figure guide.
2. **Actor:** The user selects one or more interest vibe chips. **System:** The system updates the selection count dynamically and enables the Continue action.
3. **Actor:** The user drags the alignment trial slider. **System:** The system updates the simulated viewfinder ghost overlay and displays green matched feedback when within tolerance.
4. **Actor:** The user reviews the permission explanation and selects enable camera access. **System:** The system records the consent intent and invokes the camera permission prompt; Photo Library permission is deferred to contextual in-app actions (import/save).
5. **Actor:** The user selects launch camera or browse poses. **System:** The system persists has_completed_onboarding as true, saves the selected interest categories, and transitions to the chosen destination.

### Alternative flows

- **A1 — Early skip.** Source step: 1. Condition: The user chooses to skip onboarding at Stage 1, 2, or 3. Behavior: The system marks has_completed_onboarding as true with default general categories and transitions directly to the pose catalog. Ends with: The user enters the main application without completing the remaining onboarding stages.
- **A2 — Permission deferred.** Source step: 4. Condition: The user selects Maybe Later on the permission primer. Behavior: The system records camera_permissions_status as deferred and advances to Stage 5 without invoking the native operating system prompt. Ends with: The user completes onboarding and enters the application with camera permissions unprompted.
- **A3 — Replay from Settings.** Source step: 1. Condition: An existing user triggers Replay onboarding from Settings. Behavior: The system presents the onboarding flow and updates the stored interest preferences upon completion. Ends with: The user returns to the Settings surface.

### Exception flows

- **E1 — Local preference persistence fails.** Source step: 5. Failure: Local storage write operation fails. Handling: Retain session preferences in memory and permit the user to proceed into the application. Prohibited: Reporting false persistent success or blocking navigation with a fatal crash. Failure postcondition: The user can access the application in a temporary session.
- **E2 — Flow interrupted prematurely.** Source step: 2. Failure: The application process is terminated before completing onboarding. Handling: Maintain has_completed_onboarding as false so the flow restarts cleanly on the next cold launch. Prohibited: Leaving the application in a partially initialized or corrupted navigation state. Failure postcondition: The user restarts the onboarding flow on the subsequent launch.

### Postconditions

- **Success:** has_completed_onboarding is set to true, selected interest categories are saved, and the application displays Camera or Pose Catalog.
- **Failure:** has_completed_onboarding remains false and no corrupted state prevents subsequent cold launch.

---

## Requirements

- **FR-016-01 [First-Run Routing]:** The application shall check local persistent storage on cold launch. If `has_completed_onboarding` is false or absent, the application shall present the Onboarding flow before displaying the main tab navigation.
- **FR-016-02 [Multi-Stage Progress]:** The onboarding flow shall display a top progress bar indicating progress across five distinct stages, with an accessible back button on Stages 2–5.
- **FR-016-03 [Interest & Vibe Selection]:** The system shall provide an interest selection surface containing categorized pose vibes (Portrait, Cafe, Travel, Street, Fitness, Couples, Professional). Users must select at least one interest to proceed, with real-time visual feedback on selection count.
- **FR-016-04 [Interactive Pose Matching Trial]:** The system shall include a risk-free interactive simulation where users adjust an alignment control to see a ghost overlay transition from unaligned (pink/dashed) to aligned (green/solid) with real-time feedback.
- **FR-016-05 [Contextual Permission Primer]:** Before triggering native operating system permission dialogs for Camera, the system shall present a transparent explanation detailing the purpose (live viewfinder overlay guide) and a privacy pledge stating that joint processing is performed 100% on-device. Photo Library access shall remain deferred to contextual in-app actions (import/save).
- **FR-016-06 [Graceful Permission Fallback]:** The permission primer shall offer an explicit "Maybe Later" option. Selecting this option shall not block completion of onboarding or app entry.
- **FR-016-07 [Non-Blocking Skip]:** A "Skip" control shall be available in Stages 1 to 3, allowing users to bypass onboarding immediately with sensible defaults.
- **FR-016-08 [Replay Affordance]:** The Onboarding flow shall be accessible on demand from the Settings surface (`FEAT-015`), allowing returning users to re-experience the flow and update their interest preferences.

---

## Acceptance

- [ ] First-time app launch automatically renders the Onboarding flow.
- [ ] Tapping "Skip" marks onboarding complete and immediately opens the Pose Catalog.
- [ ] Interest selection requires at least 1 category selected to proceed to Step 3.
- [ ] The interactive pose alignment slider triggers a visual "PERFECT MATCH!" state when within tolerance.
- [ ] Permission primer card clearly displays Camera access rationale with on-device privacy guarantee, while Photo Library permission remains contextual.
- [ ] Tapping "Maybe Later" on the permission primer completes onboarding without error.
- [ ] Tapping "Open Camera with Guide" routes to the live camera viewfinder.
- [ ] Tapping "Browse Recommended Poses" routes to the Pose Catalog with interests applied.
- [ ] Tapping "Replay onboarding" from Settings successfully opens the onboarding flow.

### Verification Scenarios

**Scenario 1: Standard First-Run Happy Path**
- **Given** a new user installs and opens posing for the first time
- **When** the app completes initialization
- **Then** the Onboarding Welcome screen (Stage 1) is displayed
- **When** the user taps "Get Started" and selects "Portrait & Selfie" and "Cafe & Aesthetic"
- **And** completes the interactive alignment slider trial
- **And** taps "Enable Camera Access"
- **Then** Stage 5 displays the curated summary matching the two selected categories
- **When** the user taps "Open Camera with Guide"
- **Then** the camera viewfinder is displayed and `has_completed_onboarding` is persisted as true.

**Scenario 2: Early Skip Path**
- **Given** a first-time user lands on Stage 1 of Onboarding
- **When** the user taps "Skip"
- **Then** the app immediately transitions to `PosesTab`
- **And** subsequent cold app launches bypass onboarding.

**Scenario 3: Permission Deferred Path**
- **Given** a user is on Stage 4 (Permission Primer)
- **When** the user taps "Maybe Later"
- **Then** no native OS permission dialog is triggered
- **And** the user proceeds to Stage 5 and successfully enters the app.

**Scenario 4: Settings Replay Path**
- **Given** an existing user opens Settings
- **When** the user taps "Replay onboarding"
- **Then** the Onboarding screen is presented starting at Stage 1
- **And** exiting or completing returns the user to the application.

---

## Relationships

- **Specs:**
  - `[[product-delivery-roadmap|Product Delivery Roadmap]]` — Delivery scheduling.
  - `[[product-feature-inventory]]` — Feature inventory and boundaries.
  - `[[technical-architecture|Technical Architecture]]` — Client architecture and state storage.
  - `[[ui-ux-system|UI/UX System]]` — Neo-brutalist design tokens and interaction standards.
- **Features:**
  - `[[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]` — Handoff target for Camera capture.
  - `[[FEAT-003-browse-and-search-published-poses|FEAT-003]]` — Handoff target for personalized pose feed.
  - `[[FEAT-012-restore-pose-and-camera-settings-across-relaunch|FEAT-012]]` — Camera settings boundary.
  - `[[FEAT-015-manage-app-settings-and-preferences|FEAT-015]]` — Replay onboarding entry point.
- **Source Paths:**
  - `docs/prototype/onboarding-research.md` — UX research and competitive teardown.
  - `docs/prototype/screens/onboarding.html` — Interactive 5-stage screen prototype.
  - `docs/prototype/styles/onboarding.css` — Neo-brutalist prototype styles.
  - `docs/prototype/scripts/onboarding.js` — Interactive prototype script.
  - `mobile/composeApp/src/commonMain/kotlin/com/aipose/App.kt` — App entry point & navigator mounting.
  - `mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt` — Tab & screen navigation contracts.
  - `mobile/composeApp/src/commonMain/kotlin/com/aipose/platform/ExternalActions.kt` — Platform permission and settings actions.
