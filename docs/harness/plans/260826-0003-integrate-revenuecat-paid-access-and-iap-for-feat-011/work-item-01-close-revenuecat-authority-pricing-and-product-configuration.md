---
work_item: 1
title: Close RevenueCat authority, pricing, and product configuration
status: pending
priority: P2
effort: TBD
dependencies: []
decision_dependencies:
  - "[[DEC-007-ios-sdk-integration-architecture|DEC-007]]"
  - "[[DEC-008-revenuecat-pricing-and-offerings|DEC-008]]"
---

# Work Item 1: Close RevenueCat authority, pricing, and product configuration

## Tasks

- Confirm FEAT-011, DEC-007, DEC-008, and this Plan approvals before Cook.
- Confirm paid-access scope: Community library/detail/Try Pose and
  Gallery/detail/save/share.
- Confirm product IDs/types, pricing, offering/entitlement names, trial/lifetime
  policy, customer identity policy, legal URLs, and external App Store setup.
- Resolve the prototype Premium header location, the pre-purchase preview, the
  paywall dismissal policy, and the conflict-safe presentation seam.
- Re-run sourcewalk/direct impact checks for the selected app entry symbols;
  preserve the remove-my-poses-tab boundary.

## Scope and affected files

DEC-007/DEC-008, external RevenueCat/App Store configuration runbook, Podfile
configuration inputs, prototype reference when supplied, and no conflict-owned
source files.

## Success criteria

- All commercial and observable behavior choices are recorded as PO direction
  or approved authority; no plan assumes an unselected free tier, preview, or
  route.

## Risks

- Product copy and route may change after the future prototype.
- App Store products/offering/legal URLs are external dependencies.

## Required evidence

ckh status/check output, Product Authority provenance, product/offering checklist,
prototype or handoff evidence, impact evidence, and no-credential diff.
