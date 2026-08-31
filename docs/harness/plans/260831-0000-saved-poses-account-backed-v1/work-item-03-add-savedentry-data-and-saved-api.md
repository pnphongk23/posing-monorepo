---
work_item: 3
title: Add SavedEntry data and Saved API
status: pending
priority: P2
effort: M
dependencies: [2]
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

Exact migration/store/route symbols; tests for 200, duplicate, 204, invalid 404, 401, pagination, removal retention; backend command.

