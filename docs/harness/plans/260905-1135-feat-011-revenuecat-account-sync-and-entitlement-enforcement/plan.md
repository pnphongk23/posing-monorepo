---
title: FEAT-011 RevenueCat account sync and entitlement enforcement
description: Implementation plan for binding RevenueCat purchases to the existing Account context and enforcing one premium entitlement through pose-extract-server.
status: pending
approval:
  status: approved
  required_by: Repository Maintainer
  decided: 2026-09-05
priority: P1
effort: L
branch: backlog
tags:
  - revenuecat
  - account-sync
  - entitlement
  - webhook
  - iap
blockedBy: []
blocks: []
relationships:
  specs:
    - "[[product-feature-inventory]]"
    - "[[technical-architecture|Technical Architecture]]"
    - "[[model-entity-catalogue|Model Entity Catalogue]]"
    - "[[api-catalogue|API Catalogue]]"
  decisions:
    - "[[DEC-007-ios-sdk-integration-architecture|DEC-007]]"
    - "[[DEC-008-revenuecat-pricing-and-offerings|DEC-008]]"
  plans:
    - "[[260826-0003-integrate-revenuecat-paid-access-and-iap-for-feat-011/plan|260826-0003 UI purchase lane]]"
    - "[[260905-1135-feat-011-revenuecat-account-sync-and-entitlement-enforcement/plan|This account sync lane]]"
  reports: []
  rules: []
  features:
    - "[[FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases|FEAT-011]]"
    - "[[FEAT-013-saved-poses-albums-account-backed|FEAT-013]]"
    - "[[FEAT-014-manage-account-and-session|FEAT-014]]"
  source_paths:
    - docs/harness/features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md
    - docs/harness/features/FEAT-013-saved-poses-albums-account-backed.md
    - docs/harness/features/FEAT-014-manage-account-and-session.md
    - docs/spec/data/entities/account.md
    - docs/spec/api/conventions.md
    - docs/spec/api/openapi.yaml
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/purchases/PurchaseCore.kt
    - mobile/composeApp/src/iosMain/kotlin/com/aipose/purchases/IosRevenueCatGateway.kt
    - mobile/iosApp/iosApp/AppDelegate.swift
    - mobile/iosApp/iosApp/RevenueCatAdapter.swift
    - mobile/iosApp/Podfile
    - web/services/pose-extract-server/package.json
    - web/services/pose-extract-server/src/app.ts
    - web/services/pose-extract-server/src/config/env.ts
    - web/services/pose-extract-server/src/db/schema.sql
    - web/services/pose-extract-server/src/index.ts
    - web/services/pose-extract-server/src/middleware/adminAuth.ts
created: 2026-09-05T11:35:00+07:00
createdBy: Paseo Lead - Quach Gia
---

# FEAT-011 RevenueCat account sync and entitlement enforcement

## Overview

This is the account-sync and backend-entitlement lane for FEAT-011. The earlier plan, [260826-0003 UI purchase lane](../260826-0003-integrate-revenuecat-paid-access-and-iap-for-feat-011/plan.md), remains the companion plan for the existing iOS purchase UI and native RevenueCat integration. This lane does not rewrite that plan and does not make application-code or SDK changes while the implementation contract is being prepared.

The desired outcome is a single identity and authority chain:

`verified Account.id` -> `Purchases.logIn(accountId)` -> RevenueCat customer -> authenticated RevenueCat webhook -> Account entitlement record -> authenticated `GET /api/me/entitlement` and an explicit premium enforcement hook.

At login, the existing Account identifier must be linked to RevenueCat. At the logout boundary, the RevenueCat customer must be logged out before the old account context can be reused. RevenueCat webhook events are the backend synchronization input; the backend stores one `premium` state per Account and handles retries idempotently. The client may render purchase state, but it must not be the authority for a server-paid operation.

The plan is `pending` because the repository currently documents the Account/auth policy but does not contain the runtime auth boundary or a named Account-paid route. Those gaps are explicit work and blockers below; no SDK, token, receipt, webhook payload, or auth-provider behavior is inferred without evidence.

### Brainstorm and selected approach

