# Phase 3 evidence — Server API + admin proxy

Worker: `fb7864e4` (Lính · Lữ Bố, agy/gemini-3.7-flash-medium). First handback claimed done but
never actually ran `npm test` after adding dual auth — all 9 `extractPose.test.ts` tests broke
(401 instead of their real assertions) because the test file wasn't updated. Sent one BLOCKER
cycle with the exact failures. Second handback fixed it properly (built real JWT signing test
infra for two-account coverage, not just an admin-bearer patch) and Lead independently re-verified.

## Changed/created files
- `src/middleware/accountOrAdminAuth.ts` (+test) — tries admin bearer (constant-time compare) first, falls through to account auth, else 401.
- `src/routes/myExtractJobsRoutes.ts` (+test) — `/api/me/extract-jobs` GET/retry/hide, AccountSession only.
- `src/routes/guideReadRoutes.ts` (+test) — `/api/guides/:id`, read-only, owner-only.
- `src/routes/extractPoseRoutes.ts`, `extractJobsRoutes.ts` — dual auth, draft validation, owner scoping, `poseId` in response.
- `src/app.ts` — dual-auth middleware wiring; `/api/me/extract-jobs` mounted only when `extractionJobStore` + account auth configured; `/api/guides` mounted only when `communityStore` + account auth configured (applies the plan-review cycle-7 non-blocking note).
- `src/extractPose.test.ts` — rewritten with real ES256 JWT signing (test JWKS) for two synthetic accounts (A/B), used throughout for owner-isolation coverage; legacy/admin-path assertions now send the admin bearer and keep their original expected status codes.
- `web/admin-ui/src/lib/poseExtractExtractPoseProxy.js`, `poseExtractAdminServer.js` (`getAdminConfig` exported) — proxy sends `Authorization: Bearer <adminSecret>`.
- `web/admin-ui/src/lib/poseExtractExtractPoseProxy.test.mjs` (new, `node --test`).
- `docs/harness/specs/api/openapi.yaml`, `api-contract.md` — nullable `thumbnailUrl`, `INVALID_METADATA`/`POSE_MATERIALIZE_FAILED` codes, `AdminBearer` removed from `/api/me/extract-jobs*` and `GET /api/guides/{id}` security.

## Checks (Lead-verified independently, both cycles)
Cycle 1 (rejected): `npm test` → `src/extractPose.test.ts` 9/9 failing (401 instead of 400/413/429/202/200 — auth added to routes but not to the pre-existing test requests).

Cycle 2 (accepted):
```
cd web/services/pose-extract-server
npm test
 Test Files  34 passed (34)
      Tests  245 passed (245)

npm run lint   # tsc --noEmit -p tsconfig.json — clean

cd ../../admin-ui
node --test src/lib/poseExtractExtractPoseProxy.test.mjs
 tests 1, pass 1, fail 0
npm run lint   # eslint — 0 errors, 5 pre-existing warnings (unrelated <img> usage in
               # community/page.js, PhotoCard.js, PoseCard.js; not touched by this phase)

cd ../..
python3 -c "import yaml;yaml.safe_load(open('docs/harness/specs/api/openapi.yaml'))"
OPENAPI_OK
```

## Boundary/diff spot-check (Lead)
- `accountOrAdminAuth.ts`: constant-time compare via `timingSafeEqual`, correct length-guard before compare, falls through to `accountAuth` (not straight to 401) on a non-matching bearer — matches the "wrong bearer falls through to account and gets 401" requirement.
- `app.ts`: `/api/extract-pose` and `/api/extract-jobs` use the dual middleware; when no account auth is configured, `accountAuthMiddleware` is `undefined` so the dual middleware degrades to admin-bearer-only (never anonymous) — matches D5 and the non-goal against leaving submit open.
- `/api/me/extract-jobs` and `/api/guides` are mounted only under account-auth (+ `communityStore` for guides) — AdminBearer has no access there, matching D10.

## Deploy-order note (relayed, not implemented as code)
Per plan.md R2 and the worker's own handback: **admin-ui must deploy before pose-extract-server.** The admin-ui proxy patch is backward compatible (today's server ignores the extra header), so it's safe to ship first; deploying the server first would 401 admin community intake until admin-ui catches up.

## Status
Phase 3: **DONE**, verified by Lead. All Backend Phases 1-3 are now locally green together (single `npm test` run above covers Phases 1+2+3 combined). Ready for Docker-based checks and the ordered dev deploy.
