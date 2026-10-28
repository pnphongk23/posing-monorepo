#!/usr/bin/env bash
# Usage: run.sh <simulator-udid> [flow-file ...]   (default: every flow in flows/)
set -euo pipefail
cd "$(dirname "$0")"
./check-traceability.sh
udid=${1:?simulator udid}; shift || true
export MAESTRO_CLI_NO_ANALYTICS=1
exec maestro --device "$udid" test -e APP_ID=posing.camera.app "${@:-flows}"
