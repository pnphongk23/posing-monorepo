#!/usr/bin/env bash
# Usage: [SHOTS_DIR=<dir>] run.sh <simulator-udid> [flow-file ...]   (default: every flow in flows/)
# With SHOTS_DIR set, flows run one by one and the final screen of each is saved as <flow>.png.
set -euo pipefail
cd "$(dirname "$0")"
./check-traceability.sh
udid=${1:?simulator udid}; shift || true
export MAESTRO_CLI_NO_ANALYTICS=1
# Reinstalls leave dead app containers behind; drop them after every run (this simulator only, disk is tight).
cleanup_dead_containers() {
  case "$udid" in CF871F97*) return 0 ;; esac
  rm -rf "$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/Caches/com.apple.containermanagerd/Dead/"* 2>/dev/null || true
}
trap cleanup_dead_containers EXIT
run() { maestro --device "$udid" test -e APP_ID=posing.camera.app "$@"; }
if [ -z "${SHOTS_DIR:-}" ]; then
  maestro --device "$udid" test -e APP_ID=posing.camera.app "${@:-flows}"
  exit $?
fi
mkdir -p "$SHOTS_DIR"; rc=0
[ $# -gt 0 ] || set -- flows/*.yaml
for f in "$@"; do
  run "$f" && xcrun simctl io "$udid" screenshot "$SHOTS_DIR/$(basename "$f" .yaml).png" >/dev/null 2>&1 || rc=1
done
exit $rc
