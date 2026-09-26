---
phase: 3
title: "Server API + admin proxy"
status: pending
priority: P1
effort: "5h"
dependencies: [1]
---

# Phase 3: Server API + admin proxy

## Overview
Expose the owner-scoped job API, make the Pose readable, require auth on submit, and keep the admin intake working.

## Requirements
- Functional (see openapi for shapes):
  - `POST /api/extract-pose`: AccountSession or AdminBearer (D5). Multipart fields `image`, `name` (1–80 chars, trimmed),
    `tags` (sent as a repeated `tags` field or a JSON array string, 1–10 items, each 1–30 chars; name/tags required for accounts),
    and optional `description` (≤500). Invalid input → 400 `INVALID_METADATA`. Anonymous → 401.
  - `GET /api/extract-jobs/:jobId`: AdminBearer sees any job (unchanged payload). AccountSession sees only its own jobs, otherwise 404,
    and the response includes `poseId` (D6).
  - `GET /api/me/extract-jobs?state&cursor&limit`, `POST /api/me/extract-jobs/:id/retry` (202 / 404 for missing, foreign or hidden / 409 `JOB_NOT_RETRYABLE`),
    `DELETE /api/me/extract-jobs/:id` (204 / 404). **AccountSession only** (D10).
  - `GET /api/guides/:id`: owner only (404 otherwise), returns the `Pose` schema with media URLs. It is read-only; no other `/api/guides` verbs are added.
- Non-functional: all routes keep the existing extract rate limiter, and error envelopes match `ErrorEnvelope`.

## Architecture
- Add `createAccountOrAdminAuth({ adminSecret, accountAuth })` in `src/middleware/`. It tries `Bearer <adminSecret>` first
  (constant-time compare, reusing the `adminAuth.ts` logic), then falls back to the account middleware. It sets `req.account` or `req.isAdmin`.
- New router `src/routes/myExtractJobsRoutes.ts`, mounted at `/api/me/extract-jobs` behind account auth.
- New router `src/routes/guideReadRoutes.ts`, mounted at `/api/guides` with GET `/:id` only, reusing `communityStore` pose + media lookups.
- In `app.ts`, mount these only when `extractionJobStore` **and** account auth are configured. With no account auth, keep the current
  behaviour for `/api/extract-pose` but require the admin bearer, so the endpoint is never left anonymous.
- Admin-ui: `web/admin-ui/src/lib/poseExtractExtractPoseProxy.js` adds `Authorization: Bearer ${adminSecret}`. `getAdminConfig`
  is module-private in `poseExtractAdminServer.js:3`, so Phase 3 exports it and the proxy imports it with an explicit extension (`import { getAdminConfig } from './poseExtractAdminServer.js'`), which Node's ESM loader requires under `node --test`. The secret therefore has a single source.
- Contract delta (D7): add a nullable `thumbnailUrl` to `ExtractionJobListItem` in `docs/harness/specs/api/openapi.yaml`, and add one line in
  `docs/harness/specs/api-contract.md`. Add the `INVALID_METADATA` and `POSE_MATERIALIZE_FAILED` codes if they are missing.
  Remove `AdminBearer` from the `security` of the three `/api/me/extract-jobs*` operations (D10) and of `GET /api/guides/{id}` (owner-only here).

## Related Code Files
- Create: `src/middleware/accountOrAdminAuth.ts` (+test), `src/routes/myExtractJobsRoutes.ts` (+test), `src/routes/guideReadRoutes.ts` (+test)
- Modify: `src/routes/extractPoseRoutes.ts`, `src/routes/extractJobsRoutes.ts`, `src/app.ts`, `src/extractPose.test.ts`
- Modify: `web/admin-ui/src/lib/poseExtractExtractPoseProxy.js`, `web/admin-ui/src/lib/poseExtractAdminServer.js` (export `getAdminConfig`)
- Modify: `docs/harness/specs/api/openapi.yaml`, `docs/harness/specs/api-contract.md` (D7 delta only)

## Implementation Steps
1. Add the dual-auth middleware and its tests (admin ok, account ok, anonymous 401, wrong bearer falls through to account and gets 401).
2. Update submit to parse and validate the draft and pass the owner and draft to `enqueue`. Update `extractPose.test.ts`.
3. Scope the job GET by owner, then add the `/api/me/extract-jobs` router and the guides read router.
4. Mount everything in `app.ts` and patch the admin-ui proxy. Add `web/admin-ui/src/lib/poseExtractExtractPoseProxy.test.mjs`, run with
   Node's built-in runner (`node --test`), since admin-ui has no test runner. It stubs `fetch` and env and asserts `callPoseExtractExtractPose`
   sends `Authorization: Bearer <configured secret>`, using a dummy secret set in the test.
5. Integration tests with two accounts (A/B) covering every route, including `limit`/`cursor` validation (400 on bad values).
6. Apply the openapi/api-contract delta, then confirm `openapi.yaml` still parses.

## Success Criteria
- [ ] `npm test` and `npm run lint` pass in `pose-extract-server`.
- [ ] The owner-isolation integration test passes for GET job, list, retry, hide and GET guide.
- [ ] `node --test web/admin-ui/src/lib/poseExtractExtractPoseProxy.test.mjs` passes, and so does `npm run lint` in `web/admin-ui`.
- [ ] `python3 -c "import yaml;yaml.safe_load(open('docs/harness/specs/api/openapi.yaml'))"` exits 0.

## Risk Assessment
- The admin-ui has not deployed the bearer patch yet → admin extract returns 401. **Deploy admin-ui first, then the server** (plan.md R2). The patch
  is backward compatible because today's server ignores the header. The phase handback repeats this order.
- How multipart `tags` gets parsed differs between clients → accept both forms, and cover both in tests.
