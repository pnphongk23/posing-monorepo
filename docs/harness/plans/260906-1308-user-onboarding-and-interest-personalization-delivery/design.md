# Technical Design — User Onboarding and Interest Personalization

> **Plan-Local Technical Design for FEAT-016**  
> **Location:** `docs/harness/plans/260906-1308-user-onboarding-and-interest-personalization-delivery/design.md`  
> **Author:** Paseo Team — Lead Architect & Code King  
> **Date:** 2026-09-06

---

## 1. Overview & Architectural Goals

The goal of this design is to deliver an engaging, rock-solid, and decoupled First-Time User Experience (FTUE) in Compose Multiplatform targeting iOS (and forward-compatible with Android), matching the prototype in `docs/prototype/screens/onboarding.html` and governed by `FEAT-016`.

### Key Constraints & Design Principles
1. **Zero Mandatory Network/Auth Blocking:** Onboarding operates entirely offline and local-first. Guests can complete the flow in <30 seconds without creating an account or hitting a paywall.
2. **Clean Navigation Seam:** App entry routing checks onboarding completion before mounting the tab dock. Replay from Settings pushes `OnboardingScreen` as an overlay screen without breaking the root `TabNavigator`.
3. **Decoupled Preference Store:** Preference persistence is handled via a lightweight interface (`OnboardingPreferencesRepository`) backed by SQLDelight or Key-Value storage, testable with in-memory fakes.
4. **Interactive Simulation Without Hardware Dependencies:** Stage 3 (Pose Alignment Trial) simulates camera overlay mechanics purely in Compose Canvas / vector math, requiring no camera hardware or camera permissions.
5. **HIG-Compliant Permission Gate:** Native iOS camera permission prompt is only invoked after user taps "Enable Camera Access" on the contextual primer card (Stage 4). Photo Library permission remains deferred and is requested contextually upon first save or import (`FEAT-001`/`FEAT-002`), conforming to Apple HIG 5.1.1.

---

## 2. Navigation Architecture

```text
┌────────────────────────────────────────────────────────┐
│                        App.kt                          │
│               Root Startup Resolution                  │
└────────────────────────────────────────────────────────┘
                           │
       hasCompletedOnboarding? (read repository)
              ┌────────────┴────────────┐
             No                        Yes
              ▼                         ▼
┌───────────────────────────┐ ┌───────────────────────────┐
│     OnboardingScreen      │ │    TabNavigator(Poses)    │
│  (Voyager Screen Stack)   │ │  - PosesTab (FEAT-003)    │
│  Stages 1 -> 2 -> 3-> 4->5│ │  - CameraTab (FEAT-001)   │
└───────────────────────────┘ │  - GalleryTab (FEAT-002)  │
              │               └───────────────────────────┘
              │                              ▲
              │ [Complete or Skip]           │
              └──────────────────────────────┘
```

### Routing Invariants
- **First-Run Path:** `App.kt` inspects `onboardingState.hasCompleted`. If `false`, renders `OnboardingScreen(onComplete = { ... })`.
- **Handoff from Stage 5:**
  - `onLaunchCamera`: marks completed, sets `TabNavigator(tab = CameraTab)`.
  - `onBrowsePoses`: marks completed, sets `TabNavigator(tab = PosesTab)`.
  - `onSkip`: marks completed with general defaults, sets `TabNavigator(tab = PosesTab)`.
- **Replay Path (from Settings):** `SettingsScreen` invokes `navigator.push(OnboardingScreen(isReplay = true))`. On finish or back, pops back to Settings.

---

## 3. Data Contracts & State Machine

### 3.1 Pose Vibe Enum & Models

```kotlin
package com.aipose.onboarding

enum class PoseVibe(val id: String, val displayName: String, val icon: String) {
    PORTRAIT("portrait", "Portrait & Selfie", "📸"),
    CAFE("cafe", "Cafe & Aesthetic", "☕"),
    TRAVEL("travel", "Travel & Landmarks", "✈️"),
    STREET("street", "Street & OOTD", "👟"),
    FITNESS("fitness", "Fitness & Gym", "🏋️"),
    COUPLES("couples", "Couples & Duo", "👥"),
    PROFESSIONAL("professional", "Headshots & Work", "🏢")
}

data class OnboardingState(
    val stage: OnboardingStage = OnboardingStage.WELCOME,
    val selectedVibes: Set<PoseVibe> = setOf(PoseVibe.PORTRAIT, PoseVibe.CAFE),
    val alignmentSliderValue: Float = 30f, // -35f to +35f, sweet spot within [-8f, +8f]
    val isPoseAligned: Boolean = false,
    val permissionsGranted: Boolean = false,
    val isReplay: Boolean = false
)

enum class OnboardingStage(val stepNumber: Int) {
    WELCOME(1),
    VIBE_SELECTION(2),
    INTERACTIVE_TRIAL(3),
    PERMISSION_PRIMER(4),
    READY_LAUNCHPAD(5)
}
```

