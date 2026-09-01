---
schema_version: 1
type: decision
id: DEC-008
title: RevenueCat launch pricing and offerings
status: approved
created: 2026-08-25
approved: 2026-08-31
approved_by: Pham Nhu Phong
relationships:
  specs:
    - "[[product-feature-inventory]]"
  decisions: []
  plans:
    - "[[260826-0003-integrate-revenuecat-paid-access-and-iap-for-feat-011/plan|260826-0003]]"
  reports: []
  rules: []
  features:
    - "[[FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases|FEAT-011]]"
  source_paths:
    - docs/harness/features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md
---

# DEC-008: RevenueCat launch pricing and offerings

## Context

AI Pose needs one explicit launch commercial contract for RevenueCat and App
Store Connect. This decision closes the paid-access trigger, capability scope,
trial policy, entitlement, offering, package IDs, and planning prices without
placing secrets or external configuration in the repository.

## Decision

**Approved launch model (Product Authority, 2026-08-31):** one `premium`
entitlement and one `default` RevenueCat offering with two packages.

**D-TRIGGER:** Show paid access only when an unentitled user taps **Try Pose** or
**Camera (Capture)** from Home, plus gated Gallery save/share actions in scope.
There is no post-Splash auto-paywall and no Premium header affordance trigger.

**D-SCOPE:** Premium applies only to Capture/Camera, Try Pose, and the
PO-selected Gallery save/share actions. Home, Community browsing/detail, and
Gallery browsing/detail remain free.

**D-TRIAL:** No trial or introductory offer at launch. There is one premium
entitlement and one default offering.

| Package / product ID | United States anchor | Vietnam anchor | Role |
| --- | ---: | ---: | --- |
| `premium_monthly` | **$5.99 / month** | **₫149,000 / month** | Comparison anchor |
| `premium_annual` | **$39.99 / year** | **₫999,000 / year** | Default highlight; recommended |

The `default` offering contains only the annual and monthly packages. Annual is
highlighted and monthly is the comparison anchor. StoreKit localized metadata is
authoritative for the displayed price.

## Alternatives

- A — Two-package annual-led offering (selected): preserves the frozen launch
  package set and one entitlement.
- B — Multiple entitlements: rejected because it adds entitlement semantics
  without Product Authority direction.
- C — Trial/introductory offer: rejected at launch by D-TRIAL.

## Consequences

- RevenueCat product identifiers and the `premium` entitlement remain stable.
- App Store Connect products/prices, the real public SDK key, sandbox users, and
  legal URLs remain external dependencies.
- No unlimited AI usage or additional paid capability is authorized.
- A triggered paywall may return the user to the prior context; this does not
  create a free-core promise and does not add an auto-paywall.

## Evidence

- **Observed market reference:** PoseSnap lists Pro at $4.99/month and
  $49.99/year ([App Store listing](https://apps.apple.com/us/app/posesnap-ai-pose-camera/id6768783594)).
- **Observed market reference:** Superpose lists one-time packs
  ([App Store listing](https://apps.apple.com/us/app/superpose-ai-pose-camera/id6759357866)).
- **Observed market range:** JEFIT lists subscription pricing
  ([App Store listing](https://apps.apple.com/us/app/jefit-workout-plan-gym-tracker/id449810000)).
- **Observed platform constraint:** Apple documents territory-specific pricing
  ([Apple subscriptions](https://developer.apple.com/app-store/subscriptions/)).
- **Observed RevenueCat model:** RevenueCat documents offerings and entitlements
  ([RevenueCat Handbook](https://www.revenuecat.com/documents/revenuecat-handbook)).
- **Observed binding presentation policy:** the sandbox design returns a dismissed
  paywall to the prior screen; this is for triggered gates only.
- **Verified PO freeze (2026-08-31, authority: Pham Nhu Phong):** D-TRIGGER,
  D-SCOPE, D-TRIAL, one entitlement, one default offering, and exactly the two
  IDs and prices above.
- **Unresolved external dependencies:** exact Apple price tiers, taxes/commission,
  configured products, legal URLs, sandbox users, and real public SDK key.

## Supersession

This decision supersedes no earlier decision.