| Approach | Shape | Trade-off | Decision |
| --- | --- | --- | --- |
| A. Client-only CustomerInfo | Read RevenueCat CustomerInfo and gate UI locally. | Smallest change, but a client can be stale or tampered with and the backend cannot enforce account access. | Rejected for this scope. |
| B. Client-to-server receipt/entitlement handoff | Send a client receipt or token and let the API decide. | Could provide a bridge, but introduces an unverified trust boundary and a new receipt/token contract that current evidence does not define. | Rejected for the minimal design. |
| C. Account link plus webhook authority | Link the existing Account to RevenueCat at login/logout, accept authenticated idempotent provider events, and read the caller's server entitlement. | Requires an auth verifier, persistence, webhook configuration, and explicit paid-route scope; keeps one identity, one entitlement, and no billing subsystem. | Selected. |

The selected approach is the smallest design that satisfies account isolation and backend enforcement. `Purchases.logIn(accountId)` and `Purchases.logOut()` are required target behavior from the intent brief, not evidence that the current adapter already supports them; WI-01 freezes the boundary and WI-02 verifies the SDK and runtime call sites before implementation.

### Ownership and phase boundary

| Phase | Work item | Scope and owner boundary |
| --- | --- | --- |
| 0. Contract and evidence | WI-01 | Freeze Account-to-RevenueCat identity, one `premium`, event/API invariants, and unresolved evidence. This lane owns the sync contract; FEAT-013/014 remain owners of auth/session lifecycle. |
| 1. Mobile identity link | WI-02 | Add the link at the real successful-login and logout/account-switch boundaries, reusing the existing Account context. The old UI purchase lane owns offering/purchase/restore UI. Account-bound purchase begins only after sign-in; anonymous purchase transfer is not assumed. |
| 2. Backend synchronization | WI-03 | Backend-enforcement work begins here and may proceed from WI-01 independently of mobile implementation: minimal entitlement persistence, server-only webhook verification, account mapping, and idempotent state updates in `pose-extract-server`. |
| 3. Read and enforce | WI-04 | Add authenticated `GET /api/me/entitlement`, account isolation, and a fail-closed premium hook for a route explicitly designated as paid. Existing public routes are not reclassified by this plan. |
| 4. Verification and rollout | WI-05 | Review consistency, run repository checks, exercise cross-account and provider retry cases, and record external/native blockers. |

The General Lead remains the single outcome owner. The companion UI plan, FEAT-013, and FEAT-014 are dependencies/owners for their bounded concerns, not parallel outcome hierarchies.

### Minimal implementation shape

- Identity is the verified existing `Account.id` (also called `accountId` at the integration boundary). No new auth provider, credential format, client token, or receipt handoff is introduced. The exact runtime source of this ID is unresolved until FEAT-013/014 auth code exists or is supplied.
- The mobile boundary is deliberately narrow: call `Purchases.logIn(accountId)` after a valid login has established the Account, and call `Purchases.logOut()` at logout/account-switch before the old customer context can leak. The implementation must use the installed RevenueCat SDK contract and handle asynchronous success/failure without granting access merely because the call returned.
- An Account-bound purchase starts only after a valid signed-in Account exists. A signed-out paid trigger enters the existing sign-in flow first; this lane does not start an anonymous purchase or rely on provider-specific anonymous-to-Account alias/transfer behavior. Unknown or unmapped provider customers remain fail-closed.
- Logout is fail-closed even offline: invalidate local in-memory purchase/entitlement state immediately, do not block local auth logout on a RevenueCat network result, call the provider logout boundary, and do not allow the next Account to reuse the old provider context until the SDK-supported reset or a fresh Account sync is complete. Exact SDK reset/cache behavior remains an implementation-time evidence item.
- The model has exactly one entitlement, `premium`, and retains the existing `default` offering. No plan tier, product catalog, billing service, event bus, admin dashboard, or second entitlement is added.
- The proposed provider boundary is a server-only `POST /api/webhooks/revenuecat`. Its header, signature/secret mechanism, event identifier, customer identifier, entitlement fields, and ordering metadata must come from official provider/configuration evidence in WI-01/WI-03; the plan intentionally does not invent those names. Validation must happen before persistence, and a unique provider event identity must make a replay a no-op.
- The proposed caller endpoint is authenticated `GET /api/me/entitlement`; it derives the Account from the verified session and accepts no account ID query/body selector. A minimal response shape for implementation review is `200 {"data":{"entitlement":{"id":"premium","active":true}}}` and `401 {"error":{"code":"UNAUTHORIZED","message":"Unauthorized"}}`. This is a proposed contract, not current runtime evidence, and must be aligned with the repository's existing response/error conventions in WI-04.
- The minimal entitlement persistence must follow the current server schema reality: store `account_id TEXT NOT NULL PRIMARY KEY` (matching `poses.owner_account_id`) without a foreign key to an `accounts` table that does not currently exist. Add a foreign key only with a separate, verified local Account-table migration/decision.
- Backend premium enforcement starts in WI-03/WI-04, but the exact paid route remains a Cook blocker. The current API convention identifies `POST /api/extract-pose` as a Visitor route; this plan does not silently change it, nor community/admin routes. Once Product explicitly names an Account-paid route, its middleware must derive the caller Account, require stored active `premium`, and fail closed on missing, stale, invalid, or unavailable entitlement state.
- Do not persist raw receipts, provider secrets, access tokens, or raw webhook bodies unless a later security decision explicitly requires a redacted audit field. No client-supplied account selector can influence another Account's result.

