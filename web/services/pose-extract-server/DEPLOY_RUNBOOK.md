# pose-extract-server — Production Deploy Runbook

**Scope:** Fix the production crash loop + edge 502 symptom without changing API/worker scope.
**Root cause:** `DATABASE_URL` points at the Supabase **transaction-mode pooler (port 6543)**. The shared `postgres` client defaulted to `prepare: true`, so prepared statements failed with `PostgresError 26000` after a pooler session reset. The worker poll loop had no iteration-level error containment, so a transient `claimNext`/requeue error escaped to `run().catch → process.exit(1)`; with `wait -n` the whole container (API + worker) restarted, surfacing as a crash loop and edge 502s.

**Fix (this deploy):**
1. `src/db/connection.ts` — `createDatabase(url)` now passes `{ prepare: false }` (single shared factory; covers API and worker).
2. `src/worker/worker-loop.ts` — the poll loop (`runWorkerLoop`) wraps each iteration in `try/catch` with bounded exponential backoff (1s → 30s cap). A transient poll/DB error (claimNext, provider lookup, or requeue) can no longer crash the worker through the 26000 path. SIGINT/SIGTERM graceful shutdown is preserved via the `isShuttingDown` predicate.
3. `Dockerfile` **unchanged** — `wait -n` is the chosen minimal reversible decision (per frozen plan).

**Secrets:** Never print, embed, or report secret values. `DATABASE_URL`, `ADMIN_SECRET`, `R2_*` and Higgsfield credentials are referenced **by name only** below. Do not add their values to this file or to logs.

**Deployable workspace rule:** An uncommitted or unpushed workspace is **NOT deployable**. See the Provenance Gate (section 0). Railway builds from its configured source; only a pushed commit can become an active deployment.

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

The fix must be committed **and** available in Railway's configured source (pushed) before deploying. Record the exact fix commit and confirm a clean tree:

```bash
# 1. Record the exact fix commit and branch.
git rev-parse HEAD            # -> record this as the FIX_COMMIT (e.g. abc123...)
git rev-parse --abbrev-ref HEAD

# 2. Confirm the working tree is clean (no uncommitted changes).
git status --short            # MUST be empty for the deployable scope.
git log -1 --oneline          # sanity check the recorded commit.

# 3. Ensure the commit is pushed to the branch Railway builds from.
git push origin "$(git rev-parse --abbrev-ref HEAD)"
```

- If `git status --short` is non-empty for in-scope files, **do not deploy** — commit and push first.
- Keep `FIX_COMMIT` handy; you will verify it matches the active deployment in section 3e.

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

> **Terminology — `redeploy` is NOT `rollback`.** `railway redeploy` re-deploys the **latest configured deployment** (with `--from-source` it builds the latest commit/image from the configured source). It does **not** select a previous deployment. Rolling back to a prior deployment is a separate action documented in section 4.

Run from `web/services/pose-extract-server` (after passing the Provenance Gate):

```bash
# Build & deploy the FIX_COMMIT (latest source) as a fresh deployment.
railway redeploy \
  --project 8a60334e-9f62-44df-ac02-2f3d7eec1f7b \
  --environment production \
  --service c4350044-7a2f-4d48-9d37-f6ecb665ba29 \
  --from-source \
  --yes
```

> The exact deploy trigger depends on the project's configured source (Railway repo build vs. image). If your pipeline deploys via git push/webhook instead, push `FIX_COMMIT` (section 0) and confirm a new deployment spins up. Either way, the source must contain the committed fix.

**This runbook documents the operator deploy steps. The fix itself must NOT be deployed by the implementer (production deploy is out of scope for this packet).**

---

## 3. Post-deploy checks (production)

Wait for the new deployment to reach a `SUCCESS` state, then verify:

### 3a. No worker crash loop

```bash
railway logs --service c4350044-7a2f-4d48-9d37-f6ecb665ba29 --tail 500 \
  | grep -i "worker crashed"
# EXPECTED: no output (grep exits non-zero / no lines)
```

### 3b. API health returns HTTP 200

```bash
# Replace <PUBLIC_HOST> with the service's production host (do not print secrets).
curl -i https://<PUBLIC_HOST>/api/health
# EXPECTED: HTTP/1.1 200 OK  (body: {"status":"ok", ...})
```

### 3c. GET /api/community/poses reaches Express

```bash
curl -i https://<PUBLIC_HOST>/api/community/poses
# EXPECTED: HTTP/1.1 200 OK and a JSON array body (route handled by Express,
# not a 502/504 from an upstream or crashed worker).
```

### 3d. Positive watch (prolonged)

Monitor `railway logs` for ~10–15 minutes and confirm **all** of:
- **No** `worker crashed` lines.
- **No** Postgres error code `26000` (prepared-statement rejection after pooler reset).
- **No sustained/repeated** `worker poll iteration failed; backing off before retry` (occasional transient blips are expected and must NOT crash the worker; the `consecutiveErrors` field should not climb unboundedly).
- `/api/health` stays 200 and `/api/community/poses` keeps returning 200.

### 3e. Confirm the active deployment matches the committed fix

```bash
railway deployment list --service c4350044-7a2f-4d48-9d37-f6ecb665ba29 \
  --project 8a60334e-9f62-44df-ac02-2f3d7eec1f7b --environment production --limit 5 --json
```

Verify the **active** deployment's source revision equals `FIX_COMMIT` from section 0. If they differ, the deploy did not pick up the committed fix — do not trust the result; redeploy `--from-source` again or stop and reassess.

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
