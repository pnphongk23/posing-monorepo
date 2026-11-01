#!/usr/bin/env bash
# Usage: [SHOTS_DIR=<dir>] run.sh <simulator-udid> [flow-file ...]   (default: every flow in flows/)
# With SHOTS_DIR set, flows run one by one and the final screen of each is saved as <flow>.png.
# Flows tagged `e2e` sign in with the real QA account and need the gitignored credentials; without
# E2E_EMAIL in the environment they are excluded, so the default run stays green with no credentials
# (with SHOTS_DIR set the per-flow loop skips those files outright):
#   set -a; . ./e2e.local.env; set +a; ./run.sh <udid>
set -euo pipefail
cd "$(dirname "$0")"
udid=${1:?simulator udid}; shift || true
# Disk gate: the lane-2 simulator accumulates XCTest attachments fast enough to fill the volume (it
# happened on 1.1 build 17), and an ENOSPC mid-run reads as random test failures. Refuse to start
# below the floor instead of discovering it halfway through a suite.
min_free_gb=${RUN_MIN_FREE_GB:-3}
free_gb=$(df -g / | awk 'NR==2 {print $4}')
if [ "${free_gb:-0}" -lt "$min_free_gb" ]; then
  echo "run.sh: refusing to start - ${free_gb:-0} GB free on /, need ${min_free_gb} GB. Attachments live under" \
       "~/Library/Developer/CoreSimulator/Devices/<udid>/data/Containers/Data/InternalDaemon/*/Attachments."
  exit 3
fi
# Disk hygiene, lane 2 only (never another simulator, never erase). Two sizes matter: XCTest
# attachments inside the device, and the per-run xctestrunner build in $TMPDIR. Shared DerivedData
# (/tmp/dd-*) is deliberately NOT deleted here — it belongs to builds other workers are using, and a
# test run must not pull it out from under them.
purge_attachments() {
  case "$udid" in CF871F97*) ;; *) return 0 ;; esac
  find "$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Containers/Data/InternalDaemon/"*/Attachments \
    -type f -mmin +10 -delete 2>/dev/null || true
  find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'maestro_xctestrunner_*' -mmin +10 -exec rm -rf {} + 2>/dev/null || true
}
purge_attachments
./check-traceability.sh
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
  purge_attachments
  case "$udid" in CF871F97*) return 0 ;; esac
  rm -rf "$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/Caches/com.apple.containermanagerd/Dead/"* 2>/dev/null || true
}
trap cleanup_dead_containers EXIT
run() { maestro --device "$udid" test -e APP_ID=posing.camera.app "${e2e_args[@]}" "$@"; }
# Without credentials `--exclude-tags=e2e` filters those flows out of the invocation; handed one file
# at a time that leaves an invocation with no flow in it, which the shot loop would score as a failed
# flow. Skip the file instead of asking maestro to run nothing.
e2e_tagged() { grep -qE '^tags:.*(,|\[)[[:space:]]*e2e[[:space:]]*(,|\])' "$1"; }
if [ -z "${SHOTS_DIR:-}" ]; then
  run "${@:-flows}"
  exit $?
fi
mkdir -p "$SHOTS_DIR"; rc=0; skipped=0
[ $# -gt 0 ] || set -- flows/*.yaml
for f in "$@"; do
  if [ -z "${E2E_EMAIL:-}" ] && e2e_tagged "$f"; then
    echo "run.sh: skipping $f (e2e-tagged, E2E_EMAIL is not set)"
    skipped=$((skipped + 1))
    continue
  fi
  run "$f" && xcrun simctl io "$udid" screenshot "$SHOTS_DIR/$(basename "$f" .yaml).png" >/dev/null 2>&1 || rc=1
done
if [ "$skipped" -gt 0 ]; then
  echo "run.sh: skipped $skipped e2e-tagged flow(s) - export E2E_EMAIL to run them"
fi
exit $rc
