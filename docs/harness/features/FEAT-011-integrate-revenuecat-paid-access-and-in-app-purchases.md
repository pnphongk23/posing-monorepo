---
schema_version: 1
type: feature
id: FEAT-011
title: Integrate RevenueCat paid access and in-app purchases
status: proposed
created: 2026-08-26
relationships:
  specs:
    - "[[product-feature-inventory]]"
    - "[[ui-ux-system]]"
    - "[[technical-architecture|Technical Architecture]]"
    - "[[model-entity-catalogue|Model Entity Catalogue]]"
    - "[[api-catalogue|API Catalogue]]"
  decisions:
    - "[[DEC-007-ios-sdk-integration-architecture|DEC-007]]"
    - "[[DEC-008-revenuecat-pricing-and-offerings|DEC-008]]"
  plans:
    - "[[260826-0003-integrate-revenuecat-paid-access-and-iap-for-feat-011/plan|260826-0003 UI purchase lane]]"
    - "[[260905-1135-feat-011-revenuecat-account-sync-and-entitlement-enforcement/plan|260905-1135 account sync lane]]"
  reports: []
  rules: []
  features:
    - "[[FEAT-013-saved-poses-albums-account-backed|FEAT-013]]"
    - "[[FEAT-014-manage-account-and-session|FEAT-014]]"
  source_paths:
    - docs/harness/features/FEAT-013-saved-poses-albums-account-backed.md
    - docs/harness/features/FEAT-014-manage-account-and-session.md
    - docs/harness/specs/data-contract.md
    - docs/harness/specs/api-contract.md
    - docs/harness/specs/api/openapi.yaml
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/purchases/PurchaseCore.kt
    - mobile/composeApp/src/iosMain/kotlin/com/aipose/purchases/IosRevenueCatGateway.kt
    - mobile/iosApp/iosApp/AppDelegate.swift
    - mobile/iosApp/iosApp/RevenueCatAdapter.swift
    - mobile/iosApp/Podfile
    - web/services/pose-extract-server/src/app.ts
    - web/services/pose-extract-server/src/config/env.ts
    - web/services/pose-extract-server/src/db/schema.sql
    - web/services/pose-extract-server/src/index.ts
---

# FEAT-011: Integrate RevenueCat paid access and in-app purchases

## Introduction

**Revision note:** The previous approval covered the iOS purchase surface and
client-side confirmed entitlement only. This material revision adds the
account-bound synchronization and server entitlement behavior below, so the
Feature is proposed again until the Product Authority re-approves the expanded
boundary.

**Purpose:** Add a clear RevenueCat purchase surface and account-bound premium
access for Capture/Camera, Try Pose, and PO-selected Gallery save/share actions.
The same signed-in Account must retain its entitlement across devices and
re-entry, while a signed-out or different Account must never inherit it.

**In scope:** One `premium` entitlement, one `default` offering with the two
DEC-008 packages, triggered purchase/restore flow, truthful entitlement states,
account-bound paid-access context at login/logout boundaries, provider status
synchronization into the backend, an authenticated entitlement read, and
server-side enforcement for explicitly paid Account operations.

**Out of scope:** Firebase/Remote Config (FEAT-010), Android, archive/TestFlight,
auth-provider changes, a new credential/token contract, a separate billing
service, event bus, admin dashboard, multiple entitlements, and unrelated edits
to `PosesScreen.kt` or `Navigation.kt`. Home, Community browsing/detail, and
Gallery browsing/detail remain free. Existing public routes are not silently
reclassified as paid by this Feature revision.

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| App user | Customer | Understand and purchase paid capabilities | Trigger access, purchase, restore, or dismiss |
| Signed-in Account | Customer identity | Keep paid access attached to the correct account | Enter/leave an authenticated context and use its entitlement |
| RevenueCat / App Store | External system | Sell, restore, and report products | Return offerings, localized prices, entitlement state, and provider events |
| Pose API | Existing system | Enforce account-bound paid access | Read the requesting Account's current entitlement and fail closed when unavailable |

### User needs

- The user needs clear paid scope, localized price, renewal terms, and restore.
- The user needs access only after confirmed `premium` entitlement.
- The user needs a purchase to follow the same signed-in Account after relaunch,
  another device, or a later login.
- The user needs logout and account switching to remove the previous Account's
  paid context without exposing it to a guest or another Account.
- The user needs backend and client decisions to remain fail-closed while a
  provider update is pending, invalid, or unavailable.

### Preconditions

- RevenueCat products, `default` offering, `premium` entitlement, legal URLs,
  sandbox users, and public SDK key are supplied externally.
