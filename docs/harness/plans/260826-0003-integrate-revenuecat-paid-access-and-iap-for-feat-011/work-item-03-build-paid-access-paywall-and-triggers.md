---
work_item: 3
title: Build paid-access paywall and triggers
status: completed
priority: P2
effort: TBD
dependencies:
  - 2
decision_dependencies:
  - "[[DEC-007-ios-sdk-integration-architecture|DEC-007]]"
  - "[[DEC-008-revenuecat-pricing-and-offerings|DEC-008]]"
---

# Work Item 3: Build paid-access paywall and triggers

## Tasks

- Create a self-contained Compose paywall/state surface with localized offering
  prices, package periods, purchase, restore, legal links, loading, success,
  cancellation, retryable failure, and entitlement state.
- Show the same paid-access flow from Home Try Pose, Home Capture/Camera without
  entitlement, and gated Gallery save/share. Do not trigger after Splash or from
  a Premium header affordance.
- Explain only Capture/Camera, Try Pose, and Gallery save/share; do not advertise
  unapproved capabilities.
- Dismissal returns to prior context and grants no access; do not infer a
  free-core promise for gated actions.
- Use the approved minimal App-root/Navigation seam for true Camera
  prior-context dismissal and distinct Gallery share; do not rewrite navigation.

## Scope and affected files

New composeApp IAP screen/state package, App.kt, Navigation.kt only at the
approved seam, approved presentation host, common UI/state tests, legal URL
placeholder configuration, and no PosesScreen.kt edits.

## Success criteria

- All three approved triggers converge on one truthful paywall state.
- Confirmed premium exposes only Capture/Camera, Try Pose, and Gallery save/share.
- No purchase, cancellation, failure, or unavailable offering grants access.
- Store-localized prices and legal links are shown without hardcoded currency
  values or raw SDK errors; legal links remain inert when unset or PLACEHOLDER.
- Camera dismissal returns through the true prior-context callback and Gallery
  share invokes a distinct share action through the approved seam.

## Risks

- The future prototype may change the header entry point.
- The conflict-safe route seam may require coordination with another lane.

## Required evidence

Compose/state tests, deterministic selectors, trigger matrix, paywall copy,
route/handoff evidence, and no visual proof claimed before Cook.

## Remediation evidence

- `PaywallScreen` observes `PurchaseGateway.snapshot`, loads the default
  offering on entry, and exposes a retry action for unconfigured/no-offering.
- One primary CTA uses StoreKit-localized price/period metadata; annual is
  highlighted, monthly is the comparison anchor, and no currency values are
  hardcoded. The launch offering has exactly `premium_annual` and
  `premium_monthly`, with no weekly or lifetime product.
- Visible Terms/Privacy labels now invoke a platform legal action using
  externally injected Info.plist URL keys; this workspace does not contain the
  external legal URL values, so runtime legal navigation is not claimed.
- Try Pose, Camera/Capture, and Gallery save/share use the same
  confirmed-entitlement gate through allowed seams. `PosesScreen.kt` and
  unrelated navigation remain untouched.
- Gallery share uses a distinct iOS platform share-sheet seam and never aliases
  it to saving. Camera dismissal uses the true prior-context callback through
  the approved seam.
- WI3 completed its approved scope: the App-root/Navigation seam is wired for
  true Camera prior-context dismissal and distinct Gallery share; legal
  placeholder handling is inert; and common/KMP evidence is recorded below.
- Xcode and RevenueCat Sandbox availability disclosures are owned by WI4 and
  are not used as WI3 acceptance claims.
- Bounded `./gradlew :composeApp:iosSimulatorArm64Test` passed with
  `BUILD SUCCESSFUL in 54s`; `PaywallTest` covers each trigger and all
  non-entitled terminal/unavailable states. This is common/KMP evidence only,
  not native UI, StoreKit, or Sandbox evidence.
- WI4 retains the required Xcode/Sandbox disclosures and does not convert those
  unavailable checks into passes.
