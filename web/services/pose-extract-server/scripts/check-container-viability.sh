#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG="pose-extract-server:local"
CONTAINER_NAME="pose-extract-server-viability"
HOST_PORT="38080"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# A reachable PostgreSQL database is required — Supabase pooler URL or a local
# `postgres`. If you run Postgres on the host, use `host.docker.internal` (not
# `localhost`) so the container can reach it. R2 vars and ADMIN_SECRET are also
# validated by the service on boot; defaults below are placeholders for the check.
: "${DATABASE_URL:?ERROR: DATABASE_URL is required (Postgres connection string).}"

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}

trap cleanup EXIT

echo "[1/3] Building Docker image"
docker build -f web/services/pose-extract-server/Dockerfile -t "$IMAGE_TAG" "$REPO_ROOT"

cleanup

echo "[2/3] Starting container"
docker run -d \
  --name "$CONTAINER_NAME" \
  -p "$HOST_PORT:3000" \
  -e NODE_ENV=production \
  -e PORT=3000 \
  -e DATABASE_URL="$DATABASE_URL" \
  -e ADMIN_SECRET="${ADMIN_SECRET:-spike-admin-secret}" \
  -e R2_ACCOUNT_ID="${R2_ACCOUNT_ID:-spike-account-id}" \
  -e R2_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID:-spike-access-key-id}" \
  -e R2_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY:-spike-secret-access-key}" \
  -e R2_BUCKET="${R2_BUCKET:-spike-bucket}" \
  -e R2_PUBLIC_URL="${R2_PUBLIC_URL:-https://spike.example.com}" \
  -e APP_VERSION=docker-spike \
  "$IMAGE_TAG" >/dev/null

echo "[3/3] Waiting for /api/health"
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${HOST_PORT}/api/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

curl -fsS "http://127.0.0.1:${HOST_PORT}/api/health"

echo
echo "Container viability check passed."