- StoreKit localized metadata is available for real purchase verification.
- A valid signed-in Account identity is supplied by the existing auth/session
  boundary owned by FEAT-013/FEAT-014. The current checkout does not yet provide
  runtime evidence for that boundary; it remains unresolved for implementation.
- An Account-bound purchase requires a valid signed-in Account before the
  RevenueCat purchase starts. A signed-out paid trigger first enters the existing
  sign-in flow; this lane does not start anonymous purchases or depend on
  provider-specific anonymous-to-Account transfer behavior.
- Provider webhook authentication and event-to-Account mapping are configured
  server-side before backend synchronization is enabled. No provider header,
  payload, receipt, or token shape is assumed by this Feature.

### Trigger

Paid access appears when an unentitled Home user taps Try Pose or Camera
(Capture), or attempts a gated Gallery save/share action. Account-bound sync also
starts at sign-in, logout/account switch, purchase/restore completion, provider
status change, or an authenticated request for entitlement. A signed-out paid
trigger requests sign-in before any purchase begins. It never appears after
Splash and has no Premium header affordance trigger.

### Main flow

1. **Actor:** An Account signs in or re-enters the app. **System:** the paid-access
   context is associated with that Account, without changing the auth provider or
   creating a second identity.
2. **Actor:** The Account purchases or restores. **System:** RevenueCat confirms
   the transaction and `premium` entitlement; the account-bound state is updated
   for subsequent client and server reads.
3. **Actor:** The Account requests a paid operation or entitlement status.
   **System:** the system uses the Account's current confirmed entitlement and
   allows the operation only when `premium` is active.
4. **Actor:** The Account logs out or changes account. **System:** the previous
   paid-access context is cleared before the next context can be used.

### Alternative flows

- **A0 — Signed-out trigger.** Source step: trigger. Condition: no valid Account
  session exists. Behavior: require the existing sign-in flow before presenting
  or starting the Account-bound purchase; do not create an anonymous purchase.
  Resume at step: 1 after a valid Account is established.
- **A1 — Capture/Try Pose gate.** Source step: 2–3. Condition: user is not
  entitled. Behavior: show the common paid-access surface and do not complete the
  action. Resume at step: 2.
- **A2 — Gallery save/share gate.** Source step: 2–3. Condition: user is not
  entitled. Behavior: show the common paid-access surface and do not complete
  save/share. Resume at step: 2.
- **A3 — No offering.** Source step: 2. Condition: offering is unavailable.
  Behavior: show a retryable unavailable state; never fabricate access. Resume at
  step: 2 after retry.
- **A4 — Restore succeeds.** Source step: 2. Condition: restore confirms
  entitlement. Behavior: apply confirmed entitlement without a duplicate
  purchase. Ends with: paid access restored for the signed-in Account.
- **A5 — Returning Account.** Source step: 1. Condition: the Account has a
  previously confirmed purchase. Behavior: resolve the same Account context and
  show its current entitlement; do not create a second Account.
- **A6 — Dismissal.** Source step: 2. Condition: user dismisses the triggered
  paywall. Behavior: return to prior context; grant no access and complete no
  gated action. Ends with: no paid action completed.

### Exception flows

- **E1 — Purchase cancelled or failed.** Source step: 2, purchase attempt.
  Handling: keep entitlement unchanged and show a truthful retryable result.
  Prohibited: reporting success or granting access.
- **E2 — Expired, revoked, billing retry, or grace.** Source step: 2–3,
  entitlement update. Handling: reflect the confirmed provider state and keep
  backend enforcement fail-closed when active access is not confirmed.
  Prohibited: granting optimistically.
- **E3 — Duplicate or invalid provider notification.** Source step: 2–3.
  Handling: repeated delivery has the same outcome and invalid/unmappable input
  changes no Account state. Prohibited: duplicate entitlement state or accepting
  an event for another Account.
- **E4 — Logout or account switch during sync.** Source step: 1–4. Handling:
  immediately invalidate local in-memory purchase/entitlement state, do not block
  local auth logout on a provider network result, call the RevenueCat logout
  boundary, and prevent the next Account from reusing the old provider context
  until it is safely reset or freshly re-synced. Reject stale results for the next
  Account. Prohibited: showing Account A's entitlement in Account B or guest
  context.
- **E5 — RevenueCat/backend/auth unavailable.** Source step: 1–3. Handling:
  show a truthful unavailable/retry state and do not grant a server-protected
  paid operation. Prohibited: treating a client boolean or unauthenticated
  request as authority.

