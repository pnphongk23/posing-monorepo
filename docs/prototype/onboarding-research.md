# Onboarding Design Research — AI Pose First-Time User Experience (FTUE)

> **Research & Architecture Note for FEAT-016**  
> **Author:** Paseo Team — Lead Architect & Code King  
> **Date:** 2026-09-06  
> **Applicable Specs & Features:** FEAT-016, FEAT-001 (Camera), FEAT-003 (Pose Library), FEAT-012 (Camera Settings), FEAT-015 (Settings Hub), `docs/harness/specs/ui-ux-system.md`, `design.md`.

---

## 1. Executive Summary & Problem Statement

### 1.1 The Cold Start Problem in AI Pose
When a first-time user installs **AI Pose**, they arrive with high expectations ("I want to look good in photos without feeling awkward") but zero context on how the core mechanic works. 

If dumped directly into an empty camera viewfinder or an uncategorized list of 200+ poses:
1. **Decision Paralysis:** The user doesn't know which pose fits their current setting (cafe, street, gym, portrait).
2. **Cognitive Disconnect:** The concept of "Ghost Pose Matching" (aligning joints with a translucent silhouette on a live viewfinder) is completely novel. Without a risk-free primer, users hesitate to open the camera.
3. **Permission Shock:** Prompting for iOS Camera and Photo Library permissions immediately upon cold launch triggers high bounce rates (industry average 40–60% denial when prompted without context).
4. **Retention Drop-off:** Industry benchmark data for 2025–2026 confirms that **~77% of mobile app users abandon apps within the first 3 days**. The primary driver is failure to achieve the **"Aha! Moment"** (Time-to-Value, TTV) in session one.

### 1.2 The Strategic Goal of FEAT-016 Onboarding
The onboarding experience must not be an administrative chore or a passive slideshow. It must be an **active, interactive value hook** that:
- Delivers the core "Aha! Moment" within **30 seconds** without requiring a camera roll photo.
- Collects 1–3 high-intent vibe/category preferences (Reddit/X model) to personalize the initial Pose Library feed.
- Transparently primes permissions with a local-first privacy pledge before the iOS system alert appears.
- Allows instant skipping for power users or re-installers, and provides replayability from Settings (`FEAT-015`).

---

## 2. Competitive & Modern Industry Teardown

### 2.1 X (formerly Twitter) — The Topic / Interest Selector
- **Pattern:** Full-screen progressive picker asking "What do you want to see on X?" categorized into punchy cards and sub-topic pill buttons.
- **Key UX Mechanics:**
  - **Goal-Oriented Chunking:** Grouped by broad domains (Entertainment, Tech, Sports, Lifestyle) with selectable pills.
  - **Dynamic Threshold CTA:** The primary CTA button ("Next") tracks progress dynamically, e.g., "Choose 3 or more" with an active count badge (`2/3 selected`).
  - **Tactile Feedback:** Selected pills invert contrast or apply brand accent borders with subtle micro-spring animations.
  - **Skip Affordance:** Explicit "Skip for now" in the top navigation bar prevents churn for users who want to jump straight to browsing.
- **AI Pose Translation:** Adopt tactile neo-brutalist interest chips for 7 canonical pose vibes: Portrait, Cafe, Travel, Street, Fitness, Couples, Professional. Pre-filters the community pose feed so the user's first catalog view is 100% relevant.

### 2.2 Reddit — Overcoming Cold Start via Community Seeding
- **Pattern:** After topic selection, Reddit immediately transitions into "Recommended Communities" with pre-checked top subreddits.
- **Key UX Mechanics:**
  - **Endowed Progress Effect:** Showing users that their feed is already being built ("Setting up your home feed...").
  - **Pre-Selected Defaults with Instant Customization:** Avoids the blank screen trap by offering curated popular picks while giving full control to uncheck or customize.
- **AI Pose Translation:** Following interest selection, present a tailored collection preview ("Curated 18 poses matching your vibes") before handoff to the camera or library.

