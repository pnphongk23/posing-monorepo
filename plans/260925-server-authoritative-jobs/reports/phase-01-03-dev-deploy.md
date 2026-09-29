# Dev deploy — admin-ui then pose-extract-server (Railway `ai-pose` project)

Docker gate was fully green (see phase-01-03-docker-checks.md) before any deploy action.

## Environment note
Railway project `ai-pose` (`8a60334e-9f62-44df-ac02-2f3d7eec1f7b`) has exactly one environment,
named `production` (`ce5b0dcb-4fd5-4154-aab6-2b850111ba8e`). I escalated this before deploying
(no separate "dev" environment exists); the user confirmed directly that this project/environment
is the intended dev target for this mission.

## Deploy mechanism
Neither service is on a GitHub-autodeploy branch I can safely push to, and commit/push were
explicitly unauthorized anyway. Used `railway up` (Railway CLI), which uploads local source
directly to Railway and triggers a build/deploy — no git commit or push involved, satisfies the
"no commit/push" constraint while still shipping the actual local (uncommitted) Phases 1-3 + Docker
fix code.

Uploading the true repo root failed (`IO error ... mobile/iosApp/gradle: No such file or
directory`) — a broken symlink under the sibling iOS Domain Lead's in-progress, unrelated work in
this same shared checkout. Did not touch that file (out of this slice's boundary; could destroy
someone else's in-progress work). Instead built a clean temp copy containing only the relevant
service subtree at the repo-relative path each service's Railway config expects
(`web/admin-ui/...` and `web/services/pose-extract-server/...` respectively, both `node_modules`
excluded) and ran `railway up` from there.

## 1. admin-ui — deployed first
```
railway up -y -c -p 8a60334e-9f62-44df-ac02-2f3d7eec1f7b -e ce5b0dcb-4fd5-4154-aab6-2b850111ba8e \
  -s 76c642df-196e-447b-95e1-392ee09cd31e -m "Phase 3: dual-auth admin bearer for extract-pose proxy"
```
(run from a temp dir containing only `web/admin-ui/`, matching its configured `rootDirectory`)

- Two earlier attempts failed on root-directory path mismatches (visible as `recentFailedDeployments`
  in Railway's status — harmless, service never went down, no traffic impact).
- Final deployment `99e0530a-d8a5-42ac-822c-9560d79856ac`: **SUCCESS**, build clean (Next.js 16.2.3,
  `npm run build` succeeded, all routes compiled).
- Health check: `curl https://admin-ui-production-a20c.up.railway.app/admin` → **200**.
- `environment-status`: `state: online`, `replicaStatus: {running:1, crashed:0, total:1}`,
  `issues: {critical:0, warning:0}`.

## 2. pose-extract-server — deployed second
```
railway up -y -c -p 8a60334e-9f62-44df-ac02-2f3d7eec1f7b -e ce5b0dcb-4fd5-4154-aab6-2b850111ba8e \
  -s c4350044-7a2f-4d48-9d37-f6ecb665ba29 -m "Phases 1-3: server-authoritative extraction jobs"
```
(run from a temp dir containing only `web/services/pose-extract-server/`, matching the production
`Dockerfile`'s expected repo-root-relative COPY paths)

- Build succeeded end to end: TypeScript compile, Higgsfield CLI install, Playwright Chromium +
  deps install, Python3/pip3 + `pillow`/`numpy` install (production Dockerfile already had these —
  unaffected by the Docker-gate fix, which only touched `Dockerfile.dev`), image exported and
  pushed.
- Railway's own healthcheck (`/api/health`, 30s retry window, per `railway.toml`) passed —
  "Deploy complete" reported by the CLI.
- Deployment `2bbe92fb-ddcc-4ecf-b64f-5bed73dd5f00`: **SUCCESS**, `recentFailures: 0`.
- Health check (Lead, independent): `curl https://pose-extract-server-production.up.railway.app/api/health`
  → **200** `{"status":"ok","uptime":9.204,"version":"1.0.0"}`.
- `environment-status`: `state: online`, `replicaStatus: {running:1, crashed:0, total:1}`,
  `issues: {critical:0, warning:0}`.

## Deploy order respected
admin-ui shipped first (bearer-sending proxy patch, backward compatible per plan.md R2), then
pose-extract-server (now requiring the bearer/account auth) — matches the mandatory order so admin
community intake never saw a window of 401s.

## Status
**Both services deployed and healthy.** Combined with Docker checks (245/245, lint clean, both
services) and the three independently Lead-verified phase evidence files, Backend Phases 1-3 are
fully done, verified, and now live on dev. No commit/push was made. Migrations: schema changes are
applied idempotently by the app itself on boot (`schema.sql` via `ALTER TABLE ... IF NOT EXISTS`),
confirmed via the pose-extract-server-dev container logs during the local Docker check (D-idempotency,
plan.md R4) — Railway's own boot should behave identically since it runs the same code path.
