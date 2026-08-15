---
work_item: 2
title: Correct community transport pagination refresh and recovery
status: completed
priority: P1
effort: L
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 2: Correct community transport pagination refresh and recovery

**Kind:** story

## Tasks

- Align mobile list/detail DTOs and nested error envelope with actual backend
  payloads; use the same tolerant, explicit JSON configuration in production and
  tests and add the missing community detail client call.
- Inject the HTTP client/service/repository into a library coordinator instead
  of constructing a Darwin client inside common UI code.
- Model initial, refresh, load-more, success, empty, and retryable failure states
  independently while retaining visible items during refresh/failure.
- Derive `hasMore` from server `page`, `limit`, and `total`; dedupe append results
  by ID with stable order and ignore stale/duplicate requests.
- Surface operation-specific retry actions and preserve published-only trust
  boundary; do not add durable cache or server search.
- Add MockEngine and reducer tests for unknown fields, nested errors, page
  overlap, exact-last-page, empty catalog, refresh replacement, and failure
  retention; repair test-only coroutine dependencies in approved scope.

## Scope and affected files

- `mobile/shared/.../PoseApiService.kt`, `PoseRepository.kt`, shared test source
  sets/Gradle declarations, and new small community contracts/coordinator files.
- `PosesScreen.kt` only for consuming the new state/actions.
- Backend route code only if an approved contract mismatch cannot be solved
  compatibly on the client; no search endpoint expansion.

## Success criteria

- No exception is silently discarded; loaded items survive every request
  failure and the matching retry action is available.
- Pagination cannot display duplicate IDs and stops according to server totals.
- Production and test decoders accept the representative backend payload.

## Risks

- `Json { ignoreUnknownKeys = true }` alone does not fix nullable/type or nested
  envelope mismatches; fixtures must reflect the server contract.
- Concurrent refresh/load-more completions can corrupt page/order without
  operation identity.

## Required evidence

- MockEngine/reducer test output, representative payload fixtures, backend route
  tests, and a state-transition trace for refresh and pagination failure.
