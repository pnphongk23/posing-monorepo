---
work_item: 3
title: Add backend entitlement persistence and idempotent webhook
status: pending
priority: P1
effort: L
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 3: Add backend entitlement persistence and idempotent webhook

## Tasks

- Add the minimal backend persistence needed to represent one `premium` entitlement per Account and the provider customer identity/event idempotency keys. Reuse the existing database and `pose-extract-server`; do not create a billing service, event bus, admin dashboard, or second entitlement.
- In the current schema reality, define the entitlement `account_id` as `TEXT NOT NULL PRIMARY KEY`, matching `poses.owner_account_id`, without a foreign key to a local `accounts` table that does not exist. Introduce a foreign key only through a separately verified Account-table migration and decision.
- Establish the server-only RevenueCat webhook boundary, proposed as `POST /api/webhooks/revenuecat`, and verify its authentication/signature using official provider/configuration evidence. Reject malformed or unauthenticated notifications before any database mutation.
- Map the provider customer identifier to the existing Account identity. Define safe behavior for an unknown customer, missing Account mapping, duplicate mapping, and invalid entitlement event; none may grant access to an arbitrary Account.
- Because purchases begin only after sign-in in this lane, an anonymous or unmapped provider customer must remain non-premium. If provider-specific alias/transfer events are later required, verify their contract separately before adding handling; do not infer them from an anonymous webhook.
- Process a valid event transactionally: record a unique provider event identity, update the Account's `premium` state, and make a replay a no-op. Define event ordering/terminal-state behavior from verified provider metadata rather than arrival order assumptions.
- Wire the minimum config, schema, store/service, route, and app/index registration required by the existing server conventions. Keep admin Bearer authentication separate from user Account authentication.
- Expose a reusable server entitlement lookup/enforcement seam for WI-04. Missing, stale, invalid, or unavailable state must be treated as not premium.

## Scope and affected files

Expected implementation surface (to be confirmed against the actual auth/store structure):

- `web/services/pose-extract-server/src/db/schema.sql` and a safe migration mechanism/test fixture
- `web/services/pose-extract-server/src/config/env.ts`
- `web/services/pose-extract-server/src/app.ts` and `src/index.ts`
- New focused entitlement store/service and RevenueCat webhook route/middleware under `web/services/pose-extract-server/src/`
- Existing server test/fixture files and API documentation only where the webhook contract is verified
- The existing Account/auth integration seam supplied by FEAT-013/014; no replacement auth middleware

No mobile, Android, App Store, admin dashboard, billing-service, event-bus, or public-route reclassification work belongs here.

## Success criteria

- A valid, authenticated provider event can update only the mapped Account's single `premium` state.
- Replaying the same provider event produces no duplicate effect and leaves the state stable; invalid authentication, schema, mapping, and event identity produce no grant.
- Persistence is transactionally safe and restart-safe, with unique constraints or equivalent evidence for Account/provider identity and provider event idempotency.
- The schema does not reference a missing `accounts` relation; Account IDs remain the verified auth identity until a separate local Account-table contract exists.
- Secrets remain server-only, raw receipt/access-token material is not persisted or logged, and existing admin authentication remains isolated.
- The entitlement lookup seam is available to WI-04 and fails closed for missing, invalid, stale, or unavailable state.
- Migration, webhook, and replay tests pass in the repository's supported backend test command.

## Risks

- The current server has no Account table, user-auth verifier, entitlement table, webhook route, or RevenueCat backend dependency. Adding these against guessed contracts would be a material security error.
- Provider payload fields, signature/header rules, event ordering, and secret provisioning are not in the repository and require authoritative external/configuration evidence.
- Existing schema application is simple; migration must not rely on a destructive reset or silently break current request/community/extraction tables.
- A future Account-table foreign key can be added only after FEAT-013/014 provides a verified local persistence contract; this item must not create a placeholder table merely to satisfy referential integrity.

## Required evidence

- The verified provider webhook authentication and payload/event fixture used by tests, with secrets redacted.
- Database schema/migration diff, unique constraints, transaction/replay tests, and account-mapping tests for A/B/unknown identities.
- A schema check proving `account_id TEXT NOT NULL PRIMARY KEY` has no unresolved foreign-key reference, plus an explicit anonymous/unmapped-customer no-grant test.
- Route tests proving invalid webhook input does not mutate entitlement state.
- Backend test, lint, and build output, plus an explicit note for any unavailable auth/provider environment.
- A documented decision or blocker naming the first premium-protected route; until then no current public route is changed.
