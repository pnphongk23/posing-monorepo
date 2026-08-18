# Deployment Viability — Postgres + R2

This service stores all state in PostgreSQL (`DATABASE_URL`) and community pose
images in Cloudflare R2. There is **no SQLite** and no native database module
(`better-sqlite3` has been removed), so deployment checks focus on:

1. The Node service booting with a reachable `DATABASE_URL`.
2. The schema applying on boot (`applySchema` → `dist/db/schema.sql`).
3. The health endpoint responding once the schema is applied.
4. R2 being reachable for community image uploads in production.

## Required environment variables

The service validates these on boot and exits with an error if any are missing:

- `DATABASE_URL` — PostgreSQL connection string. A hosted Postgres such as
  [Supabase](https://supabase.com) works well (use the **pooler** connection
  string, e.g. `postgresql://postgres.[ref]:[password]@aws-0-[region].pooler.supabase.com:6543/postgres`).
- `ADMIN_SECRET` — Bearer token for admin endpoints.
- `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` — Cloudflare R2 credentials.
- `R2_BUCKET` — R2 bucket name (note: `R2_BUCKET`, not `R2_BUCKET_NAME`).
- `R2_PUBLIC_URL` — public base URL for the bucket (e.g. `https://pub-xxx.r2.dev`).

`COMMUNITY_UPLOAD_DIR` is **local dev only**; in production (`NODE_ENV=production`)
community images are stored in R2 and served from `R2_PUBLIC_URL`.

## Local Docker workflow (repo root)

Use Compose for the full stack (API + worker in `pose-extract-server`, plus
`admin-ui`). `docker-compose.yml` loads `DATABASE_URL` and the R2 vars from
`web/services/pose-extract-server/.env` — set those before running.

```bash
docker compose build && docker compose up
```

Persistent host data lives under `.docker-persist/`:

| Host path | Container path | Purpose |
| --- | --- | --- |
| `.docker-persist/data/` | `/app/data` | Browser profile only (`BROWSER_PROFILE_DIR`) — **not** the database |
| `.docker-persist/higgsfield/` | `/app/higgsfield` | `credentials.json` (`HIGGSFIELD_CREDENTIALS_PATH`) |

The database is **not** a mounted volume — it lives in your Postgres instance
referenced by `DATABASE_URL`.

## Local checks

### 1) Boot + schema apply against an ephemeral Postgres

```bash
npm run spike:boot-check
```

This command:

- Builds TypeScript output (`npm run build`)
- Starts an ephemeral in-process Postgres (PGlite) on a local socket
- Boots `dist/index.js` with `DATABASE_URL` pointing at that ephemeral instance,
  plus `ADMIN_SECRET` and placeholder R2 vars
- Calls `GET /api/health`
- Verifies the schema was applied (checks the `schema_bootstrap` sentinel row)

### 2) Container viability

```bash
npm run spike:docker-viability
```

This command:

- Builds the Docker image (`Dockerfile`)
- Runs the container with `DATABASE_URL` supplied via the `DATABASE_URL` env var
  (a reachable Postgres — Supabase or a local `postgres` — is required)
- Calls `GET /api/health`

See `scripts/check-container-viability.sh` for the exact env contract.
