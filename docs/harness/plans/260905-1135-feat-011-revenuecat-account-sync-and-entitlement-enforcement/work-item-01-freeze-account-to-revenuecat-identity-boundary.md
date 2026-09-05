---
work_item: 1
title: Freeze Account-to-RevenueCat identity boundary
status: pending
priority: P1
effort: M
dependencies: []
decision_dependencies: []
---

# Work Item 1: Freeze Account-to-RevenueCat identity boundary

## Tasks

- Reconcile FEAT-011 with the companion UI/purchase plan. Keep the existing one-entitlement vocabulary (`premium`) and `default` offering, while making the new Account-sync/backend scope explicit and preserving the earlier UI lane's ownership.
- Freeze the identity boundary as the verified existing `Account.id`/`accountId` from the authenticated session. Do not introduce a new auth provider, credential/session token, client receipt, client entitlement claim, or second customer identity.
- Define the required mobile lifecycle invariants: `Purchases.logIn(accountId)` only after a successful Account login, and `Purchases.logOut()` at logout/account-switch before the old customer context can be reused. Mark these as target behavior because the current adapter has no such calls.
- Define the backend invariants: provider customer identity must map to exactly one Account, the server owns the stored `premium` state, provider notifications are authenticated and idempotent, and a caller can read only its own entitlement.
- Record the proposed webhook and entitlement endpoint boundaries without guessing provider header names, payload fields, SDK signatures, auth token formats, or receipt semantics. Route selection for the first premium-protected operation remains a Product/Cook blocker.
- Document the default that existing Visitor/public routes, including `POST /api/extract-pose`, are not silently reclassified as paid.

## Scope and affected files

This is a documentation/contract work item. Update the FEAT-011 feature and this plan only; use the following as read-only evidence:

- `docs/harness/features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md`
- `docs/harness/features/FEAT-013-saved-poses-albums-account-backed.md`
- `docs/harness/features/FEAT-014-manage-account-and-session.md`
- `docs/spec/data/entities/account.md`
- `docs/spec/api/conventions.md` and `docs/spec/api/openapi.yaml`
- `mobile/composeApp/src/commonMain/kotlin/com/aipose/purchases/PurchaseCore.kt`
- `mobile/iosApp/iosApp/RevenueCatAdapter.swift` and `mobile/composeApp/src/iosMain/kotlin/com/aipose/purchases/IosRevenueCatGateway.kt`
- `web/services/pose-extract-server/src/app.ts`, `src/config/env.ts`, `src/db/schema.sql`, `src/index.ts`, and `src/middleware/adminAuth.ts`

## Success criteria

- The Feature, plan, and companion UI plan have no contradictory ownership or scope language.
- The identity mapping, login/logout boundary, single-entitlement rule, webhook authority, account isolation, and fail-closed rule are each stated as observable invariants.
- Current evidence and missing evidence are separated with `Verified`, `Failed`, and `Unresolved` status; no SDK/token/provider contract is presented as already implemented.
- Backend enforcement is identified as beginning in WI-03 and WI-04, while the exact paid route is explicitly recorded as blocked rather than inferred.
- The plan remains `pending` until implementation evidence and repository-maintainer approval exist.

## Risks

- FEAT-013/014 describe auth/session ownership but have no verified runtime implementation in this worktree, so the Account ID source and lifecycle hooks may move.
- RevenueCat webhook authentication, payload/event ordering, and Sandbox configuration are external facts; guessing them would create an unsafe contract.
- The previous FEAT-011 approval covered UI/native purchase behavior only. The feature is intentionally `proposed` again after this material scope expansion.

## Required evidence

- Source inspection showing the current adapter/gateway vocabulary and the absence of current `logIn`/`logOut` or Account input.
- Source inspection showing current API route/auth boundaries and the absence of entitlement/webhook persistence.
- A successful feature/plan validation plus a manual consistency read of FEAT-011, this plan, and all five work items.
- A clean `git diff --check`; no application code, tests, SDK lockfiles, secrets, or unrelated `.tmp/` files changed by this planning work.
