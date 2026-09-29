#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_ENV="$ROOT/web/services/pose-extract-server/.env"

COMPOSE_ENV_ARGS=()
if [[ -f "$SERVER_ENV" ]]; then
  COMPOSE_ENV_ARGS+=(--env-file "$SERVER_ENV")
else
  echo "WARN: ADMIN_SECRET is not set. Admin UI proxy may fail until you set it in $SERVER_ENV" >&2
fi

cd "$ROOT"
exec docker compose "${COMPOSE_ENV_ARGS[@]}" -f docker-compose.dev.yml "$@"
