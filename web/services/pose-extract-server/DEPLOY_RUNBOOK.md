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
git status --short -- railway.toml package.json package-lock.json web/services/pose-extract-server
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

**Distinction (keep):** `railway up` (section 2) uploads the current source snapshot and creates a fresh deployment. `railway redeploy` is for the latest configured repository/image source. **Rollback** means selecting a *prior* deployment from history and making it active again. There is **no** `railway rollback` CLI command, so use the dashboard deployment history. Never use `railway redeploy` to mean rollback.

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

# Status must be SUCCESS and the active deployment must be the recorded healthy target.
# For CLI-uploaded deployments, source-revision metadata may be unavailable; use
# the deployment ID/image and the same health/artifact checks as section 3.
railway status --project 8a60334e-9f62-44df-ac02-2f3d7eec1f7b --environment production
```

6. Verify endpoints (substitute `<PUBLIC_HOST>`; never print secrets):
   - `curl -i https://<PUBLIC_HOST>/api/health` → 200
   - `curl -i https://<PUBLIC_HOST>/api/community/poses` → 200
   - `railway logs VERIFIED_HEALTHY_DEPLOYMENT_ID --tail 200` → no `worker crashed`, no `26000`.

### If no verified healthy deployment exists

If you cannot identify an exact `VERIFIED_HEALTHY_DEPLOYMENT_ID` from a prior known-good production run, **stop** — do not guess or select an unverified deployment (including `1a3733fd`). Escalate to Tướng quân (lead) via `BLOCKED_NEEDS_LEAD` and invoke the fallback below.

### Corrective path if A + C is insufficient (fallback B)

If `prepare:false` **plus** loop-level resilience (A + C) does not stop the crash loop, the frozen fallback is **B**: switch the production `DATABASE_URL` to the Supabase **session pooler / direct DB** (not the transaction-mode port 6543). This is a corrective, lead-approved change — escalate via `BLOCKED_NEEDS_LEAD` before altering production variables. Do **not** perform B unilaterally.

---

## 5. Notes / out-of-scope

- **Not changed:** `Dockerfile` `wait -n` coupling, mobile/iOS files, schema/data migrations, domain/URLs, and any files outside `pose-extract-server`.
- **Local Docker unavailable:** this is a local verification limitation, not a production deploy blocker. `railway up` uploads the source snapshot and Railway builds the Docker image remotely; a local `docker build` is optional for this workflow.
- **Out of scope for this fix:** a worker supervisor / separate Railway service (explicitly deferred per frozen plan; escalate if evidence later shows `wait -n` is unsafe).
- **Fallback only (not in this deploy):** switching the production `DATABASE_URL` to the Supabase session pooler / direct DB — only if `prepare:false` + loop containment is insufficient, and only with lead approval.

## 6. Account deletion + Sign in with Apple prerequisites

**Status: REQUIRED BEFORE DEPLOY — CURRENTLY UNPROVISIONED.** Every item below is unverified or absent as of 260918. Deploying the current source without them does **not** break the service: the new code fails closed. But it also does not deliver the feature, so do not report account deletion or Apple sign-in as working until each item is confirmed.

### 6a. `SUPABASE_SERVICE_ROLE_KEY` (server-only)

Required by `DELETE /api/account`, which removes the Supabase Auth user through the Admin REST API (`DELETE {SUPABASE_URL}/auth/v1/admin/users/{id}`) before purging application data.

| Field | Value |
| --- | --- |
| Where | Railway service variable (`c4350044-7a2f-4d48-9d37-f6ecb665ba29`, environment `production`) **and** the operator's local `web/services/pose-extract-server/.env` |
| Value | The Supabase **service_role** key for project `jqvqsxzcbstscvkhizkw`. Never the anon key. |
| Absent today? | Yes. `.env.example` documents the variable; the local `.env` and the Railway service do not yet set it. |

Rules:

- Server-only. Never ship it to a client, never add it to an `.env` file that is committed, never log it, never echo it in a response or a query string.
- Optional by design so a misconfigured deploy still boots. When it is absent, `DELETE /api/account` answers `503 {"error":{"code":"AUTH_PENDING_VALIDATION","message":"Account deletion is pending runtime validation"}}` and the middleware in front of the route still answers `401` to an unauthenticated caller. That 503 is the intended safety property, not a bug — treat a live 503 as "key not provisioned yet".

### 6b. Supabase Auth — Apple provider

