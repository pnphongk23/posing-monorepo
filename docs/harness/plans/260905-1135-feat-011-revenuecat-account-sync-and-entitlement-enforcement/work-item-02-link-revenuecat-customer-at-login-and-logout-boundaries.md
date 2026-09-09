---
work_item: 2
title: Link RevenueCat customer at login and logout boundaries
status: pending
priority: P1
effort: M
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 2: Link RevenueCat customer at login and logout boundaries

## Tasks

- Locate the real successful-login, logout, session-expiry, and account-switch boundaries owned by FEAT-013/014. If those hooks do not exist, stop at the documented integration seam and record the dependency; do not invent a parallel auth flow.
- Require a valid signed-in Account before an Account-bound purchase begins. A signed-out paid trigger must enter the existing sign-in flow; this lane does not initiate an anonymous RevenueCat purchase or rely on anonymous-to-Account transfer/alias behavior.
- At successful login, pass the existing Account ID to the installed RevenueCat SDK via `Purchases.logIn(accountId)`. Verify the exact SDK signature and async result against the locked dependency before coding.
- At logout and account switch, invalidate local in-memory purchase/entitlement state immediately, then call `Purchases.logOut()` at the provider boundary before the old customer context can be reused. Local auth logout must not be blocked by an offline/failed provider call; the next Account must remain fail-closed until an SDK-supported reset or fresh sync prevents cached Account A state from being exposed.
- Make repeated login/re-entry idempotent and make Account A -> Account B transitions explicit. Invalidate or ignore stale CustomerInfo/offering/purchase results after a switch.
- Keep the existing `premium`/`default` purchase vocabulary and UI bridge. Do not pass receipts, provider secrets, or auth tokens through common UI state merely to perform the link.
- Add focused tests for repeated login, logout, switch, provider unavailability, and the rule that a RevenueCat link success alone is not server premium confirmation.

## Scope and affected files

Implementation will be bounded to the existing mobile purchase adapter/bridge and the already-owned auth/session integration seam:

- `mobile/iosApp/iosApp/RevenueCatAdapter.swift`
- `mobile/composeApp/src/iosMain/kotlin/com/aipose/purchases/IosRevenueCatGateway.kt`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/purchases/PurchaseCore.kt` only if a narrow interface change is required
- `mobile/iosApp/iosApp/AppDelegate.swift` only if lifecycle wiring evidence requires it
- The actual FEAT-013/014 auth/session implementation files, once located; current paths are unresolved
- Corresponding mobile/unit/integration tests and dependency metadata only as required for the installed SDK

Do not change server persistence, webhook processing, auth-provider policy, Android, or the companion plan's unrelated UI behavior in this item.

## Success criteria

- Every successful authenticated Account login has one documented call path to `Purchases.logIn(accountId)` using the existing Account ID, with the actual SDK result/error handled.
- Logout and account-switch boundaries invalidate local entitlement state immediately, call `Purchases.logOut()` at the provider boundary, and prevent the old provider context from being reused.
- A signed-out trigger cannot start an Account-bound purchase; sign-in precedes the purchase and no anonymous transfer behavior is required by this lane.
- Local entitlement state is invalidated even when RevenueCat is offline, local logout remains possible, and Account B cannot mount on Account A's cached provider context.
- Account A cannot inherit Account B's RevenueCat customer state during relaunch, re-entry, switch, delayed response, or provider outage.
- Existing purchase/restore/offering states and the single `premium` entitlement remain compatible with the companion UI plan.
- Tests or executable evidence cover the lifecycle matrix; missing auth runtime or native module evidence is reported as a failure/blocker, not assumed to pass.

## Risks

- No mobile login/logout implementation was found during planning, so the correct hook may be owned by a future FEAT-013/014 implementation.
- The repository's RevenueCat module is resolved historically but native compilation may not have the module/configuration available in every environment; SDK API usage must be verified at implementation time.
- Async CustomerInfo or purchase callbacks can race with logout/account switch and cause cross-account leakage if not cancelled or ignored.
- RevenueCat logout/reset semantics may differ by SDK version and connectivity. Use only SDK-supported cache/context controls and keep the app/backend fail-closed if the provider boundary cannot be confirmed.

## Required evidence

- Source diff identifying the actual login/logout boundaries and the exact `Purchases.logIn`/`Purchases.logOut` calls.
- Native compile/typecheck with the locked RevenueCat dependency, or the exact unavailable-module failure.
- Automated tests for A/B identity switching, repeated login/logout, stale callbacks, and failure handling.
- Tests or an explicit state-machine trace for signed-out purchase prevention and offline logout/cache invalidation.
- No receipt/token/secret added to client logs or persisted client state; `git diff --check` passes.
