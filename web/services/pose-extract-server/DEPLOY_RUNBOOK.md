# pose-extract-server — Production Deploy Runbook

**Scope:** Fix the production crash loop + edge 502 symptom without changing API/worker scope.
**Root cause:** `DATABASE_URL` points at the Supabase **transaction-mode pooler (port 6543)**. The shared `postgres` client defaulted to `prepare: true`, so prepared statements failed with `PostgresError 26000` after a pooler session reset. The worker poll loop had no iteration-level error containment, so a transient `claimNext`/requeue error escaped to `run().catch → process.exit(1)`; with `wait -n` the whole container (API + worker) restarted, surfacing as a crash loop and edge 502s.

**Fix (this deploy):**
1. `src/db/connection.ts` — `createDatabase(url)` now passes `{ prepare: false }` (single shared factory; covers API and worker).
2. `src/worker/worker-loop.ts` — the poll loop (`runWorkerLoop`) wraps each iteration in `try/catch` with bounded exponential backoff (1s → 30s cap). A transient poll/DB error (claimNext, provider lookup, or requeue) can no longer crash the worker through the 26000 path. SIGINT/SIGTERM graceful shutdown is preserved via the `isShuttingDown` predicate.
3. `Dockerfile` **unchanged** — `wait -n` is the chosen minimal reversible decision (per frozen plan).

**Secrets:** Never print, embed, or report secret values. `DATABASE_URL`, `ADMIN_SECRET`, `R2_*` and Higgsfield credentials are referenced **by name only** below. Do not add their values to this file or to logs.

**Deployable workspace rule:** Deploy only from a clean, committed workspace. This service is currently deployed from a CLI-uploaded source snapshot (`source.repo` and `source.image` are unset), so the canonical code deploy is `railway up` from the repository root. A `railway redeploy --from-source` build log is not sufficient evidence that the current local source became the active image.

---

## Target (frozen)

| Field | Value |
| --- | --- |
| Project | `8a60334e-9f62-44df-ac02-2f3d7eec1f7b` |
| Service | `c4350044-7a2f-4d48-9d37-f6ecb665ba29` |
| Environment | `production` |

All Railway commands below use these exact identifiers.

---

## 0. Provenance Gate (REQUIRED before any deploy)

The fix must be committed before deploying. Because this service uses a CLI-uploaded snapshot, the deploy command—not a Railway Git source—selects the workspace. Record the exact fix commit and confirm the files used by the build are clean:

```bash
# 1. Record the exact fix commit and branch.
git rev-parse HEAD            # -> record this as the FIX_COMMIT (e.g. abc123...)
git rev-parse --abbrev-ref HEAD

# 2. Confirm the deployable files are clean (no uncommitted changes).
git status --short -- railway.toml web/services/pose-extract-server
# MUST be empty. Unrelated workspace changes may remain outside this scope.
git log -1 --oneline          # sanity check the recorded commit.

# 3. Push for repository/audit consistency when required by team policy.
#    This is not the deploy trigger for this CLI-uploaded service.
git push origin "$(git rev-parse --abbrev-ref HEAD)"
```

- If `git status --short` is non-empty for in-scope files, **do not deploy** — commit and push first.
- Keep `FIX_COMMIT` handy; you will associate it with the uploaded snapshot, deployment ID, build log, image digest, and live compiled artifact in section 3.

---

## 1. Link / read-only inspection

> **`railway link` is STATEFUL, not read-only.** It writes a local project/service association (the `.railway` link in the working directory). Run it once to set local context; it changes local state. Read-only inspection uses the explicit `--project`/`--service` flags below, which do not mutate remote state.

```bash
# Stateful local-context association (run once; writes .railway link).
railway link \
  --project 8a60334e-9f62-44df-ac02-2f3d7eec1f7b \
  --environment production \
  --service c4350044-7a2f-4d48-9d37-f6ecb665ba29

# READ-ONLY inspection (explicit IDs; no remote mutation):
railway status  --project 8a60334e-9f62-44df-ac02-2f3d7eec1f7b --environment production
railway logs   --service c4350044-7a2f-4d48-9d37-f6ecb665ba29 --tail 200
railway deployment list --service c4350044-7a2f-4d48-9d37-f6ecb665ba29 \
  --project 8a60334e-9f62-44df-ac02-2f3d7eec1f7b --environment production --limit 10
```

Verify current logs show the crash-loop signature before deploy (for before/after comparison):
`worker crashed` and/or `PostgresError: 26000`.

---

## 2. Deploy (apply the fix)

