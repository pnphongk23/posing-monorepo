---
schema_version: 1
type: decision
id: DEC-008
title: RevenueCat launch pricing and offerings
status: proposed
created: 2026-08-25
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

AI Pose is an iPhone pose-camera product with existing discovery/capture
surfaces and a proposed paid-access boundary. The user authorized pricing
brainstorming, but the
commercial promise, introductory offer, and exact App Store Connect price tiers
still require Product Authority confirmation. The roadmap currently places
monetization outside Phase 6, so this is also a proposed cross-cutting exception
that Product Authority must explicitly confirm. Apple supports many localized
subscription price points and territory-specific pricing; the numbers below are
planning anchors, not a claim that a particular Apple tier has been selected.

## Decision

**Proposed launch model:** one `premium` entitlement with one current RevenueCat
offering and duration packages, rather than multiple launch entitlements:

**PO direction (2026-08-26):** AI Pose is a paid-access app, not a free-tier
product. A confirmed `premium` entitlement grants access to the Community pose
library, pose detail and Try Pose, Gallery and gallery detail, and the
PO-selected Gallery save/share actions. The paid-access surface is entered after Splash,
from the Capture gate, and from a Premium header/entry affordance defined by the
future prototype. The pre-purchase preview contents and whether the paywall can
be dismissed remain Unresolved (TBD); this Decision remains `proposed` until
Product Authority approves the full commercial boundary.

| Package / product ID | United States anchor | Vietnam anchor | Role |
| --- | ---: | ---: | --- |
| `premium_weekly` | **$1.99 / week** | **₫49,000 / week** | Short commitment; secondary option, never the default highlight |
| `premium_monthly` | **$5.99 / month** | **₫149,000 / month** | Flexible reference price |
| `premium_annual` | **$39.99 / year** | **₫999,000 / year** | Recommended default/highlight; best value for repeat users |
| `premium_lifetime` | **$59.99 one-time** | **₫1,499,000 one-time** | Non-renewing alternative for users avoiding subscriptions |

The paywall should highlight annual, show monthly as the comparison anchor, keep
weekly available but visually secondary, and show lifetime as a clear one-time
alternative. The single `premium` entitlement keeps access checks and future
package changes simple. A `default` offering contains the four packages; future
experiments can use a separate offering without changing entitlement semantics.

**Recommended default:** annual at $39.99 / ₫999,000, with no automatic weekly
trial. If Product Authority wants an introductory offer, the smallest safe
launch experiment is a 3-day annual introductory period configured in App Store
Connect/RevenueCat, shown with explicit renewal terms; do not silently add it in
code.

## Alternatives

- **A — Moderate annual-led bundle (recommended):** $5.99 monthly, $39.99 annual,
  $1.99 weekly, $59.99 lifetime. It is below premium fitness outliers while
  preserving a meaningful annual discount and a lifetime escape hatch.
- **B — Aggressive low-price acquisition:** $2.99 monthly, $19.99 annual, and
  $29.99 lifetime. Easier first conversion, but risks underpricing cloud/API
  costs and makes a later price increase harder.
- **C — Premium coaching positioning:** $9.99 monthly, $69.99 annual, and
  $99.99 lifetime. Better margin if AI coaching is materially differentiated, but
  not justified by the current feature evidence and likely too high for the MVP.

## Consequences

- The launch can measure package preference without multiplying entitlement
  logic. RevenueCat product identifiers must remain stable after release.
- Weekly pricing has a high annualized equivalent; the paywall must make period
  and renewal terms prominent and must not use dark-pattern urgency.
- VND values are localized anchors. App Store Connect's territory price tier,
  taxes, and Apple's currency rules are authoritative and can shift the final
  displayed amount.
- The paid capability scope is now proposed as the Community and Gallery access
  listed above; it does not authorize unlimited AI usage or any additional
  capability not named in the Feature.

## Evidence

- **Observed market reference:** PoseSnap lists Pro at $4.99/month and
  $49.99/year and positions a pose-camera/AI pose product with premium templates
  and analysis ([App Store listing](https://apps.apple.com/us/app/posesnap-ai-pose-camera/id6768783594)).
- **Observed market reference:** Superpose lists one-time $2.99 starter and
  $9.99 value packs rather than subscriptions ([App Store listing](https://apps.apple.com/us/app/superpose-ai-pose-camera/id6759357866)).
- **Observed market range:** JEFIT lists $12.99/month and $69.99/year for a
  broader fitness-tracking product ([App Store listing](https://apps.apple.com/us/app/jefit-workout-plan-gym-tracker/id449810000)).
- **Observed platform constraint:** Apple documents territory-specific
  subscription pricing and many price points ([Apple subscriptions](https://developer.apple.com/app-store/subscriptions/)); Apple also documents a
  Vietnam threshold reference of ₫130,000 / ₫1,300,000 for one price-increase
  rule, which is not a direct recommendation for these products ([Apple price-increase thresholds](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/auto-renewable-subscription-price-increase-thresholds)).
- **Observed RevenueCat model:** RevenueCat's handbook describes a current
  offering and entitlements as the app-facing abstraction ([RevenueCat Handbook](https://www.revenuecat.com/documents/revenuecat-handbook)).
- **Inferred:** AI Pose should launch between the low-price pose-camera examples
  and the higher-priced broad fitness/coaching products until its premium value
  and API cost are measured.
- **Unresolved:** Product Authority must confirm the pre-purchase preview and
  paywall-dismissal behavior, trial policy, exact Apple price tiers,
  tax/commission assumptions, and whether lifetime is launch scope or a later
  experiment.

## Supersession

This decision supersedes no earlier decision.