### 3.2 Preference Store Interface

```kotlin
package com.aipose.onboarding

import kotlinx.coroutines.flow.Flow

interface OnboardingPreferencesRepository {
    fun hasCompletedOnboarding(): Flow<Boolean>
    suspend fun setCompletedOnboarding(completed: Boolean)
    
    fun getSelectedVibes(): Flow<Set<PoseVibe>>
    suspend fun setSelectedVibes(vibes: Set<PoseVibe>)
}
```

---

## 4. UI Component Hierarchy (Compose Multiplatform)

```text
OnboardingScreen
├── OnboardingTopBar
│   ├── BackButton (disabled on Stage 1)
│   ├── NeoBrutalistProgressBar (20% -> 100%)
│   └── SkipButton (hidden on Stage 4 and 5)
├── AnimatedContent (OnboardingStage transition)
│   ├── Stage1WelcomeContent
│   │   ├── Badge ("AI-Powered Guide")
│   │   ├── HeroGraphic (Stick figure animated guide)
│   │   ├── FeatureHighlightList
│   │   └── PrimaryCtaButton ("Get Started")
│   ├── Stage2VibePickerContent
│   │   ├── Title & Subtitle
│   │   ├── SelectionCounterText ("X of 7 selected")
│   │   ├── FlowRow (NeoBrutalistChip for each PoseVibe)
│   │   └── PrimaryCtaButton ("Continue (X)", enabled when >= 1)
│   ├── Stage3InteractiveTrialContent
│   │   ├── Title & Subtitle
│   │   ├── SimulatedViewfinderBox
│   │   │   ├── CameraGridOverlay
│   │   │   ├── StaticModelSilhouette (Subject)
│   │   │   ├── MovableGhostSilhouette (Offset by slider)
│   │   │   └── MatchBanner ("PERFECT MATCH!", visible when aligned)
│   │   ├── SliderControlPanel (RangeSlider: -35 to +35)
│   │   └── PrimaryCtaButton ("Next: Quick Privacy Check")
│   ├── Stage4PermissionPrimerContent
│   │   ├── Title & Subtitle
│   │   ├── PermissionRow (Camera Access for Live Guides)
│   │   ├── ContextualNote (Photos permission requested when saving/importing)
│   │   ├── PrivacyPledgeBox (100% on-device AI joint detection)
│   │   ├── PrimaryCtaButton ("Enable Camera Access")
│   │   └── SecondaryCtaButton ("Maybe Later")
│   └── Stage5ReadyLaunchpadContent
│       ├── SuccessCheckIcon
│       ├── Title & Subtitle
│       ├── CuratedVibePillRow
│       ├── PrimaryCtaButton ("Open Camera with Guide")
│       └── SecondaryCtaButton ("Browse Recommended Poses")
```

---

## 5. Testing Strategy

1. **Unit Tests (`commonTest`):**
   - `OnboardingViewModelTest`: Verify state transitions across Stages 1–5, selection counter, alignment calculation (slider value in sweet spot activates `isPoseAligned`), and persistence invocation.
   - `OnboardingPreferencesRepositoryTest`: Test fake in-memory repository reading/writing `hasCompletedOnboarding` and `selectedVibes`.
2. **UI Component Tests (`commonTest` / Compose Test):**
   - Verify Stage 2 "Continue" button disables when zero vibes are selected.
   - Verify "Skip" button triggers completion with fallback defaults.
   - Verify Stage 3 slider interaction triggers green match banner.
3. **Integration Test:**
   - App startup test verifying that when `hasCompletedOnboarding == false`, `OnboardingScreen` is the initial destination, and after completion, `TabNavigator` mounts properly.