> **Canonical workflow for this service:** `railway up` uploads the current source snapshot. Do not use `railway redeploy --from-source` for this service: the previous incident showed that it can produce fresh-looking build output while the active instance still serves an older image. `railway redeploy` and `rollback` are also different operations; rollback to a prior deployment is documented in section 4.

Run from the repository root—the directory containing `railway.toml`—after passing the Provenance Gate:

```bash
# Upload and deploy the current FIX_COMMIT source snapshot as a fresh deployment.
railway up \
  --project 8a60334e-9f62-44df-ac02-2f3d7eec1f7b \
  --environment production \
  --service c4350044-7a2f-4d48-9d37-f6ecb665ba29 \
  --detach \
  --yes \
  --json \
  --message "deploy ${FIX_COMMIT}: pose-extract-server"
```

Record the returned `deploymentId` as `DEPLOYMENT_ID`. Capture the currently active image digest before deploying when available; the new deployment must report a new digest and become the active running deployment.

**This runbook documents the operator deploy steps. The fix itself must NOT be deployed by the implementer (production deploy is out of scope for this packet).**

---

## 3. Post-deploy checks (production)

Wait for the new deployment to reach a `SUCCESS` state, then verify:

### 3a. Build logs

Inspect the build log for the exact deployment:

```bash
railway logs "$DEPLOYMENT_ID" --build --lines 250 --json
```

Require the expected Dockerfile steps (`COPY src`, `RUN npm run build`, and `COPY --from=build /app/dist ./dist`) and no build error. A build log alone does not prove that the active instance uses that image.

### 3b. Active image and compiled artifact

Confirm that `DEPLOYMENT_ID` is active, successful, and running:

```bash
railway status \
  --project 8a60334e-9f62-44df-ac02-2f3d7eec1f7b \
  --environment production \
  --service c4350044-7a2f-4d48-9d37-f6ecb665ba29 \
  --json
```

Record the active instance ID as `INSTANCE_ID`, then verify the compiled files inside that instance:

```bash
railway ssh \
  --project 8a60334e-9f62-44df-ac02-2f3d7eec1f7b \
  --environment production \
  --service c4350044-7a2f-4d48-9d37-f6ecb665ba29 \
  --deployment-instance "$INSTANCE_ID" \
  -- sh -lc 'test -f /app/dist/worker/worker-loop.js && grep -q "prepare: false" /app/dist/db/connection.js && grep -q "runWorkerLoop" /app/dist/worker/worker-main.js'
```

The SSH check must pass for the compiled worker loop, `prepare: false`, and the worker entrypoint. The active image digest must match the new deployment and differ from the pre-deploy digest when one was captured.

### 3c. No worker crash loop

```bash
railway logs "$DEPLOYMENT_ID" --tail 500 \
  | grep -i "worker crashed"
# EXPECTED: no output (grep exits non-zero / no lines)
```

### 3d. API health returns HTTP 200

```bash
# Replace <PUBLIC_HOST> with the service's production host (do not print secrets).
curl -i https://<PUBLIC_HOST>/api/health
# EXPECTED: HTTP/1.1 200 OK  (body: {"status":"ok", ...})
```

### 3e. GET /api/community/poses reaches Express

```bash
curl -i https://<PUBLIC_HOST>/api/community/poses
# EXPECTED: HTTP/1.1 200 OK and a JSON array body (route handled by Express,
# not a 502/504 from an upstream or crashed worker).
```

### 3f. Positive watch (prolonged)

Monitor the logs for `DEPLOYMENT_ID` for ~10–15 minutes and confirm **all** of:
- **No** `worker crashed` lines.
- **No** Postgres error code `26000` (prepared-statement rejection after pooler reset).
- **No sustained/repeated** `worker poll iteration failed; backing off before retry` (occasional transient blips are expected and must NOT crash the worker; the `consecutiveErrors` field should not climb unboundedly).
- `/api/health` stays 200 and `/api/community/poses` keeps returning 200.

### 3g. Confirm deployment provenance

```bash
railway deployment list --service c4350044-7a2f-4d48-9d37-f6ecb665ba29 \
  --project 8a60334e-9f62-44df-ac02-2f3d7eec1f7b --environment production --limit 5 --json
```

For a CLI-uploaded service, deployment metadata may not expose a source revision. Require all of the following before declaring success:

- the deploy was launched from the clean workspace whose `FIX_COMMIT` was recorded in section 0;
- the build log belongs to `DEPLOYMENT_ID` and contains the expected compile/copy steps;
- the active deployment is `DEPLOYMENT_ID`, successful, and running;
- the new image digest differs from the pre-deploy digest when one was captured;
- the compiled-artifact SSH check, health check, API smoke test, and bounded runtime-log check all pass.

