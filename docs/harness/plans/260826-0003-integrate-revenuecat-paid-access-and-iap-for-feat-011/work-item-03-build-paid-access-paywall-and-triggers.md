---
work_item: 3
title: Build paid-access paywall and triggers
status: pending
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
- Show the same paid-access flow after Splash, from Capture without entitlement,
  and from the prototype-defined Premium header/entry affordance.
- Explain the PO-selected paid scope: Community library/detail/Try Pose and
  Gallery/detail/save/share; do not advertise unapproved capabilities.
- Keep the exact non-purchaser preview and dismissal behavior as an explicit
  authority input; do not infer a free core tier.
- Preserve the conflict boundary: route through an approved App-root seam or
  record a handoff to the remove-my-poses-tab owner.

## Scope and affected files

New composeApp IAP screen/state package, App.kt or approved presentation host,
common UI/state tests, legal URL configuration, and no PosesScreen.kt or
Navigation.kt edits.

## Success criteria

- All three triggers converge on one truthful paywall state.
- Confirmed premium exposes only the PO-selected Community/Gallery scope.
- No purchase, cancellation, failure, or unavailable offering grants access.
- Store-localized prices and approved legal links are shown without hardcoded
  currency values or raw SDK errors.

## Risks

- The future prototype may change the header entry point.
- The conflict-safe route seam may require coordination with another lane.

## Required evidence

Compose/state tests, deterministic selectors, trigger matrix, paywall copy,
route/handoff evidence, and no visual proof claimed before Cook.
