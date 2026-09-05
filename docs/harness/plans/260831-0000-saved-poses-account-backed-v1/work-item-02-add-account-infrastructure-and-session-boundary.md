---
work_item: 2
title: Add Account infrastructure and session boundary
status: completed
priority: P2
effort: M
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 2: Add Account infrastructure and session boundary

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

Auth middleware/verifier, Account persistence, mobile session boundary and tests discovered during execution; excludes Albums, ownership/publish, FEAT-012 and camera changes.

## Success criteria

If the identity-mapping proposal is approved, evidence should show valid identity
maps to one Account without duplicates. Independently, invalid session cannot read
another collection; existing FR-007 refresh/clear returns user to sign-in.

## Risks

Provider SDK/config runtime path is currently Unresolved and may require Maintainer
evidence; no runtime integration is shipped or verified until this WI supplies it.

## Required evidence

Exact paths/symbols, dependency/config paths, valid/expired-token tests, 401 test, backend/mobile commands and ckh validate.

## Current evidence (2026-09-03)

- Backend implementation is landed in `web/services/pose-extract-server`: `accounts` schema, `AccountStore.upsert/getById`, server-side Account JWT verifier with issuer/audience/expiry/kid validation and ES256/RS256 JWKS support, Google-only state+PKCE OAuth routes using fixed `BACKEND_PUBLIC_URL`, opaque one-time handoff/session exchange, refresh route, and existing 401 envelope.
- Backend route-registration integration evidence proves `/api/auth/google/start` is reachable during `createApp` construction and `/api/account/me` returns the existing 401 envelope without Bearer.
- Mocked JWKS/provider contract tests cover valid/expired claims, issuer/audience/signature/key-id/algorithm rejection, state mismatch/replay/expiry, PKCE binding, fixed redirect against Host/protocol injection, opaque callback handoff, one-time session consumption, refresh failure, 401 behavior, and Account correlation. These tests are not live-runtime verification.
- Mobile artifacts are landed: common `SecureTokenStorage`/`SessionBoundary`, iOS `platform.Security` Keychain storage, Android SharedPreferences dev-only/out-of-scope parity, API Bearer attachment, one refresh attempt followed by clear and `SignInRequired`, iOS `ASWebAuthenticationSession` callback parser/session exchange, `aipose` URL registration, and Xcode project wiring. Simulator/typecheck evidence is recorded separately from live verification.
- WI-02 implementation evidence supports completion, but live provisioning remains explicitly Pending-validation.

## Pending-validation and unresolved findings

- Live Supabase health is Pending-validation: the probe without an API key returned HTTP 401 (`No API key found in request`); no key was guessed.
- Live JWKS/OAuth/token exchange/end-to-end verification is Pending-validation. The observed JWKS advertised ES256/EC with the case-insensitively matching kid; production `BACKEND_PUBLIC_URL` provisioning is not verified.
- Account persistence against the live database and cross-account isolation at runtime are not verified; Account correlation/isolation evidence is mocked/unit-level only.
- Android target compile is unavailable, and the full Xcode app build is blocked by environment contention. These are compile/build evidence gaps, not live verification.
- HS256-with-secret remains only a documented fallback if a real JWT Secret is supplied; no secret is inferred or hardcoded.

## Queue and status boundary

WI-03 and WI-04 are `completed`; WI-05 is `in_progress`. Account/session evidence here does not authorize additional Saved routes or Saved UX, Albums, ownership/publish work, or any other scope expansion. Frozen non-goals and provider/config runtime uncertainties remain unchanged.