Do not use an absent or stale source-revision field as the sole verification signal.

---

## 4. Rollback (recover to a VERIFIED healthy deployment)

**Distinction (keep):** `railway redeploy` (section 2) re-deploys the latest configured deployment. **Rollback** means selecting a *prior* deployment from history and making it active again. There is **no** `railway rollback` CLI command, so use the dashboard deployment history. Never use `railway redeploy` to mean rollback.

### Historical diagnostic context ONLY — do NOT use as a target

- Deployment **`1a3733fd`** is the **known-bad crash-loop baseline** (it reproduces the original PostgresError `26000` / `worker crashed` loop). It is recorded here **solely as diagnostic context** for root-cause comparison. **It is never a recovery target or rollback instruction.** Do not select it during rollback.

### Actionable rollback procedure

Roll back to a deployment that was **verified healthy** before this change. You need its exact deployment ID, recorded from a prior successful production run (e.g., from `railway deployment list --json` when the service was healthy). Substitute that exact ID as `VERIFIED_HEALTHY_DEPLOYMENT_ID` below.

1. Open the **pose-extract-server** service in [Railway](https://railway.com) (project `8a60334e-9f62-44df-ac02-2f3d7eec1f7b`, environment `production`).
2. **Deployments** → **Deployment History**.
3. Locate the deployment with exact ID **`VERIFIED_HEALTHY_DEPLOYMENT_ID`** — it must match a prior verified-healthy deployment, **not** `1a3733fd`.
4. Open it → **Redeploy** / **Rollback to this deployment**. This makes it the active deployment.
5. Confirm it is active and healthy:

```bash
# Active deployment must be the verified-healthy ID (not 1a3733fd).
railway deployment list \
  --service c4350044-7a2f-4d48-9d37-f6ecb665ba29 \
  --project 8a60334e-9f62-44df-ac02-2f3d7eec1f7b \
  --environment production --limit 5 --json

# Status must be SUCCESS and source revision must match the recorded healthy commit.
railway status --project 8a60334e-9f62-44df-ac02-2f3d7eec1f7b --environment production
```

6. Verify endpoints (substitute `<PUBLIC_HOST>`; never print secrets):
   - `curl -i https://<PUBLIC_HOST>/api/health` → 200
   - `curl -i https://<PUBLIC_HOST>/api/community/poses` → 200
   - `railway logs --service c4350044-7a2f-4d48-9d37-f6ecb665ba29 --tail 200` → no `worker crashed`, no `26000`.

### If no verified healthy deployment exists

If you cannot identify an exact `VERIFIED_HEALTHY_DEPLOYMENT_ID` from a prior known-good production run, **stop** — do not guess or select an unverified deployment (including `1a3733fd`). Escalate to Tướng quân (lead) via `BLOCKED_NEEDS_LEAD` and invoke the fallback below.

### Corrective path if A + C is insufficient (fallback B)

If `prepare:false` **plus** loop-level resilience (A + C) does not stop the crash loop, the frozen fallback is **B**: switch the production `DATABASE_URL` to the Supabase **session pooler / direct DB** (not the transaction-mode port 6543). This is a corrective, lead-approved change — escalate via `BLOCKED_NEEDS_LEAD` before altering production variables. Do **not** perform B unilaterally.

---

## 5. Notes / out-of-scope

- **Not changed:** `Dockerfile` `wait -n` coupling, mobile/iOS files, schema/data migrations, domain/URLs, and any files outside `pose-extract-server`.
- **Out of scope for this fix:** a worker supervisor / separate Railway service (explicitly deferred per frozen plan; escalate if evidence later shows `wait -n` is unsafe).
- **Fallback only (not in this deploy):** switching the production `DATABASE_URL` to the Supabase session pooler / direct DB — only if `prepare:false` + loop containment is insufficient, and only with lead approval.

## Related

- Source fix: `src/db/connection.ts` (`prepare: false`), `src/worker/worker-loop.ts` (bounded retry loop), `src/worker/worker-main.ts` (wires loop + SIGINT/SIGTERM shutdown).
- Regression tests: `src/db/connection.test.ts` (`prepare: false`), `src/worker/worker-loop.test.ts` (containment/backoff/reset/shutdown predicate, log sanitization).
- Auth/volume ops: `docs/s1-auth-runbook.md` (same combined API+worker container, `wait -n` CMD unchanged).
