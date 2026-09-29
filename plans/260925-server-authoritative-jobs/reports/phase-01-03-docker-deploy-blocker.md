# Docker check / dev deploy — BLOCKED (attempt 2)

Phases 1-3 remain done and independently Lead-verified locally (see phase-01/02/03-evidence.md;
combined `npm test` = 245/245, lint clean, admin-ui proxy test + lint clean, openapi parses).

## Progress this attempt
Docker daemon was confirmed reachable (`docker info` succeeded, server v29.3.1) and:
1. `docker compose -f docker-compose.dev.yml build postgres pose-extract-server admin-ui` — **succeeded**. Both `ai-pose-pose-extract-server:latest` and `ai-pose-admin-ui:latest` images built cleanly.
2. `docker compose -f docker-compose.dev.yml up -d postgres` — **succeeded**, container `pose-postgres-dev` reported `Running`.
3. Noted: plain `docker compose up` does not read `web/services/pose-extract-server/.env`'s `ADMIN_SECRET` into the shell for admin-ui's `${ADMIN_SECRET}` interpolation (compose warns "variable is not set, defaulting to blank"). The repo already has `scripts/docker-dev.sh` for this — it sources the server `.env` and exports `ADMIN_SECRET`/`POSE_EXTRACT_ADMIN_SECRET` before calling `docker compose`. Plan is to use that wrapper for the remaining steps instead of raw `docker compose`.
4. Confirmed `ADMIN_SECRET` in `.env` is the shipped dev placeholder (`replace-with-strong-secret`), not a real credential — no secret-handling concern.

## New blocker
Immediately after step 2, the Docker daemon stopped responding:
```
$ docker compose -f docker-compose.dev.yml ps postgres   # hung, no output, backgrounded
$ docker ps --filter name=pose-postgres-dev               # hung, no output, backgrounded
$ docker version --format '{{.Server.Version}}'           # hung, no output, backgrounded
$ pgrep -fl "Docker Desktop|com.docker"                    # no processes found
$ ls -la ~/.docker/run/docker.sock                         # socket file still exists (stale?)
```
Three `docker` CLI invocations are currently hung in the background waiting on the daemon; no
Docker process is visible via `pgrep`. This looks like Docker Desktop's daemon crashed or was
killed shortly after handling the build + `postgres up`, leaving a stale socket file. This is a
host-level Docker Desktop issue, not something fixable from this sandboxed shell — I have no way
to restart the Docker Desktop app/VM from here.

## Status
- Image builds: done, verified.
- `postgres` container: was started successfully, but I can no longer query its live status
  since the daemon stopped answering — actual current state (still running vs. crashed with the
  daemon) is **unknown**, not verified either way.
- `pose-extract-server` / `admin-ui` containers: **not started** — blocked before this step.
- Docker-based `npm test`/`npm run lint` (pose-extract-server) and `npm run lint`/`node --test`
  (admin-ui): **not run**.
- Dev deploy (admin-ui → pose-extract-server): **not started**, still gated on Docker checks
  passing per the user's own rule.

## Next dependency
Same as attempt 1: needs a human with desktop access to check/restart Docker Desktop. Once the
daemon answers `docker version` again reliably, resume from `docker compose -f
docker-compose.dev.yml up -d postgres` (or `bash scripts/docker-dev.sh up -d postgres` to also
get `ADMIN_SECRET` wired correctly), confirm health, then continue with
`pose-extract-server`/`admin-ui` checks and the ordered deploy.
