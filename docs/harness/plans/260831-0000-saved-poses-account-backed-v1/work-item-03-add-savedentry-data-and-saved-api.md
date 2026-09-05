---
work_item: 3
title: Add SavedEntry data and Saved API
status: completed
priority: P2
effort: M
dependencies:
  - 2
decision_dependencies: []
---

# Work Item 3: Add SavedEntry data and Saved API

## Tasks

- Add migration/schema and SavedEntry with unique(accountId, poseId).
- Add protected GET /api/me/saved, PUT /api/me/saved/:poseId and DELETE /api/me/saved/:poseId.
- Reuse CommunityPose projection, pagination and error envelope.
- Save published returns 200/idempotent; Unsave returns 204/idempotent; invalid returns policy 404 and creates no entry.
- GET/list returns only published usable poses. Unpublish/terminal delete retains SavedEntry persistence-side; no tombstone list model or automatic delete.

## Scope and affected files

Backend migration/store/routes/tests with WI-02 auth; no Album tables/routes.

## Success criteria

Cross-account isolation, DB uniqueness, filtering and removal retention are testable.

## Risks

Cascade deletion, duplicate race, public data leak or 404/409 mismatch.

## Required evidence

Implemented evidence:

- `web/services/pose-extract-server/src/db/schema.sql`: `saved_entries` uses composite primary key `(account_id, pose_id)` (therefore unique per account/pose), with no cascading foreign key so entries survive pose unpublish and terminal delete. Account-scoped pagination and pose lookup indexes are present.
- `web/services/pose-extract-server/src/db/savedStore.ts`: `SavedStore.save`, `remove`, `list`, and `getUsablePublishedPose`; save uses conflict-safe idempotent insertion and requires a published pose with all three media roles ready. List filters the same published+ready predicate.
- `web/services/pose-extract-server/src/routes/savedRoutes.ts`: `createSavedRoutes` exposes protected GET `/api/me/saved`, PUT `/api/me/saved/:poseId`, and DELETE `/api/me/saved/:poseId`, mounted through the existing Account auth middleware and public CommunityPose projection.
- `web/services/pose-extract-server/src/db/savedStore.test.ts` and `web/services/pose-extract-server/src/routes/savedRoutes.test.ts`: cover 200 duplicate-idempotent PUT, 204 idempotent DELETE, invalid/unusable 404 with no entry, pagination, published+ready filtering, cross-account isolation, retention after unpublish/delete, projection, and 401 `UNAUTHORIZED` envelope through the Account boundary.

Verification evidence:

- Focused backend tests: 3 files, 13 tests passed.
- Full backend tests (serial): 27 files, 149 tests passed.
- Backend lint and build passed.
- `ckh validate --all --workspace .`, `ckh workflow check docs/harness/plans/260831-0000-saved-poses-account-backed-v1 --workspace .`, and `git diff --check` passed.

Pending-validation:

- Live Supabase provisioning, live JWT/JWKS verification, and production database/runtime behavior remain Pending-validation; they are not claimed as verified here.

Frozen boundaries:

- No Albums/WI-06, social sharing, ownership/publish changes, mobile/UI work, or WI-04/WI-05 work is included; WI-04 and WI-05 remain queued.
