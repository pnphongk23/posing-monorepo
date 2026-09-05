---
work_item: 4
title: Expose authenticated entitlement API and enforce account isolation
status: pending
priority: P1
effort: M
dependencies:
  - 3
decision_dependencies: []
---

# Work Item 4: Expose authenticated entitlement API and enforce account isolation

## Tasks

- Reuse the verified Account-auth middleware/session boundary owned by FEAT-013/014. Derive the caller Account on the server; do not accept an account ID in query parameters, request bodies, or client entitlement claims.
- Add the authenticated `GET /api/me/entitlement` endpoint using the repository's response/error conventions. Return the caller's single `premium` state and `401` for missing/invalid auth; do not disclose another Account's existence or state.
- Add the server entitlement enforcement hook established by WI-03. For a route explicitly designated as premium, require the stored active `premium` state and fail closed on missing, stale, invalid, or unavailable state.
- Keep `POST /api/extract-pose`, community routes, and admin routes at their documented access class until Product names a paid Account route. Record route selection as a Cook blocker rather than silently reclassifying an existing public operation.
- Update `docs/spec/api/conventions.md` and `docs/spec/api/openapi.yaml` only after the auth/response/webhook contract is verified. Add endpoint, error, isolation, and premium-hook tests; update mobile client/state only if an existing authenticated API path is present.

## Scope and affected files

Expected implementation surface:

- `web/services/pose-extract-server/src/` authenticated route/middleware/service registration from WI-03 and the existing auth owner
- `docs/spec/api/conventions.md` and `docs/spec/api/openapi.yaml`
- Focused backend endpoint, isolation, enforcement, and error tests
- Existing mobile API client/state only if FEAT-013/014 provides a real authenticated session path

This item does not add an auth provider, token format, billing service, admin endpoint, entitlement tier, or client-side bypass. It does not choose a paid route without the Product decision.

## Success criteria

- An authenticated Account A receives only A's `premium` entitlement from `GET /api/me/entitlement`; Account B receives only B's state; no selector can cross the boundary.
- Unauthenticated, invalid, forged, and expired sessions receive the repository-standard unauthorized response without a state leak.
- A designated premium route checks server state, not local CustomerInfo or a client boolean, and returns a documented fail-closed response when state is absent or unavailable.
- Existing public/admin route behavior is unchanged until a named paid-route decision is recorded.
- OpenAPI/convention documentation and automated tests describe the same endpoint/error/isolation contract.

## Risks

- No runtime Account-auth verifier exists in the current server evidence, so endpoint implementation is blocked until FEAT-013/014 supplies the real session contract.
- The first paid route is a material product decision; selecting `/api/extract-pose` by implication would violate the current Visitor contract.
- Response wrapper/error conventions may differ from the proposed minimal shape and must be reconciled before docs are treated as API truth.

## Required evidence

- Authenticated endpoint tests for A/B, unauthenticated, invalid/expired, forged account selector, and missing entitlement cases.
- Enforcement tests for active premium, inactive premium, missing record, provider/database failure, and the explicitly named route.
- OpenAPI/conventions diff and validation showing no unintended route reclassification.
- A security review confirming account derivation is server-side and no secret/receipt/token is accepted from the client.
