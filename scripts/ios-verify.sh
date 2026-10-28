#!/usr/bin/env bash
#
# ios-verify.sh — the only supported way to claim "iOS tests are green".
#
# Builds and runs the Dev scheme's unit tests on the shared test simulator and prints one
# summary line. Every iOS commit in this repo must be green here first (VERIFY RULE in
# docs/harness/specs/technical-architecture.md § "iOS app architecture and conventions").
#
# Usage:
#   scripts/ios-verify.sh                      # build-for-testing + full unit test run
#   scripts/ios-verify.sh -only-testing:iosAppTests/AppConfigTests
#   scripts/ios-verify.sh -only-testing:iosAppTests/AppConfigTests/testLaunchArgumentOverrideIsNilInReleaseBuilds
#   scripts/ios-verify.sh --check-env          # no build: disk, lock, simulator presence only
#
# Selectors are bundle-relative and must NOT repeat the source folder: `iosAppTests/AppConfigTests`
# selects that class, while `iosAppTests/Services/AppConfigTests` selects nothing. A run that selects
# or executes 0 tests fails non-zero — a green run with 0 tests is a false pass.
#
# Environment:
#   IOS_VERIFY_SIM   simulator UDID (default: the shared ai-pose-test device)
#   IOS_VERIFY_TIMEOUT  wall-clock cap in seconds for a single xcodebuild invocation (1400)
#
# Why the perl wrapper: this Mac has no `timeout` binary. `alarm` survives exec, so the
# xcodebuild child gets the signal and is killed instead of hanging a lane forever.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Shared test device. Never default to CF871F97-… (that device belongs to manual QA runs);
# override deliberately with IOS_VERIFY_SIM when needed.
DEFAULT_SIM="7CC9393C-88FC-4AE6-88D3-AC68A2E266B7"
SIM_ID="${IOS_VERIFY_SIM:-$DEFAULT_SIM}"
DERIVED_DATA="/tmp/dd-shared"
WORKSPACE="$ROOT/mobile/iosApp/iosApp.xcworkspace"
SCHEME="Dev"
TIMEOUT_SECONDS="${IOS_VERIFY_TIMEOUT:-1400}"
MIN_FREE_KB=$((1536 * 1024)) # 1.5 GiB, in 1K blocks

CHECK_ENV_ONLY=0
TEST_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --check-env) CHECK_ENV_ONLY=1 ;;
    -h | --help)
      sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -only-testing:* | -skip-testing:* | -only-testing | -skip-testing) TEST_ARGS+=("$arg") ;;
    *)
      echo "ios-verify: unsupported argument '$arg'" >&2
      echo "ios-verify: only -only-testing / -skip-testing selectors are forwarded" >&2
      exit 2
      ;;
  esac
done

fail() {
  echo "ios-verify: $*" >&2
  exit 1
}

check_disk() {
  local avail_kb
  avail_kb="$(df -k / | awk 'NR == 2 {print $4}')"
  if [[ -z "$avail_kb" || "$avail_kb" -lt "$MIN_FREE_KB" ]]; then
    fail "not enough free disk on / — need >= 1.5 GB, have $(( ${avail_kb:-0} / 1024 )) MB." \
      "Clear /tmp/dd-shared, /tmp/dd-* or simulator data and retry."
  fi
  echo "disk ok: $(( avail_kb / 1024 )) MB free on / (need >= 1536 MB)"
}

check_single_build() {
  local running
  if running="$(pgrep -x xcodebuild)"; then
    fail "another xcodebuild is already running (pid(s): $(echo "$running" | tr '\n' ' '))." \
      "One iOS build at a time machine-wide — wait for it (or stop it) and retry."
  fi
  echo "no xcodebuild running machine-wide"
}

check_simulator() {
  if ! xcrun simctl list devices available 2>/dev/null | grep -q "$SIM_ID"; then
    fail "simulator $SIM_ID is not installed/available." \
      "List candidates with 'xcrun simctl list devices available' or set IOS_VERIFY_SIM."
  fi
  echo "simulator available: $SIM_ID"
}

check_env() {
  check_disk
  check_single_build
  check_simulator
}

check_env

if [[ "$CHECK_ENV_ONLY" -eq 1 ]]; then
  echo "ios-verify: env check passed (no build executed)"
  exit 0
fi

[[ -e "$WORKSPACE" ]] || fail "missing workspace $WORKSPACE (run 'cd mobile/iosApp && xcodegen generate')"
command -v xcodebuild >/dev/null || fail "xcodebuild not found — install Xcode and run 'xcode-select -p'"
command -v perl >/dev/null || fail "perl not found — required for the wall-clock guard"

mkdir -p "$DERIVED_DATA"
LOG_DIR="${TMPDIR:-/tmp}"
BUILD_LOG="$LOG_DIR/ios-verify-build.log"
TEST_LOG="$LOG_DIR/ios-verify-test.log"