### Dependencies and blockers

1. FEAT-013 and FEAT-014 are proposed and describe Account/session policy, but repository scans found no mobile login/logout implementation or server Account-auth verifier. The real login-success, logout, expiry, and account-switch hooks must be identified before WI-02/WI-04 can be implemented.
2. RevenueCat webhook authentication, payload/event schema, customer identity field, ordering semantics, and Sandbox configuration are external/configuration evidence not present in the repository. WI-03 cannot be closed with guessed SDK or webhook fields.
3. `pose-extract-server` currently has no Account table, entitlement table, user-auth middleware, webhook route, or entitlement environment settings. WI-03 must introduce only the minimal persistence and wiring needed, while preserving existing admin authentication as a separate boundary.
4. No current route is explicitly documented as an Account-paid operation. WI-04 can build the fail-closed hook and `GET /api/me/entitlement`, but selecting the first production route to protect is a material Product decision. Recommended default: leave `/api/extract-pose` and all current public routes unchanged until that decision is recorded.
5. The companion UI plan still depends on external RevenueCat/App Store configuration and retains its own historical verification state. Its configuration blocker is not silently resolved by this account-sync plan.

### Verification ledger

| Claim | Status | Evidence / consequence |
| --- | --- | --- |
| One `premium` entitlement and `default` offering are already the common purchase vocabulary. | Verified | `PurchaseCore.kt` and `RevenueCatAdapter.swift` define `premium`, `default`, and the existing product IDs. |
| The iOS adapter can currently receive an Account ID and call RevenueCat login/logout. | Failed | `RevenueCatAdapter.swift` has configuration/offering/purchase/restore/customer-info handling but no `Purchases.logIn`, `Purchases.logOut`, or Account input. |
| Login/logout hooks are wired at app runtime. | Failed | `AppDelegate.swift` configures RevenueCat at launch only; `srcwalk` login/logout scans found no mobile implementation. |
| FEAT-013/014 provide the runtime auth/session verifier and Account ID source. | Unresolved | Their feature documents define policy and ownership, but implementation/runtime evidence is absent in this worktree. |
| The backend already exposes a user entitlement endpoint or RevenueCat webhook. | Failed | `app.ts`, `index.ts`, `env.ts`, and `schema.sql` contain no such route/config/table; `package.json` has no RevenueCat backend integration. |
| Existing API conventions have an Account-authenticated, paid route. | Failed | The conventions document lists `POST /api/extract-pose` as Visitor and does not define an entitlement route. This makes paid-route selection a blocker. |
| Provider webhook contract and Sandbox credentials/configuration are available locally. | Unresolved | No verified header, payload, secret, or external environment evidence is present. |
| Backend test/lint/build toolchain is available in this checkout. | Failed | The attempted server commands exited 127 because `vitest` and `tsc` are not installed; no dependency installation was performed. |
| Repository-wide index validation is clean. | Failed (outside this lane) | `harness index check`/`harness validate --all` report pre-existing FEAT-015 `decision_dependencies` format errors and a duplicate REP-012; the FEAT-011 target itself has no such finding. |
| Planning changes are docs-only and preserve unrelated worktree state. | Verified | The existing untracked `.tmp/` was observed and is not part of this plan's mutation scope. |

