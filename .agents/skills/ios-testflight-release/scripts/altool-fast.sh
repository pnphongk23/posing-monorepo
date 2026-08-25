#!/usr/bin/env bash
set -euo pipefail

APPLE_ID="tolaphamnhuphong@gmail.com"
KEYCHAIN_ITEM="camerapose-appstore"
KEYCHAIN_PATH_FILE="${HOME}/.config/camerapose/altool-keychain-path"

usage() {
  cat >&2 <<'EOF'
Usage:
  altool-fast.sh providers
  altool-fast.sh validate <ipa-path>
  altool-fast.sh upload <ipa-path>
  altool-fast.sh status <delivery-uuid>

This wrapper reads the App Store app-specific password from the project's
custom macOS keychain into a child-only environment variable. It never prints
or writes the credential.
EOF
  exit 64
}

case "${1:-}" in
  providers) timeout_seconds=30 ;;
  validate)  timeout_seconds=120; [[ $# -eq 2 ]] || usage ;;
  upload)    timeout_seconds=300; [[ $# -eq 2 ]] || usage ;;
  status)    timeout_seconds=120; [[ $# -eq 2 ]] || usage ;;
  *) usage ;;
esac

[[ -f "$KEYCHAIN_PATH_FILE" ]] || {
  echo "BLOCKED_CREDENTIALS: missing $KEYCHAIN_PATH_FILE" >&2
  exit 78
}

KEYCHAIN_PATH="$(tr -d '\r\n' < "$KEYCHAIN_PATH_FILE")"
[[ -f "$KEYCHAIN_PATH" ]] || {
  echo "BLOCKED_CREDENTIALS: custom keychain not found" >&2
  exit 78
}

# This dedicated project keychain was created with an empty keychain password
# under explicit user authorization. The App Store password inside it is never
# printed, placed in argv, or written to a file.
security unlock-keychain -p '' "$KEYCHAIN_PATH" >/dev/null
set +x
export ALTOOL_APP_PASSWORD="$(security find-generic-password \
  -s "$KEYCHAIN_ITEM" \
  -a "$APPLE_ID" \
  -w "$KEYCHAIN_PATH")"
trap 'unset ALTOOL_APP_PASSWORD' EXIT

case "$1" in
  providers)
    command=(xcrun altool --list-providers
      -u "$APPLE_ID" -p @env:ALTOOL_APP_PASSWORD --output-format xml)
    ;;
  validate)
    command=(xcrun altool --validate-app -f "$2" -t ios
      -u "$APPLE_ID" -p @env:ALTOOL_APP_PASSWORD --output-format xml)
    ;;
  upload)
    command=(xcrun altool --upload-app -f "$2" -t ios
      -u "$APPLE_ID" -p @env:ALTOOL_APP_PASSWORD --output-format xml)
    ;;
  status)
    command=(xcrun altool --build-status --delivery-id "$2"
      -u "$APPLE_ID" -p @env:ALTOOL_APP_PASSWORD --output-format xml)
    ;;
esac

"${command[@]}" &
altool_pid=$!
(
  sleep "$timeout_seconds"
  if kill -0 "$altool_pid" 2>/dev/null; then
    echo "ALTOOL_TIMEOUT: ${1} exceeded ${timeout_seconds}s" >&2
    ps -o pid,etime,state,%cpu,%mem,command -p "$altool_pid" >&2 || true
    lsof -nP -a -p "$altool_pid" -i >&2 || true
    sample "$altool_pid" 1 1 2>/dev/null \
      | grep -m 1 -E 'SecItemCopyMatching|CFNetwork|NSURLSession|mach_msg' >&2 \
      || true
    kill -TERM "$altool_pid" 2>/dev/null || true
  fi
) &
watchdog_pid=$!

set +e
wait "$altool_pid"
status=$?
set -e
kill "$watchdog_pid" 2>/dev/null || true
wait "$watchdog_pid" 2>/dev/null || true

if [[ $status -eq 143 ]]; then
  echo "Operation timed out. For upload, do not retry until App Store status is checked." >&2
  exit 124
fi

exit "$status"
