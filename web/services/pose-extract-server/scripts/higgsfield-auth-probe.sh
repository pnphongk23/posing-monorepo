#!/usr/bin/env bash
# S1 auth health probe for @higgsfield/cli (global install in Docker).
# Exit 0 when credentials are valid; non-zero on missing file, auth, or account errors.
#
# Note: @higgsfield/cli@1.1.23 has no `auth status` subcommand. Equivalent checks:
#   higgsfield auth token      — local OAuth token present and readable
#   higgsfield account status  — remote account reachable with that token
set -euo pipefail

CREDENTIALS_PATH="${HIGGSFIELD_CREDENTIALS_PATH:-/app/higgsfield/credentials.json}"
export HIGGSFIELD_CREDENTIALS_PATH="$CREDENTIALS_PATH"

if ! command -v higgsfield >/dev/null 2>&1; then
  echo "ERROR: higgsfield CLI not found on PATH" >&2
  exit 127
fi

if [[ ! -f "$CREDENTIALS_PATH" ]]; then
  echo "ERROR: credentials file missing at $CREDENTIALS_PATH" >&2
  exit 1
fi

echo "Probe: higgsfield $(higgsfield --version 2>&1 | head -1)"
echo "Probe: credentials file present at $CREDENTIALS_PATH"

higgsfield auth token >/dev/null
echo "Probe: auth token OK"

higgsfield account status
echo "Probe: account status OK"
