# FEAT-011 Paywall + Purchase sandbox plan

Date: 2026-08-26  
Lane: `feat/paywall-purchase`  
Baseline: `main` / `3d343d1`  
Scope: iOS-only design and implementation sandbox; no production RevenueCat key, archive, TestFlight, or device purchase validation.

## Current phase: prototype presentation (2026-08-29)

This worktree contains the static HTML/CSS/JS paywall prototype and harness
docs (FEAT-011, DEC-008, this plan). Binding UI spec: `design.md`.

**Not in this worktree:** Compose `PaywallScreen`, `PurchaseViewModel`, or a
RevenueCat CocoaPod. A prior plan revision claimed those sandbox pieces were
done; `srcwalk discover` on `mobile/` finds zero matches. Do not treat that
claim as landed work.

Native production RevenueCat still requires a real public SDK key, Product
Authority confirmation, and a later implementation lane.

## Context and constraints

- Follow FEAT-011 and DEC-008: one `premium` entitlement; annual `$39.99 / ₫999k` is the highlighted default, monthly `$5.99 / ₫149k` is the anchor, weekly `$1.99 / ₫49k` is secondary, and lifetime `$59.99 / ₫1,499k` is the one-time alternative.
- Paywall entry points are after Splash, from Capture gate, and from a Premium affordance. Gated surfaces are Community pose library/detail/Try Pose and Gallery/detail/save/share.
- Preserve the current flow while RevenueCat is unconfigured: the prototype must label simulated purchases clearly, never grant entitlement from the unconfigured path, and keep preview surfaces available.
- Do not edit `PosesScreen.kt` or `Navigation.kt` unless unavoidable; if either is touched, record the reason and `srcwalk assess` evidence.
- Use a placeholder RevenueCat key only. Do not commit/stage/push/tag or mutate the main worktree.

## Work items

### 1. Design the paywall surface

Create the static HTML/CSS/JS paywall prototype per `design.md`: stacked annual-led chooser (no 3-column price grid), paid-access copy (not freemium), one locale on cards, 44pt Close, restore + Terms + Privacy, sticky CTA with price and period. Keep a future Compose implementation aligned with `AiPoseColors`, `AiPoseTypography`, spacing, hard borders, and offset shadows.

### 2. Implement purchase core (sandbox)

**Status: not in this worktree.** Deferred until a later native lane. Prototype
simulates purchase/restore only (`sessionStorage` flag). Production integration
requires a real public SDK key and should use `purchases-kmp`.

### 3. Wire prototype entry points and verify (native wiring deferred)

Connect the least invasive prototype Capture/Try Pose/Gallery actions and Premium affordances to the paywall with a safe return context. Preserve existing navigation and screens where possible; do not claim production purchase capability before RevenueCat is configured. Verify the static prototype in representative mobile/desktop viewports, exercise simulated purchase/restore/error/unconfigured states, and run `git diff --check`; native Gradle gates remain deferred in this prototype-only phase.

## Evidence to capture

- Before editing each changed symbol, run `srcwalk assess <symbol> --scope mobile/composeApp` (and the narrowest relevant scope for iOS/Podfile symbols).
- Final report must name changed files/symbols, assess results, actual test counts and failures, the RevenueCat placeholder boundary, and whether `Navigation.kt`/`PosesScreen.kt` remained untouched.
