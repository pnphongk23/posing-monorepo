---
work_item: 2
title: Add Account infrastructure and session boundary
status: pending
priority: P2
effort: M
dependencies: [1]
decision_dependencies: []
---

# Work Item 2: Add Account infrastructure and session boundary prerequisite

FEAT-014 owns the observable Account screen and session lifecycle/sign-out policy.
This Work Item only supplies or verifies the technical Account/session boundary
that FEAT-013 consumes; it must not claim delivery of FEAT-014 UI or runtime auth
until repository evidence exists.

## Tasks

- Implement or verify only the frozen Supabase Auth Google-only boundary: Google is the only enabled provider for v1;
  all other providers are disabled/out of scope.
- Implement or verify Account infrastructure/persistence and session verification
  using repository evidence and the existing account/session boundary.
- Implement or verify the existing mobile token/session boundary and FR-007 401
  refresh/clear behavior using existing conventions; invalid sessions must not leak
  another collection and signed-out Save/Saved/Try actions remain gated.
- If Product Authority approves the related proposals, verify identity correlation
  to one Account without duplicate Accounts.
- If Product Authority approves the proposal details, verify secure OS token
  storage, expiry/silent-refresh specifics, and sign-out affordance policy.
- If approved, verify minimal OAuth scopes/privacy, provider-disable guard,
  Supabase config/secrets boundary, and server-side JWT verification before
  Account authorization.
- Keep account/provider deletion, callback/deep-link handling, and App Store 4.8
  as Unresolved/open proposals; do not invent SDK, env names, URL mechanics, or
  silently change the Google-only contract.
- Ensure protected requests return 401 without cross-account leakage and signed-out actions are gated.
- Do not invent a concrete SDK/dependency without repository evidence.

## Scope and affected files

Auth middleware/verifier, Account persistence, mobile session boundary and tests discovered during execution; excludes FEAT-014 Account UI/sign-out product behavior, Albums, ownership/publish, FEAT-012 and camera changes.

## Success criteria

If the identity-mapping proposal is approved, evidence should show valid identity
maps to one Account without duplicates. Independently, invalid session cannot read
another collection; existing FR-007 refresh/clear returns user to sign-in.

## Risks

Provider SDK/config runtime path is currently Unresolved and may require Maintainer
evidence; no runtime integration is shipped or verified until this WI supplies it.

## Required evidence

Exact paths/symbols, dependency/config paths, valid/expired-token tests, 401 test, backend/mobile commands and ckh validate.