### 2.3 Duolingo — Time-to-Value (TTV) via "Learning by Doing"
- **Pattern:** Zero passive slides. Within 15 seconds of launch, Duolingo drops the user into an interactive translation mini-exercise. The user completes one micro-task *before* ever being asked to sign up or configure settings.
- **Key UX Mechanics:**
  - **Immediate Micro-Win:** Achieving a micro-success triggers dopamine and validates product efficacy.
  - **Lazy Registration:** Account creation is deferred until after the first lesson.
- **AI Pose Translation:** Build an **Interactive Pose Match Demo** directly in the onboarding flow. A simulated camera viewport allows the user to drag an alignment slider or adjust silhouette opacity to see the ghost lines lock into green alignment. The user learns the core mechanic in 5 seconds without needing to stand up or take a real photo.

### 2.4 BeReal & Creator Camera Apps — Contextual Permission Priming
- **Pattern:** Camera and notification permissions are never requested cold. A high-contrast preflight card explains *why* access is required.
- **Key UX Mechanics:**
  - **The "Why" Card:** Visual icon + benefit-driven headline ("To show real-time pose overlays") + privacy pledge ("All joint detection runs 100% on your device").
  - **Dual Action Paths:** "Enable Camera Access" (launches native iOS prompt) and "Maybe Later" (graceful fallback).
  - **HIG Compliance:** Conforms to Apple HIG 5.1.1 (Data Collection & Permissions): explains data use prior to trigger, provides alternate path on denial.
- **AI Pose Translation:** Stage 4 dedicated permission primer card with neo-brutalist styling, explaining on-device AI privacy and giving both "Enable Access" and "Not Now" options.

---

## 3. Behavioral Psychology & UX Frameworks

