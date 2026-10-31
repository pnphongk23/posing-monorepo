#!/usr/bin/env bash
# Usage: [SHOTS_DIR=<dir>] run.sh <simulator-udid> [flow-file ...]   (default: every flow in flows/)
# With SHOTS_DIR set, flows run one by one and the final screen of each is saved as <flow>.png.
# Flows tagged `e2e` sign in with the real QA account and need the gitignored credentials; without
# E2E_EMAIL in the environment they are excluded, so the default run stays green with no credentials:
#   set -a; . ./e2e.local.env; set +a; ./run.sh <udid>
set -euo pipefail
cd "$(dirname "$0")"
./check-traceability.sh
udid=${1:?simulator udid}; shift || true
export MAESTRO_CLI_NO_ANALYTICS=1
# `e2e`-tagged flows run only when the run-time credentials exist; otherwise they are filtered out of
# the run entirely (a flow that fails fast on a missing E2E_EMAIL must never redden the default suite).
e2e_args=()
if [ -n "${E2E_EMAIL:-}" ]; then
  e2e_args=(-e "E2E_EMAIL=$E2E_EMAIL")
  if [ -n "${E2E_PASSWORD:-}" ]; then e2e_args+=(-e "E2E_PASSWORD=$E2E_PASSWORD"); fi
  if [ -n "${E2E_EMAIL_B:-}" ]; then e2e_args+=(-e "E2E_EMAIL_B=$E2E_EMAIL_B"); fi
  if [ -n "${E2E_PASSWORD_B:-}" ]; then e2e_args+=(-e "E2E_PASSWORD_B=$E2E_PASSWORD_B"); fi
  echo "run.sh: E2E_EMAIL is set - e2e-tagged flows included"
else
  e2e_args=(--exclude-tags=e2e)
  echo "run.sh: E2E_EMAIL is not set - e2e-tagged flows excluded"
fi
# Reinstalls leave dead app containers behind; drop them after every run (this simulator only, disk is tight).
cleanup_dead_containers() {
  case "$udid" in CF871F97*) return 0 ;; esac
  rm -rf "$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/Caches/com.apple.containermanagerd/Dead/"* 2>/dev/null || true
}
trap cleanup_dead_containers EXIT
run() { maestro --device "$udid" test -e APP_ID=posing.camera.app "${e2e_args[@]}" "$@"; }
if [ -z "${SHOTS_DIR:-}" ]; then
  run "${@:-flows}"
  exit $?
fi
mkdir -p "$SHOTS_DIR"; rc=0
[ $# -gt 0 ] || set -- flows/*.yaml
for f in "$@"; do
  run "$f" && xcrun simctl io "$udid" screenshot "$SHOTS_DIR/$(basename "$f" .yaml).png" >/dev/null 2>&1 || rc=1
done
exit $rc
