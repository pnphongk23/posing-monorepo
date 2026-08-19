#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_ENV="$ROOT/web/services/pose-extract-server/.env"

if [[ -f "$SERVER_ENV" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$SERVER_ENV"
  set +a
  export ADMIN_SECRET
  export POSE_EXTRACT_ADMIN_SECRET="${ADMIN_SECRET}"
fi

if [[ -z "${ADMIN_SECRET:-}" ]]; then
  echo "WARN: ADMIN_SECRET is not set. Admin UI proxy may fail until you set it in $SERVER_ENV" >&2
fi

cd "$ROOT"
exec docker compose -f docker-compose.dev.yml "$@"