| Psychology Principle | Mechanism in AI Pose Onboarding | Expected Impact* |
| --- | --- | --- |
| **The Hook Model** (Nir Eyal) | Trigger (desire for aesthetic photo) → Action (select interests & try demo) → Variable Reward (seeing personalized curated poses) → Investment (saved vibe preferences). | Increases D1/D7 retention by 25–35%. |
| **Endowed Progress Effect** | Step indicator (`Step 1 of 4`) starts filled at 25%, giving a sense of immediate forward momentum. | Reduces onboarding abandonment by 18%. |
| **Choice Architecture (Hick's Law)** | Curating 7 distinct, mutually clear pose vibe pills rather than an overwhelming 30-item taxonomy. | Minimizes cognitive friction and decision fatigue. |
| **Reciprocity Bias** | Delivering value (interactive demo + personalized curation) *before* asking for hardware permissions. | Increases camera permission acceptance rate by >30%. |

*\*Note: Percentage impacts are heuristic industry reference benchmarks from mobile UX retention studies (e.g. AppsFlyer, Mixpanel, and behavioral design literature).*

---

## 4. Architecture of the 5-Stage Onboarding Flow

```text
┌────────────────────────────────────────────────────────────────────────┐
│                        AI POSE ONBOARDING FLOW                         │
└────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│  STAGE 1: Welcome & Value Hook                                         │
│  - Headline: "Never look awkward in photos again."                     │
│  - Visual: Tactile stick-figure animation matching a photo frame.     │
│  - Value Points: Instant alignment guides • Curated creator library.   │
│  - Actions: [Get Started] | [Skip]                                     │
└────────────────────────────────────────────────────────────────────────┘
                                   │ [Next]
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│  STAGE 2: Goal & Vibe Personalization (Reddit / X Model)               │
│  - Prompt: "What do you shoot most?"                                   │
│  - Neo-Brutalist Chips: Portrait, Cafe, Travel, Street, Fitness,       │
│    Couples, Professional (7 canonical vibes).                          │
│  - Counter: "Selected: X/7" (Active CTA when >= 1).                    │
│  - Actions: [Continue] | [Back]                                        │
└────────────────────────────────────────────────────────────────────────┘
                                   │ [Next]
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│  STAGE 3: Interactive Pose Match Playground (Duolingo TTV Model)       │
│  - Simulation: Viewfinder with ghost pose silhouette overlay.          │
│  - Interactive Slider: Match / Opacity control.                        │
│  - Micro-Feedback: Joint nodes turn green when aligned ("MATCHED!").  │
│  - Actions: [Got It, Next] | [Back]                                    │
└────────────────────────────────────────────────────────────────────────┘
                                   │ [Next]
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│  STAGE 4: Smart Privacy & Permission Primer (Apple HIG Compliant)      │
│  - Pre-flight explanation: Camera Access upfront for live viewfinder   │
│    guide; Photo Library requested contextually upon first save/import. │
│  - Privacy Pledge: 100% on-device AI joint detection. No cloud upload. │
│  - Actions: [Enable Camera Access] | [Maybe Later]                     │
└────────────────────────────────────────────────────────────────────────┘
                                   │ [Granted or Deferred]
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│  STAGE 5: Personalized Launchpad & Handoff                             │
│  - Summary: "Your personalized guide is ready!" (18 curated poses).    │
│  - Dual Route CTA:                                                     │
│    1. [Open Camera with Guide] -> routes to camera-live.html           │
│    2. [Browse Recommended Poses] -> routes to poses-list.html          │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Design System Integration (Neo-brutalism)

The onboarding flow strictly adopts the repository's neo-brutalist design tokens from `docs/prototype/styles/tokens.css` and `design.md`:

- **Canvases:** Curated cream base tone (`#FBF6EF`) with slate desk backing (`#E2DDD5`).
- **Borders:** 2px solid black strokes (`var(--nb-border-thick)`) for all cards, buttons, and chips.
- **Shadows:** Rigid 3px hard offset black shadows (`3px 3px 0 #000`), depressing to `0px 0px 0 #000` on `:active`.
- **Accents:**
  - Pink (`#E89CAE`): Primary CTA ("Get Started", "Start Snapping").
  - Blue (`#7FBBE6`): Active selection pills and progress fill.
  - Yellow (`#FED766`): Notice badges, feature highlights, and tips.
  - Green (`#B5E2B9`): "Matched!" confirmation state and permission success indicator.
- **Typography:** System font stack targeting SF Pro with bold headers (`700`/`800`) and readable body copy (`14px`/`16px`).
- **Touch Targets:** All interactive chips and buttons enforce `min-height: 44px` (`--nb-touch-min`).

---

## 6. Edge Cases, Accessibility & Compliance

1. **Skipped Flow:** If the user taps "Skip" at Stage 1 or 2, default preferences (`portrait`, `cafe`) are saved, `has_completed_onboarding` is set to `true`, and navigation proceeds directly to `poses-list.html`.
2. **Permission Denial:** If the user taps "Maybe Later" or declines the native iOS prompt, the app records `permission_primer_handled: true`, does not block entry, and routes to `poses-list.html` where camera features will show an in-situ permission prompt when tapped (`FEAT-001`).
3. **Replayability:** Users can re-open onboarding anytime via **Settings → Help & Onboarding → Replay Onboarding Guide** (`FEAT-015`).
4. **Reduced Motion:** All transitions respect `prefers-reduced-motion: reduce`, replacing slide transforms with instant opacity transitions.
5. **Screen Readers:** ARIA live regions announce step changes (`aria-live="polite"`), and multi-select chips use `role="checkbox"` with `aria-checked`.

---

## 7. Next Steps in Harness Workflow
- **Deliverable 1:** Interactive Prototype in `docs/prototype/screens/onboarding.html` (with styles & scripts).
- **Deliverable 2:** Authoritative Feature Specification in `docs/harness/features/FEAT-016-user-onboarding-and-interest-personalization.md`.
- **Deliverable 3:** Implementation Plan in `docs/harness/plans/YYMMDD-HHmm-user-onboarding-delivery/` with sibling `design.md` and 5 Work Items.
