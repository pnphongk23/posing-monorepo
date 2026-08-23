---
work_item: 4
title: Add FEAT-009 admin provider toggle (invoked via Admin Web)
status: completed
priority: P2
effort: M
dependencies:
  - 3
decision_dependencies: []
---

# Work Item 4: Add FEAT-009 admin provider toggle (invoked via Admin Web)

**Kind:** story

**Feature ownership:** This Work Item implements the **[FEAT-009](../../features/FEAT-009-configure-extraction-provider.md)**
admin provider-toggle surface. **[FEAT-007](../../features/FEAT-007-operate-pose-content-from-admin-web.md)**
Admin Web **invokes** FEAT-009 (proxy routes + UI host); FEAT-007 does **not**
own provider configuration or selection policy (see
[DEC-001](../../decisions/DEC-001-extraction-provider-selection-policy.md)).

## Tasks

- Add Express admin routes:
  - `GET /api/admin/settings/extraction-provider`
  - `PUT /api/admin/settings/extraction-provider` with body `{ provider }`
  validated to `gemini_native` | `higgsfield_cli`.
- Wire routes in `app.ts` with existing admin auth + rate limit middleware.
- Add Next.js proxy routes under `web/admin-ui/src/app/api/admin/settings/`
  using `poseExtractAdminServer.js` (FEAT-007 invocation surface).
- Add provider toggle UI to Admin (extend Keys page or minimal Settings panel):
  radio/select between Gemini Native and Higgsfield CLI; no credential upload.
  UI is the FEAT-009 configuration control hosted in Admin Web.
- Show current provider on load; display save confirmation and upstream errors.
- Document that toggle affects **next** worker-claimed jobs only (DEC-001 B1).

## Scope and affected files

- `web/services/pose-extract-server/src/routes/adminSettingsRoutes.ts` (new)
- `web/services/pose-extract-server/src/db/providerSettingsStore.ts`
- `web/services/pose-extract-server/src/app.ts`
- `web/admin-ui/src/app/api/admin/settings/extraction-provider/route.js` (new)
- `web/admin-ui/src/app/admin/keys/page.js` (or new `settings/page.js`)
- `web/admin-ui/src/lib/poseExtractAdminServer.js` (no secret exposure changes)

## Success criteria

- Operator can read and set extraction provider via Admin UI (FEAT-009 FR-001/002).
- No UI for Higgsfield credential upload or CLI login.
- Invalid provider value returns `400` with structured error (FEAT-009 FR-004).
- Toggle persists in SQLite across API/worker restarts (FEAT-009 FR-003).
- Proxy never exposes `POSE_EXTRACT_ADMIN_SECRET` to browser (FEAT-007 proxy model).
- Behavior aligns with DEC-001 axes B1, C1, D2.

## Risks

- Placing toggle on Keys page may confuse operators; label clearly as "Extract engine".
- Mid-flight jobs may complete on previous provider; UI must not imply instant switch.
- Missing proxy route breaks Admin in production-only configs.
- Documenting toggle requirements under FEAT-007 would contradict FEAT-009 ownership.

## Required evidence

- Screenshot or recording of toggle save + reload showing persisted value.
- `npm run backend:test` — admin settings route tests.
- `npm run build` — admin-ui compiles.
- curl/httpx: `PUT` with Bearer admin → `GET` returns same provider.