The backend exchanges the Apple identity token through `POST {SUPABASE_URL}/auth/v1/token?grant_type=id_token` using the existing **anon** key. For that grant to accept our tokens, the Supabase project must have the Apple provider enabled with our bundle identifier as an Authorized Client ID.

| Field | Value |
| --- | --- |
| Provider | Apple, enabled for project `jqvqsxzcbstscvkhizkw` |
| Authorized Client ID | `posing.camera.app` (the iOS `PRODUCT_BUNDLE_IDENTIFIER` in `mobile/iosApp/project.yml`) |
| Absent today? | Yes — not configured, and not verifiable from this repository. |

The `id_token` grant is marked **experimental** in the Supabase Auth OpenAPI. The nonce contract is the known trap: Apple signs the **SHA-256 hex** of the nonce into the identity token while Supabase expects the **raw** nonce. The client sends the hex form to Apple and the raw form to us; the server forwards the raw value unmodified. Sending the hashed form produces a `Nonces mismatch` rejection (supabase/auth issue #2378).

### 6c. Apple Developer / App Store Connect

| Field | Value |
| --- | --- |
| Entitlement | `com.apple.developer.applesignin` = `Default` — file `mobile/iosApp/iosApp/iosApp.entitlements`, wired via `CODE_SIGN_ENTITLEMENTS` in `project.yml` |
| Capability | Sign in with Apple must be enabled on the App ID for `posing.camera.app` |
| Team | `878758XF68` (automatic signing) |
| Absent today? | The entitlement file and build wiring exist and build locally. The **provisioning** (App ID capability + profile) is an operator/portal action and is unverified. |

A local `xcodebuild` pass proves the seam compiles and the unit tests hold; it does **not** prove the live handshake or the live Supabase exchange. Those stay unverified until 6b and 6c are provisioned and a real device/sandbox Apple ID completes a sign-in.

### 6d. Post-deploy verification (run only after 6a-6c)

Substitute `<PUBLIC_HOST>`; never print secrets.

```bash
# 1. Route is mounted and the auth boundary holds: MUST be 401, not 404 and not 503.
curl -i -X DELETE https://<PUBLIC_HOST>/api/account

# 2. With a real signed-in access token and no service-role key: MUST be 503 AUTH_PENDING_VALIDATION.
#    After 6a is provisioned the same call MUST be 204 with an empty body.
curl -i -X DELETE https://<PUBLIC_HOST>/api/account -H "Authorization: Bearer <ACCESS_TOKEN>"

# 3. Apple exchange: a POST with a real identity token MUST return 200 with
#    { accessToken, refreshToken, account } — the same body shape as /api/auth/email/signin.
```

Expected statuses are asserted by `src/routes/accountRoutes.test.ts` and `src/routes/accountAuthRoutes.test.ts`; the curl calls above confirm the deployment, not the code.

### 6e. Deletion completeness — orphan rows and the object-deletion outbox

`DELETE /api/account` deletes the Supabase user first, then every row the account owns in one database
transaction, then its R2 objects. Two tables make the tail of that work observable and resumable:

- `pending_account_purges(account_id, requested_at)` — written **only after** Supabase confirmed the
  user is gone (a `404` counts as gone). A row older than 5 minutes means the request died between the
  identity delete and the row purge. The server sweep resumes it every 10 minutes and deletes the row
  when the purge commits. A cancelled or rejected Apple/Supabase step never writes this row.
- `pending_object_deletions(key, enqueued_at, attempts, claimed_until, last_error)` — object keys that
  still have to be removed. Success and a 404 from R2 delete the row; any other failure increments
  `attempts`, stores `last_error`, and leaves the key for the next sweep. Claims are time-boxed to 5
  minutes, so a replica that dies mid-drain cannot strand a key.

Read-only inspection:

```sql
SELECT account_id, requested_at, NOW() - requested_at AS age
FROM pending_account_purges
ORDER BY requested_at;

SELECT key, attempts, last_error, enqueued_at, claimed_until
FROM pending_object_deletions
ORDER BY enqueued_at
LIMIT 50;

-- What is left for one account (replace :account with the account uuid).
SELECT 'poses' AS table_name, COUNT(*)::int AS rows FROM poses WHERE owner_account_id = :'account'
UNION ALL SELECT 'saved_entries', COUNT(*)::int FROM saved_entries WHERE account_id = :'account'
UNION ALL SELECT 'extraction_jobs', COUNT(*)::int FROM extraction_jobs WHERE owner_account_id = :'account'
UNION ALL SELECT 'accounts', COUNT(*)::int FROM accounts WHERE id = :'account';
```

Resuming a stuck purge:

1. Preferred: the user signs in again and re-issues `DELETE /api/account` while the access token is
   still valid (≤ 1 h after issue). The Supabase delete then answers `404`, which counts as success.
2. If the user cannot sign in, queue the intent by hand **only when the Supabase user is confirmed
   gone** and wait one sweep (≤ 10 minutes), then confirm the intent row and the account's rows are
   gone:

```sql
INSERT INTO pending_account_purges (account_id, requested_at)
VALUES (:'account', NOW() - interval '6 minutes')
ON CONFLICT (account_id) DO UPDATE SET requested_at = EXCLUDED.requested_at;
```

> Never insert an intent for a live user, and never delete rows by hand while a purge runs: the sweep
> would then purge an account that still exists upstream. `security definer` helpers are not needed —
> the tables are plain and only the API and the sweep touch them.

Deletion leaves an account-id-only tombstone (`deleted_accounts`, no personal data) in the same
transaction as the purge. Sign-in takes the same per-account advisory lock as the purge and reads the
tombstone first, so a client that still holds valid tokens cannot recreate a deleted account: the
sign-in fails and its uploads answer `410`. Restoring an account on purpose therefore means deleting
its tombstone row **and** letting the user sign in again — never do that without a support decision.

Every owner job attempt writes one row to `pose_media_manifests` **before its first upload**, naming
the three object keys it may write. That row is the attempt's only hold, and exactly one consumer removes
it, atomically, with its keys moving to deletion tickets when the attempt is abandoned:

| Consumer | When | Outcome |
| --- | --- | --- |
| Finalize transaction | the pose is created | pose + media assets own the objects, manifest row deleted in the same commit |
| Worker failure path | any error after the manifest exists | keys become `pending_object_deletions` rows with `not_before = max(now, created_at + 1 h)` |
| Stale sweep (every 10 min) | manifest older than 1 h | same tickets; catches crashed workers and a failed `abandon` |
| Account purge | inside the purge transaction | same tickets, in the same commit as the row deletion and tombstone |

Guarantees (each is a single atomic statement, not a clock race):

- **A key is always covered by exactly one record:** a manifest row, a `media_assets` row, or a deletion
  ticket. Nothing is ever "re-recorded" and no renewal exists.
- **Finalize requires its manifest.** The transaction locks the job row first (same order as the purge),
  then deletes the manifest row and requires exactly one row to be gone. If the attempt was already
  consumed or swept, the transaction rolls back: no pose, job requeued with `POSE_MATERIALIZE_FAILED`.
- **A ticket waits for the upload horizon.** No ticket derived from a manifest is drained before
  `max(now, manifest.created_at + 1 h)`, and a put may not *start* later than 5 min after its manifest was
  written (per-put timeout 2 min). So an in-flight upload cannot land after its delete.
- **No inline deletes in the worker.** Deletion only happens through tickets, which is what makes a lost
  COMMIT acknowledgement safe: the pose and its manifest consumption are committed together, so the
  worker's late `abandon` affects 0 rows and never deletes a live pose's objects.
- **The failure path never depends on logs.** If `abandon` itself fails, the manifest row is still in the
  database and the stale sweep moves it after the horizon.

What an operator may see after a failed attempt: the job requeued (or failed after 3 attempts) with
`POSE_MATERIALIZE_FAILED`, no pose, and up to three tickets that drain after the horizon. A manifest row
older than 2 h means the sweep is not running: check the API process, not the worker. Old manifests are
also the only way to recover the keys of an attempt whose worker died.

Inspection (never copy `object_keys` into tickets, logs, or chat):
```sql
SELECT pose_id, job_id, cardinality(object_keys) AS keys, NOW() - created_at AS age
FROM pose_media_manifests ORDER BY created_at LIMIT 50;
SELECT COUNT(*) FROM pending_object_deletions WHERE not_before > NOW();  -- waiting for their horizon
SELECT COUNT(*) FROM pending_object_deletions WHERE attempts >= 3;       -- storage keeps refusing
```
Alerts: a manifest older than 2 h (sweep not running) and tickets with `attempts >= 3` (storage refusing
deletes).

**Deploy this as one release.** Never run a pre-manifest build (`59f27fa..192cac9`, the lease-based
drainer) against the same database as this build: that drainer ignores `not_before`, so it would delete
objects whose upload horizon has not passed yet. A drain whose claim expired can overlap a later drain on the same ticket, so object deletion
must stay idempotent: R2 is S3-compatible and answers a missing-key delete with success, and the drain
also treats a 404 as an acknowledgement.

Logs: a failed row purge logs `account_purge_failed` with the account id only, and cleanup failures log
counts, never object keys (a key is a capability to a reusable file). A stale object key logs
nothing until the sweep retries it; alert on `pending_object_deletions.attempts >= 3` or an intent older
than 1 hour.

---

## 7. Subscription entitlements (RevenueCat)

**Status: OPTIONAL BY DESIGN — unprovisioned is safe.** Three variables gate the feature; with any
required one missing the read/reconcile routes answer `503 ENTITLEMENT_UNAVAILABLE` and the webhook
is not mounted at all (the path is `404`). Nothing else in the service changes, so deploying before
the values exist cannot break login, extraction or saved poses.

| Variable | Where | What it is for |
| --- | --- | --- |
| `REVENUECAT_SECRET_API_KEY` | Railway service variables **and** the operator's local `.env` | Server-side REST v1 read of a subscriber. Never the public SDK key. |
| `REVENUECAT_ENTITLEMENT_ID` | Railway service variables **and** the operator's local `.env` | The entitlement id that is live in the RevenueCat dashboard. |
| `REVENUECAT_WEBHOOK_AUTH` | Railway service variables | Bearer token RevenueCat sends; the service compares it with `timingSafeEqual`. At least 32 characters. |

Rules: names only in this file — never the values, never in a response, never in a log line.
`.env.example` lists the names with no values. The REST read happens on every write, so the webhook
body is only a trigger: no state is ever taken from the payload.

### 7a. Dashboard webhook setup

1. RevenueCat → **Project settings → Integrations → Webhooks** → add
   `https://<PUBLIC_HOST>/api/webhooks/revenuecat`.
2. Authorization header value: `Bearer ` followed by `REVENUECAT_WEBHOOK_AUTH` (the exact string, including
   the `Bearer ` prefix; the service compares the whole header).
3. Enable at least `INITIAL_PURCHASE`, `RENEWAL`, `EXPIRATION`, `BILLING_ISSUE`, `CANCELLATION`,
   `UNCANCELLATION`, `PRODUCT_CHANGE`, `SUBSCRIPTION_EXTENDED`, `TRANSFER`, `TEMPORARY_ENTITLEMENT_GRANT`.
   Unsupported event types are acknowledged with `200 {"ignored": true}` rather than retried.
4. Leave **sandbox** events on: App Review buys in sandbox against the production server and those
   events must be processed.

### 7b. Post-provision verification (never print secrets)

```bash
# 1. Webhook is mounted but unauthenticated: MUST be 401, not 404 and not 500.
curl -i -X POST https://<PUBLIC_HOST>/api/webhooks/revenuecat -H 'Content-Type: application/json' -d '{}'

# 2. Entitlement read for a signed-in account: 200 with { data: { isActive, stale } },
#    or 503 ENTITLEMENT_UNAVAILABLE while the two read variables are still unset.
curl -i https://<PUBLIC_HOST>/api/me/entitlement -H "Authorization: Bearer <ACCESS_TOKEN>"

# 3. Reconcile after a sandbox purchase; repeat within a minute to see 429 after the tenth call.
curl -i -X POST https://<PUBLIC_HOST>/api/me/entitlement/sync -H "Authorization: Bearer <ACCESS_TOKEN>"
```

Read-only inspection (account id only; the table holds no personal data):

```sql
SELECT account_id, entitlement_id, is_active, expires_at, environment, upstream_at, synced_at, NOW() - synced_at AS age
FROM account_entitlements ORDER BY synced_at DESC LIMIT 50;
```

Alerts: `environment = 'SANDBOX'` rows on a production database are expected for App Review, but a
production purchase that stays `is_active = false` with a fresh `synced_at` means the dashboard
entitlement id and `REVENUECAT_ENTITLEMENT_ID` disagree. Account deletion removes the row through
`ON DELETE CASCADE`; no entitlement-specific cleanup exists or is needed.

---

## Related

- Account deletion / Apple sign-in prerequisites: section 6 above.
- Source fix: `src/db/connection.ts` (`prepare: false`), `src/worker/worker-loop.ts` (bounded retry loop), `src/worker/worker-main.ts` (wires loop + SIGINT/SIGTERM shutdown).
- Regression tests: `src/db/connection.test.ts` (`prepare: false`), `src/worker/worker-loop.test.ts` (containment/backoff/reset/shutdown predicate, log sanitization).
- Auth/volume ops: `docs/s1-auth-runbook.md` (same combined API+worker container, `wait -n` CMD unchanged).
