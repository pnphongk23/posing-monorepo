---
work_item: 1
title: Close RevenueCat authority, pricing, and product configuration
status: completed
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
- Confirm paid-access scope: Capture/Camera, Try Pose, and Gallery save/share;
  Home and browsing/detail remain free.
- Confirm product IDs/types, pricing, offering/entitlement names, no-trial policy,
  customer identity policy, legal URLs, and external App Store setup.
- Record Premium header and post-Splash triggers as excluded; verify triggered
  paywall dismissal returns to prior context and preserve the conflict-safe seam.
- Re-run sourcewalk/direct impact checks for the selected app entry symbols;
  preserve the remove-my-poses-tab boundary.

## Scope and affected files

DEC-007/DEC-008, external RevenueCat/App Store configuration runbook, Podfile
configuration inputs, prototype reference when supplied, and no conflict-owned
source files.

## Success criteria

- All commercial and observable behavior choices are recorded as approved PO
  direction; no unselected trial, trigger, route, or capability is assumed.

## Risks

- Product copy and route may change after the future prototype.
- App Store products/offering/legal URLs are external dependencies.

## Required evidence

ckh status/check output, Product Authority provenance, product/offering checklist,
prototype or handoff evidence, impact evidence, and no-credential diff.
