---
work_item: 5
title: Docker Railway CLI install credentials volume and S1 auth probe runbook
status: completed
priority: P2
effort: M
dependencies:
  - 4
decision_dependencies: []
---

# Work Item 5: Docker Railway CLI install credentials volume and S1 auth probe runbook

**Kind:** technical

## Tasks

- Update `Dockerfile` to `npm install -g` Higgsfield CLI (verify exact package
  name; not `npx` at runtime).
- Set `ENV HIGGSFIELD_CREDENTIALS_PATH=/app/higgsfield/credentials.json` and
  create mount directory.
- Document Railway volume mount for `/app/higgsfield` and secret injection
  pattern for initial `credentials.json` upload.
- Add `scripts/higgsfield-auth-probe.sh` (or npm script) running:
  `higgsfield auth status && higgsfield account`; exit non-zero on failure.
- Write S1 runbook markdown in Plan directory or `docs/harness/` ops note:
  alert → human headed `higgsfield auth login` → upload credentials to Railway
  volume → re-run probe. **Explicitly forbid** headless `auth login` in Docker.
- Configure Railway cron (or documented external cron) to run probe on schedule
  (recommend: every 6h).
- Verify combined container CMD still starts API + worker after CLI install.
- Document local Compose workflow: `docker compose build && docker compose up` from
  repo root; persistent data under `.docker-persist/data` and
  `.docker-persist/higgsfield` (no `docker cp` hotfixes for provider changes).

## Scope and affected files

- `web/services/pose-extract-server/Dockerfile`
- `web/services/pose-extract-server/scripts/higgsfield-auth-probe.sh` (new)
- `web/services/pose-extract-server/package.json` (probe script entry)
- `docs/harness/plans/260816-2240-higgsfield-cli-parallel-extract-provider/s1-auth-runbook.md` (new, ops doc)
- Railway service config (documented; not committed secrets)

## Success criteria

- Docker image contains `higgsfield` on PATH globally.
- Container starts API + worker with CLI present (`higgsfield --version` in image).
- `HIGGSFIELD_CREDENTIALS_PATH` points to volume-backed file in Railway docs.
- S1 probe script exits 0 with valid credentials, non-zero when invalid.
- Runbook steps reproducible by operator without application code changes.

## Risks

- CLI package size may inflate image; monitor build time.
- Railway volume attach requires manual dashboard step; document clearly.
- Probe false positives if CLI changes `auth status` output format.

## Required evidence

- `docker build` log showing global CLI install success.
- Probe script output (redacted) for valid and invalid credential states.
- Committed S1 runbook with alert + human re-login steps.
- Railway cron configuration screenshot or exported service JSON (secrets redacted).