### Postconditions

- **Success:** Confirmed `premium` unlocks only Capture/Camera, Try Pose, and
  Gallery save/share for the correct Account; the authenticated entitlement read
  exposes only that Account's state.
- **Logout/account change:** No previous Account's paid context is usable in a
  guest or different Account context.
- **Failure:** No entitlement or gated action is granted/completed; duplicate,
  invalid, or stale provider input does not corrupt another Account's state.

## Requirements

- **FR-001:** Show paid access only for an unentitled Home user tapping Try Pose
  or Camera (Capture), or attempting gated Gallery save/share; never after Splash
  and never from a Premium header. If no valid Account exists, require sign-in
  before the Account-bound purchase starts.
- **FR-002:** Explain the paid scope and two DEC-008 packages: annual $39.99 /
  ₫999k highlighted and monthly $5.99 / ₫149k as the comparison anchor; no
  trial/introductory offer.
- **FR-003:** Expose one `premium` entitlement and one `default` offering.
- **FR-004:** Purchase/restore grants access only after confirmed entitlement;
  cancellation, pending, failure, expiry, revocation, and no-offering states are truthful.
- **FR-005:** Include purchase, restore, legal links, loading, success, retryable
  failure, dismissal, and entitlement-state feedback.
- **FR-006:** A confirmed RevenueCat purchase shall be associated with the
  existing signed-in Account identity and shall resolve to that same Account on
  later login/re-entry; it shall not create a second Account or silently attach
  to a guest/different Account. The purchase cannot start until that Account
  context is valid; anonymous purchase transfer is not part of this lane.
- **FR-007:** The paid-access context shall follow the existing login boundary and
  be invalidated locally at logout/account switch before a different context is
  used; local logout must not depend on provider network success. Auth provider,
  session, and Account ownership remain governed by FEAT-013/FEAT-014.
- **FR-008:** Provider status updates shall update the matching Account's single
  `premium` state idempotently; repeated delivery shall not duplicate or corrupt
  entitlement state.
- **FR-009:** An authenticated `GET /api/me/entitlement` shall return only the
  requesting Account's current `premium` status; unauthenticated or invalid
  sessions shall receive the existing unauthorized behavior and no Account data.
- **FR-010:** Any explicitly paid Account operation shall be authorized from the
  server-side Account entitlement, not from a client-supplied Account ID or local
  premium boolean; unavailable/unconfirmed state shall fail closed. Existing
  public routes remain unchanged until a separate scope decision names them.
- **BR-001:** No RevenueCat secret, receipt, token, or production credential is
  embedded in source or documentation.
- **BR-002:** No paid capability or gated save/share action is granted/completed
  without confirmed `premium`; dismissal returns to prior context without access.
- **BR-003:** `PosesScreen.kt` remains outside this lane. The previous
  Navigation boundary is open only for the approved App-root/presentation seam
  required by this feature; unrelated navigation rewrites remain forbidden.
- **BR-004:** The implementation shall reuse the existing Account/auth boundary
  and shall not add a billing service, event bus, admin dashboard, auth provider,
  or second entitlement.
- **NFR-001:** Account isolation is maintained across login, logout, account
  switch, duplicate webhook delivery, and authenticated entitlement reads.
- **NFR-002 (fail-open on capture):** The client capture gate is fail-open by
  design when it cannot *know* the entitlement: an unconfigured build (missing or
  placeholder RevenueCat key / entitlement id), an unfinished or failed Account
  link, an offline or unresolved refresh, and a missing offering all let the
  shutter capture exactly as before this feature. Only a **confirmed** "no access"
  answer for the linked Account, or a signed-out user (sign-in prompt, no guest
  purchase), opens the paywall. Losing a photo outranks losing a sale; purchase
  and server-side enforcement stay fail-closed under FR-004/FR-010.

## Acceptance

- [ ] Try Pose, Camera (Capture), and gated Gallery save/share without entitlement
  open one paid-access flow; Splash and Premium header do not.
- [ ] The flow shows annual and monthly localized packages, annual highlighted,
  with no trial.
- [ ] Confirmed `premium` enables only Capture/Camera, Try Pose, and Gallery
  save/share; Home and browsing/detail remain free.
- [ ] Purchase, restore, cancel, pending/failure, expiry/revocation, and
  no-offering outcomes are truthful.
- [ ] Dismissal returns to prior context and grants no access.
- [ ] After Account A signs in, a confirmed purchase is linked to A; after logout
  and Account B sign-in, B cannot use A's entitlement; signing back into A
  resolves only A's state.
