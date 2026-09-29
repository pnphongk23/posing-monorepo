# Docker checks — pose-extract-server + admin-ui (dev compose)

## Attempt 1 — 238/245, held by General Lead
Initial in-container run of `pose-extract-server` was 238/245 (7 pre-existing failures, confirmed
unrelated to Phases 1-3 via empty `git diff` on both failing test files). General Lead held the
deploy gate on the literal "Docker checks pass" requirement and asked for both gaps fixed:
1. `src/config/env.ts`'s `getEnv()` built its parsed object as `overrides?.KEY ?? process.env.KEY`
   per field — an explicit `KEY: undefined` in `overrides` (used by env.test.ts's "throws when
   missing" tests) still fell through to the real container env value.
2. `Dockerfile.dev` never installed Python, so `lineartBackgroundRemover.test.ts` failed with
   `spawn python3 ENOENT` inside the container (the production `Dockerfile` does install it, and
   `railway.toml` deploys via that Dockerfile, not `Dockerfile.dev` — but the check command itself
   still needs the dev image to have Python).

## Fix (Worker `1a206ec0`, Hoàng Trung)
- `src/config/env.ts`: replaced the 24-field manual `??` block with
  `envSchema.safeParse({ ...process.env, ...(overrides ?? {}) })` — object-spread semantics give an
  explicit `undefined` in `overrides` correct precedence over `process.env`. `env.test.ts`,
  `envSchema`, caching (`cachedEnv`/`resetEnvCache`), and `authRateLimitFromEnv` all untouched.
- `Dockerfile.dev`: added `apt-get install python3 python3-pip` and
  `pip3 install --no-cache-dir --break-system-packages -r requirements.txt` (mirrors the production
  Dockerfile). `requirements.txt` copied in for the pip step; `scripts/*.py` stays bind-mounted at
  runtime as before.
- Confirmed via `git diff --stat`: only these two files changed, no Phase 1-3 file touched.

## Final checks (Lead-verified independently)
Host:
```
cd web/services/pose-extract-server
npm test
 Test Files  34 passed (34)
      Tests  245 passed (245)
npm run lint   # clean
```

Container (rebuilt image, recreated container):
```
docker compose -f docker-compose.dev.yml build pose-extract-server   # Image Built
docker compose -f docker-compose.dev.yml up -d pose-extract-server   # Recreated, Started
docker exec pose-extract-server-dev npm test
 Test Files  34 passed (34)
      Tests  245 passed (245)
docker exec pose-extract-server-dev npm run lint   # clean
```

admin-ui (unaffected by this fix, unchanged from earlier run, container never restarted):
```
docker exec pose-admin-ui-dev npm run lint   # 0 errors, 5 pre-existing warnings
docker exec pose-admin-ui-dev node --test src/lib/poseExtractExtractPoseProxy.test.mjs
 tests 1, pass 1, fail 0
```

Container health (all three, post-fix):
```
pose-postgres-dev: Up 27 minutes (healthy)
pose-extract-server-dev: Up ~1 minute
pose-admin-ui-dev: Up 26 minutes
curl http://localhost:3000/api/health -> 200 {"status":"ok",...}
curl -o /dev/null -w '%{http_code}' http://localhost:3001/admin -> 200
```

## Status
**Docker gate: PASS.** 245/245 on both host and rebuilt container for pose-extract-server, lint
clean both places; admin-ui lint + proxy test clean; all three dev containers healthy. Cleared to
proceed to the ordered dev deploy (admin-ui → pose-extract-server) per the General Lead's
instruction.
