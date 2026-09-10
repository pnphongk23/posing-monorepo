---
title: User Onboarding and Interest Personalization Delivery
description: "Implementation plan for FEAT-016 User Onboarding and Interest Personalization in Compose Multiplatform, delivering an interactive 5-stage FTUE, interest selection, pose alignment trial, and permission priming."
status: pending
approval:
  status: pending
  required_by: Repository Maintainer
priority: P2
effort: M
branch: codex/user-onboarding-and-interest-personalization-delivery
tags:
  - feat-016
  - onboarding
  - mobile
  - compose-multiplatform
  - ftue
blockedBy: []
blocks: []
relationships:
  specs:
    - "[[product-delivery-roadmap|Product Delivery Roadmap]]"
    - "[[product-feature-inventory]]"
    - "[[ui-ux-system|UI/UX System]]"
    - "[[technical-architecture|Technical Architecture]]"
  decisions: []
  plans: []
  reports: []
  rules: []
  features:
    - "[[FEAT-016-user-onboarding-and-interest-personalization|FEAT-016]]"
  source_paths:
    - docs/harness/features/FEAT-016-user-onboarding-and-interest-personalization.md
    - docs/harness/plans/260906-1308-user-onboarding-and-interest-personalization-delivery/design.md
    - docs/prototype/onboarding-research.md
    - docs/prototype/screens/onboarding.html
    - docs/prototype/styles/onboarding.css
    - docs/prototype/scripts/onboarding.js
    - docs/prototype/screens/settings.html
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/App.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/platform/ExternalActions.kt
created: 2026-09-06T13:08:47+07:00
createdBy: Harness CLI
---

# User Onboarding and Interest Personalization Delivery

## Overview

This Plan translates **FEAT-016 User Onboarding and Interest Personalization** into a sequenced, deterministic set of five implementation Work Items. It establishes the client-side architecture in Compose Multiplatform, builds the interactive multi-stage onboarding screens adhering to repository neo-brutalist design tokens, introduces local preference storage for first-run tracking and vibe selection, connects app launch routing in `App.kt`, and verifies the complete delivery with unit and integration tests.

The accompanying implementation design is defined in [design.md](./design.md).

## Authority and decision boundary

- **Governing Feature:** [[FEAT-016-user-onboarding-and-interest-personalization|FEAT-016]].
- **Status:** Plan remains `status: pending` with `approval.status: pending` awaiting Repository Maintainer review.
- **Scope Boundary:**
  - Onboarding is completely client-side and guest-accessible; no backend auth or paywall requirement.
  - Camera capture mechanics remain owned by `FEAT-001` and `FEAT-012`.
  - Pose library browsing remains owned by `FEAT-003`.
  - Replay affordance connects to `FEAT-015` Settings.

## Work Items

- [Work Item 1: Freeze Onboarding Specification and Parity Matrix](./work-item-01-freeze-onboarding-specification-and-parity-matrix.md)
- [Work Item 2: Implement Onboarding Preferences and Local State Persistence](./work-item-02-implement-onboarding-preferences-and-local-state-persistence.md)
- [Work Item 3: Build Compose Multiplatform Onboarding Flow and Screens](./work-item-03-build-compose-multiplatform-onboarding-flow-and-screens.md)
- [Work Item 4: Integrate App Launch Routing and Permission Primer Seams](./work-item-04-integrate-app-launch-routing-and-permission-primer-seams.md)
- [Work Item 5: Verify Onboarding Delivery Across Unit Tests and iOS Baseline](./work-item-05-verify-onboarding-delivery-across-unit-tests-and-ios-baseline.md)

## Coverage

| Requirement | Description | Covered by |
| --- | --- | --- |
| **FR-016-01** | First-Run Routing & Detection | Work Item 2, Work Item 4 |
| **FR-016-02** | Multi-Stage Progress Bar & Back Control | Work Item 3 |
| **FR-016-03** | Interest & Vibe Selection Matrix | Work Item 2, Work Item 3 |
| **FR-016-04** | Interactive Pose Matching Trial & Slider | Work Item 3 |
| **FR-016-05** | Contextual Permission Primer Card | Work Item 3, Work Item 4 |
| **FR-016-06** | Graceful Permission Fallback ("Maybe Later") | Work Item 4 |
| **FR-016-07** | Non-Blocking Skip Affordance | Work Item 3, Work Item 4 |
| **FR-016-08** | Replay Affordance from Settings | Work Item 4 |

## Verification

### Claim Ledger

- **Claim 1 (Architectural seam validated; Compose implementation deferred):** `App.kt` mounts `TabNavigator(tab = PosesTab)` directly at line 59, providing a clean interception seam for `OnboardingScreen`. The production Compose implementation remains deferred to the Cook phase; verification at this stage refers to architectural seam validation in the codebase.
- **Claim 2 (Verified):** The prototype in `docs/prototype/screens/onboarding.html` delivers complete 5-stage interactive behavior with tokens verified against `styles/tokens.css`.
- **Claim 3 (Verified):** Design tokens in `docs/harness/specs/ui-ux-system.md` specify neo-brutalist borders (`2px solid black`), hard offset shadows (`3px 3px 0 #000`), and pastel accents (`#E89CAE` pink, `#7FBBE6` blue, `#FED766` yellow, `#B5E2B9` green).
- **Claim 4 (Architectural seam validated; Compose implementation deferred):** SQLDelight / Settings KV persistence pattern exists in `mobile/shared/src/commonMain/sqldelight/com/aipose/` and can host `has_completed_onboarding` and `user_selected_interests`. The production Compose implementation remains deferred to the Cook phase; verification at this stage refers to architectural seam validation in the codebase.
- **Claim 5 (Architectural seam validated; Compose implementation deferred):** iOS permission check in `CameraContract.ios.kt` provides camera permission seam; Photo Library permission is deferred to contextual in-app capture/import actions in accordance with Apple HIG 5.1.1. The production Compose implementation remains deferred to the Cook phase; verification at this stage refers to architectural seam validation in the codebase.

## Adversarial review findings

1. **Security & Privacy Lens:**
   - *Finding:* Camera and Photo permissions must not be invoked automatically without explicit user intent.
   - *Resolution:* Stage 4 acts as a strict barrier. Only when the user taps "Enable Camera Access" is the system camera prompt invoked. Photo Library access remains deferred to in-app actions. If "Maybe Later" is tapped, no OS prompt is triggered.
2. **Assumption Lens:**
   - *Finding:* Users might not want to select any interests if forced.
   - *Resolution:* Pre-select sensible defaults (`Portrait & Selfie`, `Cafe & Aesthetic`) and allow instant 1-tap "Skip".
3. **Failure Mode Lens:**
   - *Finding:* App backgrounded or force-killed mid-onboarding.
   - *Resolution:* `has_completed_onboarding` is only set to `true` upon reaching Stage 5 completion or explicit Skip. Incomplete sessions restart cleanly at Stage 1.
4. **Scope Complexity Lens:**
   - *Finding:* Risk of adding user registration or cloud sync to onboarding.
   - *Resolution:* Strictly local-first. Onboarding requires zero network calls and zero user account sign-in.

## Consistency sweep

- Plan frontmatter, Feature ID (`FEAT-016`), and all file paths validated.
- All 8 functional requirements mapped to Work Items.
- Design document linked as sibling [design.md](./design.md).
- Zero unresolved contradictions.
