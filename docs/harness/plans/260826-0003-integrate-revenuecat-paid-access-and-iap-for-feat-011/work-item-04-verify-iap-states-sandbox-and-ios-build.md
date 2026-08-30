---
work_item: 4
title: Verify IAP states, Sandbox, and iOS build
status: pending
priority: P2
effort: TBD
dependencies:
  - 3
decision_dependencies:
  - "[[DEC-007-ios-sdk-integration-architecture|DEC-007]]"
  - "[[DEC-008-revenuecat-pricing-and-offerings|DEC-008]]"
---

# Work Item 4: Verify IAP states, Sandbox, and iOS build

## Tasks

- Run KMP tests and the existing unsigned iosApp.xcworkspace build only after
  approval; preserve the known keychain-login limitation and do not archive or
  upload.
- Exercise offering/no-offering, purchase success/cancel/pending/failure,
  restore/no-match/success, expiry, billing retry/grace, revocation, and
  localized package display.
- Verify all three paid-access triggers and confirmed access to Community/detail/
  Try Pose and Gallery/detail/save/share.
- Confirm the local product/type fixture is not treated as the authoritative
  RevenueCat flow; Sandbox is authoritative.
- Audit secrets, receipts/tokens, unexpected dependency upgrades, Android
  target changes, and PosesScreen.kt/Navigation.kt edits.

## Scope and affected files

Approved RevenueCat implementation files, tests, runbook/evidence, and existing
workspace only. No new workspace, archive, upload, signing/keychain repair,
commit, push, or tag.

## Success criteria

- Required checks pass with exact output recorded, or the concrete blocker is
  recorded as: Tôi không thể xác minh điều này hoạt động vì...
- No unconfirmed entitlement or free-core implication is shown.
- Conflict boundary and whole-plan consistency remain intact.

## Risks

- Real billing verification requires configured App Store Sandbox products and
  tester accounts; simulator/local fixture alone is insufficient.
- Existing dirty worktree can make attribution difficult.

## Required evidence

Exact commands/status, trigger/access matrix, purchase/restore state matrix,
Sandbox evidence, dependency/secret/conflict audit, and final consistency sweep.