run_guarded() {
  local log="$1"
  shift
  perl -e 'alarm shift; exec @ARGV' "$TIMEOUT_SECONDS" "$@" >"$log" 2>&1
}

echo "build-for-testing: scheme $SCHEME → $DERIVED_DATA (timeout ${TIMEOUT_SECONDS}s)"
if ! run_guarded "$BUILD_LOG" xcodebuild build-for-testing \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -destination "id=$SIM_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  ${TEST_ARGS[@]+"${TEST_ARGS[@]}"}; then
  echo "--- last 40 lines of $BUILD_LOG ---" >&2
  tail -40 "$BUILD_LOG" >&2
  fail "build-for-testing failed (full log: $BUILD_LOG)"
fi
grep -q "TEST BUILD SUCCEEDED" "$BUILD_LOG" || fail "build log has no 'TEST BUILD SUCCEEDED' (full log: $BUILD_LOG)"

echo "test-without-building (reuses the products above)"
set +e
run_guarded "$TEST_LOG" xcodebuild test-without-building \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -destination "id=$SIM_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  ${TEST_ARGS[@]+"${TEST_ARGS[@]}"}
TEST_STATUS=$?
set -e

# One-line summary parsed from the xctest output: the last "Executed N tests, with M failures"
# line is the aggregate for the run. Xcode 16+ also prints "Test run with N tests passed".
SUMMARY_LINE="$(grep -E "Executed [0-9]+ tests?, with [0-9]+ failures?" "$TEST_LOG" | tail -1 || true)"
EXECUTED="?"
FAILURES="?"
if [[ -n "$SUMMARY_LINE" ]]; then
  EXECUTED="$(sed -E 's/.*Executed ([0-9]+) tests?, with ([0-9]+) failures?.*/\1/' <<<"$SUMMARY_LINE")"
  FAILURES="$(sed -E 's/.*Executed ([0-9]+) tests?, with ([0-9]+) failures?.*/\2/' <<<"$SUMMARY_LINE")"
elif grep -qE "Test run with [0-9]+ tests? (passed|failed)" "$TEST_LOG"; then
  SUMMARY_LINE="$(grep -E "Test run with [0-9]+ tests? (passed|failed)" "$TEST_LOG" | tail -1)"
  EXECUTED="$(sed -E 's/.*Test run with ([0-9]+) tests?.*/\1/' <<<"$SUMMARY_LINE")"
  if grep -qE "Test run with [0-9]+ tests? passed" <<<"$SUMMARY_LINE"; then FAILURES="0"; else FAILURES="unknown"; fi
else
  EXECUTED="unknown"
  FAILURES="unknown"
fi

# Xcode 16+ prints "** TEST EXECUTE SUCCEEDED **"; older builds printed "** TEST SUCCEEDED **".
# Matching only the latter reported every green run as TEST FAILED (executed>0, failures=0) and
# exited 1, which is why the success marker is matched in both spellings.
if grep -qE "TEST (EXECUTE )?SUCCEEDED" "$TEST_LOG"; then TEST_RESULT="TEST SUCCEEDED"; else TEST_RESULT="TEST FAILED"; fi

echo "ios-verify: $TEST_RESULT · executed=$EXECUTED · failures=$FAILURES · simulator=$SIM_ID · log=$TEST_LOG"

# A green xcodebuild with 0 selected tests means the selector matched nothing: exit 0 there would
# report an unbuilt, unrun change as verified. Fail on the selection itself, before the generic
# success/failure paths, so the message names the fix instead of just the status.
if [[ "$EXECUTED" == "0" ]]; then
  echo "--- last 20 lines of $TEST_LOG ---" >&2
  tail -20 "$TEST_LOG" >&2
  fail "0 tests selected or executed — a green run with 0 tests is a false pass." \
    "Selectors passed: ${TEST_ARGS[*]:-<none>}. They are bundle-relative without the source folder:" \
    "'iosAppTests/AppConfigTests', not 'iosAppTests/Services/AppConfigTests'."
fi

if [[ "$TEST_STATUS" -ne 0 ]]; then
  echo "--- last 40 lines of $TEST_LOG ---" >&2
  tail -40 "$TEST_LOG" >&2
  exit "$TEST_STATUS"
fi

if [[ "$TEST_RESULT" != "TEST SUCCEEDED" ]]; then
  echo "--- last 40 lines of $TEST_LOG ---" >&2
  tail -40 "$TEST_LOG" >&2
  exit 1
fi

if [[ "$FAILURES" == "unknown" ]]; then
  # A green run that printed no parseable counts cannot be verified; treat it as red so a
  # truncated log can never masquerade as a passing lane.
  fail "xctest output has no parseable 'Executed … tests' summary (full log: $TEST_LOG)"
fi

[[ "$FAILURES" -eq 0 ]] || fail "$FAILURES test(s) failed even though xcodebuild reported success"
[[ "$EXECUTED" -gt 0 ]] || fail "0 tests executed — the run selected nothing, treat as red"

echo "ios-verify: OK"
