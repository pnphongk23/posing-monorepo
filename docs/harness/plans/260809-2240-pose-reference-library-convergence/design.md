# Pose Reference Library Design and Brainstorm

## Scope boundary

This Plan owns My Poses/Community browsing, client-side pagination and recovery,
dedicated title search, local/community detail, and local-only My Poses deletion
for an iOS-first slice. It emits a typed selected reference but does not render
it in Camera. Public uploads, social interactions, offline community caching,
Android delivery, production implementation of the absent server title-search
endpoint, and advanced/server full-text search remain out of scope.

## Approaches considered

### A — Patch `PosesViewModel` and current screens in place

Add flags, callbacks, a search screen, and file deletion directly around the
existing view models. This is the smallest diff, but keeps HTTP/database
construction, extraction, pagination, UI state, and failures coupled. Race and
compensation paths remain difficult to test deterministically.

### B — Small library coordinator with explicit ports (recommended)

Introduce immutable `PoseReference` variants for personal/community sources, a
library coordinator/reducer, and injected local repository, community service,
storage, and dispatcher/clock boundaries. Compose renders state and emits
actions; Voyager routes carry stable typed keys rather than whole mutable DTOs.

This preserves the current stack and permits deterministic tests for overlapping
refresh/load-more, retry retention, missing records, and delete compensation.
Extraction stays behind its existing FEAT-004 boundary instead of sharing
library state-machine responsibilities. FEAT-005 administration/publication is
also external; this Plan only consumes the existing published catalog contract.

### C — Unified offline-first cached catalog

Persist community records into SQLDelight and search one local catalog. This
improves offline discovery but requires schema migrations, cache invalidation,
expiry, storage policy, and a broader product promise. FEAT-003 requires retaining
already loaded UI content, not durable offline availability, so defer it.

## Recommended contracts and invariants

- `PoseReferenceKey` is source-qualified (`Personal(Long)` or
  `Community(String)`) so deletion and routing cannot cross catalogs.
- Community state keeps `itemsById` plus stable display order, page/total, and
  independent initial/refresh/load-more operation state. At most one request per
  operation is authoritative; stale completions cannot replace newer state.
- Refresh retains visible items until success. Any failure preserves items and
  exposes a retry action for the failed operation.
- `hasMore` derives from server pagination (`page * limit < total`), not response
  length alone. Appends dedupe by server ID while preserving first-seen order.
- Dedicated search uses a source-neutral contract. Personal records are matched
  case-insensitively and locale-stably; community results come from an injected
  catalog-search port. The initial adapter is a deterministic mock, and a later
  production server adapter must satisfy the same contract without changing UI
  or domain state.
- Detail resolves from the owning source. Missing author, difficulty, or outline
  values remain null and are never fabricated; only My Poses detail exposes delete.
- Personal deletion is entirely local. It makes no server request, deletes only
  confirmed locally owned files and metadata, and reports success only when the
  local invariant is satisfied. Community state is never mutated.
- Feature/Spec documents govern behavior and exclusions. The prototype governs
  concrete composition and presentation only inside that authority; prototype-
  only social interactions remain excluded.

## Approved Maintainer choices

1. **Platform delivery:** deliver iOS first. Android is deferred and cannot be
   counted as acceptance evidence for this Plan.
2. **Community search:** define the complete replaceable search abstraction now,
   use a deterministic mock adapter first, and defer the production server
   adapter/endpoint until the server supports it.
3. **Detail contract:** fields absent from the source contract are nullable.
   Current missing author, difficulty, or outline values resolve to null and the
   UI must not invent substitutes.
4. **Personal deletion:** delete locally owned My Poses files and metadata only.
   Do not add or call a server delete API; community poses never expose delete.
   Before mutation, capture enough local state to retain or restore a usable item
   when a partial local failure occurs.
5. **Authority precedence:** Feature/Spec documents win for behavior and
   exclusions; the prototype wins for concrete UI composition/presentation only
   where the documented behavior permits it. Do not add excluded interactions.