## Work Items

- [ ] [Work Item 1: Freeze Account-to-RevenueCat identity boundary](./work-item-01-freeze-account-to-revenuecat-identity-boundary.md)
- [ ] [Work Item 2: Link RevenueCat customer at login and logout boundaries](./work-item-02-link-revenuecat-customer-at-login-and-logout-boundaries.md)
- [ ] [Work Item 3: Add backend entitlement persistence and idempotent webhook](./work-item-03-add-backend-entitlement-persistence-and-idempotent-webhook.md)
- [ ] [Work Item 4: Expose authenticated entitlement API and enforce account isolation](./work-item-04-expose-authenticated-entitlement-api-and-enforce-account-isolation.md)
- [ ] [Work Item 5: Verify cross-account sync, backend enforcement, and rollout](./work-item-05-verify-cross-account-sync-backend-enforcement-and-rollout.md)

## Coverage

| Feature requirement / constraint | Covered by |
| --- | --- |
| FR001-FR005: one premium entitlement, default offering, purchase/restore UI, clear states, and existing paid UI boundary | Companion UI plan `260826-0003`, with vocabulary reconciled in WI-01 and regression coverage in WI-05 |
| FR006: a purchase belongs to the signed-in Account | WI-01 freezes the identity mapping; WI-02 links the mobile customer; WI-03 persists the server mapping; WI-05 verifies Account A/B |
| FR007: login/re-entry follows the Account and logout/switch clears the prior customer | WI-02 and WI-05 |
| FR008: one premium state is updated by authenticated, idempotent provider events | WI-01 and WI-03, verified by WI-05 replay/order tests |
| FR009: authenticated `GET /api/me/entitlement` returns only the caller's state | WI-01 and WI-04, verified by WI-05 unauthenticated/cross-account tests |
| FR010: backend enforcement is fail-closed and does not trust client/local state | WI-03 and WI-04, verified by WI-05 |
| BR001-BR004: no secret/receipt/token leakage; no access without confirmation; preserve UI boundary; reuse auth and avoid extra services/entitlements | WI-01 through WI-05 |
| NFR001: Account isolation | WI-01, WI-03, WI-04, and WI-05 |
| Dependencies, blockers, and external/native verification | Overview ledger plus WI-01/WI-05 |

## Verification

The plan is ready for implementation review only; it is not approved. Run the following after each implementation slice and record the output in WI-05:

1. Structural/document checks: `harness validate docs/harness/features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md --workspace . --json`, `harness validate docs/harness/plans/260905-1135-feat-011-revenuecat-account-sync-and-entitlement-enforcement --workspace . --json`, `harness workflow status docs/harness/plans/260905-1135-feat-011-revenuecat-account-sync-and-entitlement-enforcement --workspace . --json`, and `harness workflow check docs/harness/plans/260905-1135-feat-011-revenuecat-account-sync-and-entitlement-enforcement --workspace . --json`.
2. Repository indexes/consistency: `harness index check --workspace . --json`, `harness graph check --workspace . --json`, `git diff --check`, and a manual re-read of the Feature, this plan, and all five WIs for scope/terminology contradictions.
3. Backend implementation checks when WI-03/WI-04 land: `npm --prefix web/services/pose-extract-server test`, `npm --prefix web/services/pose-extract-server run lint`, and `npm --prefix web/services/pose-extract-server run build`, plus database migration/replay tests and authenticated endpoint tests.
4. Mobile checks when WI-02 lands: the repository's existing Gradle/KMP tests and an iOS compile/typecheck with the locked RevenueCat module available. If the module or auth runtime is unavailable, record the exact failure; do not convert a static inspection into a pass.
5. External Sandbox checks: login as Account A, purchase/restore, relaunch/re-entry, logout, login as Account B, replay valid/duplicate/invalid webhook events, query only A/B's own entitlement, exercise the explicitly designated paid route, and confirm existing public routes remain unchanged. Verify fail-closed behavior for missing, invalid, stale, and unavailable entitlement state.

The final evidence must include the account-isolation matrix, idempotency result, route-scope decision or blocker, secret/receipt/token audit, and the list of commands actually run. Until the unresolved auth/provider/paid-route items are closed and the repository maintainer approves the plan, status remains `pending`.