- [ ] A signed-out paid trigger requires sign-in before purchase; this lane does
  not start an anonymous RevenueCat purchase or rely on anonymous transfer.
- [ ] Logout invalidates local entitlement state immediately and does not strand
  local sign-out when RevenueCat is offline; Account B cannot mount until the old
  provider context is reset or freshly synchronized.
- [ ] Replaying the same provider notification leaves one unchanged entitlement
  outcome and does not affect another Account; invalid/unmappable notification
  changes no Account state.
- [ ] Authenticated `GET /api/me/entitlement` returns the caller's `premium`
  state, rejects unauthenticated/invalid sessions, and cannot be used to query
  another Account by parameter or header.
- [ ] Server-side paid enforcement fails closed without a valid Account and
  active `premium`; it does not trust a client boolean. Existing public and admin
  routes are not reclassified without explicit scope evidence.
- [ ] No secret/receipt/token is committed; no billing service, event bus, admin
  dashboard, auth-provider change, second entitlement, Android lane, or unrelated
  `PosesScreen.kt`/`Navigation.kt` rewrite is introduced.

**Scenario: gated trigger**

Given the user has no confirmed `premium` entitlement  
When the user taps Try Pose, Camera (Capture), or Gallery save/share from Home
Then the paid-access surface is shown and the gated action does not complete.

**Scenario: confirmed purchase**  

Given RevenueCat returns the configured `default` offering
When the user purchases and RevenueCat confirms `premium`  
Then Capture/Camera, Try Pose, and Gallery save/share become available for the
signed-in Account.

**Scenario: account-bound purchase**

Given Account A has a valid session and RevenueCat confirms `premium`
When A returns after logout/relaunch or signs in on another device
Then the same Account context resolves the confirmed entitlement and Account B or
Guest cannot use it.

**Scenario: entitlement read and isolation**

Given Account A and Account B have separate sessions
When each calls authenticated `GET /api/me/entitlement`
Then each response contains only its own `premium` state and an unauthenticated
request receives unauthorized behavior.

**Scenario: duplicate provider notification**

Given a provider notification has already been accepted for Account A
When the same notification is delivered again
Then the result is idempotent, no duplicate state is created, and Account B is
unchanged.

## Relationships

- Decisions: [DEC-007](../decisions/DEC-007-ios-sdk-integration-architecture.md)
  and [DEC-008](../decisions/DEC-008-revenuecat-pricing-and-offerings.md).
- Companion UI/purchase plan: [260826-0003 RevenueCat](../plans/260826-0003-integrate-revenuecat-paid-access-and-iap-for-feat-011/plan.md).
- Account sync/backend plan: [260905-1135 RevenueCat account sync](../plans/260905-1135-feat-011-revenuecat-account-sync-and-entitlement-enforcement/plan.md).
- [FEAT-013](FEAT-013-saved-poses-albums-account-backed.md) defines the proposed
  Google/Supabase Account identity boundary; [FEAT-014](FEAT-014-manage-account-and-session.md)
  owns session lifecycle, sign-out, expiry recovery, and isolation.
- Shared model: [`Account`](../../spec/data/entities/account.md) remains
  canonical; this Feature does not duplicate identity fields.
- Shared API conventions: [API Conventions](../../spec/api/conventions.md) and
  OpenAPI define existing auth/status conventions; the new entitlement endpoint
  is planned but not yet implemented.

### Current evidence and traceability

- **Observed:** `RevenueCatAdapter` owns native RevenueCat configuration,
  offering/purchase/restore requests, and `premium` CustomerInfo mapping;
  `IosRevenueCatGateway` exposes the existing notification bridge.
- **Observed:** `PurchaseCore` defines one `premium` entitlement and the approved
  `default` offering/product IDs; `AppDelegate` configures RevenueCat at launch.
- **Failed:** No `Purchases.logIn`/`Purchases.logOut` call or mobile login/logout
  hook was found in the current checkout; the adapter and gateway contain no
  Account identity input.
- **Failed:** `pose-extract-server` currently has no entitlement route, webhook
  route, Account-auth middleware, entitlement table, or entitlement environment
  contract. Its existing Bearer middleware is admin-secret-only.
- **Unresolved:** FEAT-013/FEAT-014 explicitly leave runtime Google/Supabase
  login, session, and sign-out evidence unresolved; provider webhook payload and
  authentication details and real Sandbox configuration are external
  dependencies.
- **Lifecycle:** `harness feature request-changes FEAT-011` cleared the prior
  approval metadata before this material revision. No new Product Authority
  approval is inferred here.
