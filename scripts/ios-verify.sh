#!/usr/bin/env bash
#
# ios-verify.sh — the only supported way to claim "iOS tests are green".
#
# Builds and runs the Dev scheme's unit tests on a shared test simulator and prints one summary
# line. Every iOS commit in this repo must be green here first (VERIFY RULE in
# docs/harness/specs/technical-architecture.md § "iOS app architecture and conventions").
#
# Usage:
#   scripts/ios-verify.sh                      # queue for a build slot, then build-for-testing + full test run
#   scripts/ios-verify.sh --check-env          # no build: disk, build slots, simulator presence only
#   IOS_VERIFY_ONLY_TESTING=AppConfigTests,SessionScopeCoordinatorTests scripts/ios-verify.sh
#   scripts/ios-verify.sh -only-testing:iosAppTests/AppConfigTests
#   scripts/ios-verify.sh -only-testing:iosAppTests/AppConfigTests/testLaunchArgumentOverrideIsNilInReleaseBuilds
#   IOS_VERIFY_SLOT=2 scripts/ios-verify.sh     # force slot 2 (fails if slot 2 is not configured)
#
# Selectors are bundle-relative and must NOT repeat the source folder: `iosAppTests/AppConfigTests`
# selects that class, while `iosAppTests/Services/AppConfigTests` selects nothing. A run that selects
# or executes 0 tests fails non-zero — a green run with 0 tests is a false pass.
#
# Build slots — the script QUEUES, it never fails because another build is running:
#   slot 1 = simulator 7CC9393C-88FC-4AE6-88D3-AC68A2E266B7 ("ai-pose-test") + /tmp/dd-shared
#   slot 2 = simulator $IOS_VERIFY_SIM_2 + /tmp/dd-shared-2  (only offered when IOS_VERIFY_SIM_2 is set)
#            the Feature lane's device is CF871F97-1789-4490-B3E3-0B5EFA39F23F ("iPhone 16")
#   Locks are /tmp/ai-pose-slot-1 and /tmp/ai-pose-slot-2 (atomic `mkdir`). The first run takes the
#   first free slot, the second takes the other, the third blocks until one frees and prints how long
#   it waited. A lock is stale (and is recovered) when its holder PID is dead or when it is older than
#   90 min. The slot is released on EXIT, INT and TERM, so killing a run frees it for the next one.
#   Exactly 2 slots, never 3: this is a 16 GB machine and 3 sims plus Maestro swaps.
#   Build/test logs are per slot ($TMPDIR/ios-verify-slot-<n>-{build,test}.log) so two concurrent
#   runs never parse each other's output.
#   Release/archive work is a separate path and does not take a slot unless it builds on the sim.
#
# Environment:
#   IOS_VERIFY_SIM        slot 1 simulator UDID (default: the shared ai-pose-test device)
#   IOS_VERIFY_SIM_2      slot 2 simulator UDID; unset = slot 2 disabled (slot 1 only)
#   IOS_VERIFY_SLOT       force slot 1 or slot 2 instead of taking the first free one
#   IOS_VERIFY_DD         slot 1 DerivedData path (default: /tmp/dd-shared). Slot 2 always uses
#                         /tmp/dd-shared-2 so two lanes can never share one DerivedData root.
#   IOS_VERIFY_TIMEOUT    wall-clock cap in seconds for a single xcodebuild invocation (1400)
#   IOS_VERIFY_ONLY_TESTING  comma-separated test classes/methods for the iterate loop (R3). Each
#                         entry becomes its own `-only-testing:` selector; a bare class name gets
#                         the `iosAppTests/` test-target prefix, a selector that already starts with
#                         the target keeps its form. Default (unset) = the full unit run. Run the
#                         full suite ONCE before commit.
#   IOS_VERIFY_FAKE_FREE_KB  override the free-space reading (KB) so the purge/refuse path can be
#                         exercised without filling the disk. The purge is still the real, approved,
#                         exclusion-guarded purge (it never becomes unsafe because the number is
#                         faked); the post-purge decision uses fake + bytes actually freed.
#
# Disk (R2, user-approved auto-purge): when `/` is below 3 GB free the script purges ONLY
#   1. testmanagerd attachments on every simulator that is neither a slot simulator nor held by a
#      live slot — files untouched for 10 min;
#   2. $TMPDIR/maestro_xctestrunner_* directories untouched for 10 min;
#   3. /tmp/dd-* roots that no live slot and no live xcodebuild command line references.
# It re-reads the free space and refuses to build only below 1.5 GB. It logs every item and the bytes
# freed. It never touches QuanLyLop, /tmp/qlh-*, marketing/, either slot simulator, or the
# DerivedData of a held slot / in-flight xcodebuild. Archives and exports are NOT purged: the release
# skill has no `uploaded` marker convention, so that item stays unimplemented (see ledger rule 13).
# MIN_FREE_ARCHIVE_KB below is the 5 GB floor that an archive/release path must use; this script only
# runs tests, so it refuses below 1.5 GB.
#
# Every run (green or red) also drops the shared device's dead app containers
# (.../com.apple.containermanagerd/Dead/*) and prints the bytes freed. That path is built from the
# slot's own UDID only, and the cleanup keeps the exit code.
#
# Host rule (R4) — exactly ONE Maestro run may exist on this host at any time: Maestro's iOS driver
# port 127.0.0.1:7001 is host-global, so two runs (even on different sims) kill each other's driver.
# Only the QA lane runs Maestro; Feature workers never do (not even `maestro hierarchy`/`studio`) and
# never use `xcrun simctl launch --console-pty` (killing that console host SIGTERMs the app ~1 s after
# launch — it looks like a crash, but is not one). This script uses `xcodebuild test`, not Maestro.
#
# Why the perl wrapper: this Mac has no `timeout` binary. `alarm` survives exec, so the
# xcodebuild child gets the signal and is killed instead of hanging a lane forever.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Slot 1's device, the QA lane's. Override deliberately with IOS_VERIFY_SIM when needed.
DEFAULT_SIM="7CC9393C-88FC-4AE6-88D3-AC68A2E266B7"

WORKSPACE="$ROOT/mobile/iosApp/iosApp.xcworkspace"
SCHEME="Dev"
TEST_TARGET="iosAppTests"
TIMEOUT_SECONDS="${IOS_VERIFY_TIMEOUT:-1400}"

# Disk thresholds (1K blocks).
PURGE_TRIGGER_KB=$((3072 * 1024))      # purge the approved caches below 3 GiB free
MIN_FREE_KB=$((1536 * 1024))           # refuse to build below 1.5 GiB free AFTER the purge
# 5 GiB floor for the archive/release path (documented constant: this test lane never archives).
# shellcheck disable=SC2034
MIN_FREE_ARCHIVE_KB=$((5120 * 1024))
FAKE_FREE_KB="${IOS_VERIFY_FAKE_FREE_KB:-}"

# Build slots.
SLOT_BASE="/tmp"
SLOT1_DIR="$SLOT_BASE/ai-pose-slot-1"
SLOT2_DIR="$SLOT_BASE/ai-pose-slot-2"
SLOT1_SIM="${IOS_VERIFY_SIM:-$DEFAULT_SIM}"
SLOT1_DD="${IOS_VERIFY_DD:-/tmp/dd-shared}"
SLOT2_SIM="${IOS_VERIFY_SIM_2:-}"
SLOT2_DD="/tmp/dd-shared-2"
SLOT_STALE_SECONDS=$((90 * 60))
SLOT_POLL_SECONDS=5
SLOT_ANNOUNCE_SECONDS=15

# Set once a slot is held; released by the EXIT trap.
SLOT_NUMBER=""
SLOT_DIR=""
SIM_ID=""
DERIVED_DATA=""
SIGNALLED=0
CLEANED_UP=0
CHILD_PID=""

CHECK_ENV_ONLY=0
TEST_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --check-env) CHECK_ENV_ONLY=1 ;;
    -h | --help)
      awk 'NR == 1 {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$0"
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

# --- IOS_VERIFY_ONLY_TESTING (R3) ----------------------------------------------------------
# One selector per entry, target-prefixed when the caller passed a bare class or method path.
only_testing_args() {
  local raw="${IOS_VERIFY_ONLY_TESTING:-}" entry
  local -a entries=()
  [[ -n "$raw" ]] || return 0
  IFS=',' read -r -a entries <<<"$raw"
  for entry in ${entries[@]+"${entries[@]}"}; do
    entry="${entry#"${entry%%[![:space:]]*}"}"   # ltrim
    entry="${entry%"${entry##*[![:space:]]}"}"   # rtrim
    [[ -n "$entry" ]] || continue
    entry="${entry#-only-testing:}"
    case "$entry" in
      "$TEST_TARGET" | "$TEST_TARGET"/*) ;;
      *) entry="$TEST_TARGET/$entry" ;;
    esac
    echo "-only-testing:$entry"
  done
}

while IFS= read -r selector; do
  if [[ -n "$selector" ]]; then TEST_ARGS+=("$selector"); fi
done < <(only_testing_args)

fail() {
  echo "ios-verify: $*" >&2
  exit 1
}

fmt_mb() { echo "$(( ${1:-0} / 1024 )) MB"; }

# --- build slots --------------------------------------------------------------------------

slot_field() { # <dir> <field>
  local file="$1/$2"
  [[ -f "$file" ]] && head -1 "$file" 2>/dev/null || true
}

slot_pid_alive() {
  local pid="$1"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

slot_age_seconds() { # <dir> -> seconds since the lock was taken (0 when unknown)
  local started now
  started="$(slot_field "$1" started)"
  if ! [[ "$started" =~ ^[0-9]+$ ]]; then
    started="$(stat -f %m "$1" 2>/dev/null || true)"
  fi
  if ! [[ "$started" =~ ^[0-9]+$ ]]; then
    # Unknown age must never look stale: assume it was taken just now.
    started="$(date +%s)"
  fi
  now="$(date +%s)"
  echo $(( now - started ))
}

slot_stale() { # <dir> -> 0 when the lock may be reclaimed
  local dir="$1" pid age
  pid="$(slot_field "$dir" pid)"
  age="$(slot_age_seconds "$dir")"
  if slot_pid_alive "$pid"; then
    # A holder that has been "building" for over 90 min is either a recycled PID or a wedged
    # process: a build+test pair is capped at ~47 min by IOS_VERIFY_TIMEOUT.
    (( age > SLOT_STALE_SECONDS ))
    return
  fi
  # No PID yet (the creator is a few milliseconds old) or a dead holder. Treat a lock with no PID
  # as stale only after a short grace period so we never rip out a slot mid-creation.
  if [[ -z "$pid" ]]; then
    (( age > 60 ))
    return
  fi
  return 0
}

reclaim_stale_slot() { # <dir> -> 0 when a stale lock was reclaimed
  local dir="$1" stale_dir holder
  [[ -d "$dir" ]] || return 1
  slot_stale "$dir" || return 1
  # Rename first: `mv` on the same filesystem succeeds for exactly one waiter, so two runs can
  # never both delete-and-recreate the same lock and steal each other's slot.
  stale_dir="$dir.reclaim.$$"
  mv "$dir" "$stale_dir" 2>/dev/null || return 1
  holder="$(slot_field "$stale_dir" pid)"
  echo "ios-verify: reclaiming stale build slot lock $(basename "$dir") (holder '${holder:-?}' is gone, or the lock is older than $(( SLOT_STALE_SECONDS / 60 )) min)"
  rm -rf "$stale_dir" 2>/dev/null || true
  return 0
}

try_acquire_slot() { # <n> <dir> <sim> <dd>
  local n="$1" dir="$2" sim="$3" dd="$4"
  if mkdir "$dir" 2>/dev/null; then
    printf '%s\n' "$$" >"$dir/pid"
    date +%s >"$dir/started"
    printf '%s\n' "$sim" >"$dir/sim"
    printf '%s\n' "$dd" >"$dir/dd"
    SLOT_NUMBER="$n"
    SLOT_DIR="$dir"
    SIM_ID="$sim"
    DERIVED_DATA="$dd"
    return 0
  fi
  return 1
}

release_slot() {
  [[ -n "${SLOT_DIR:-}" && -d "${SLOT_DIR:-}" ]] || return 0
  # Only the owner releases: if the lock was reclaimed under us, leave the new holder alone.
  if [[ "$(slot_field "$SLOT_DIR" pid)" == "$$" ]]; then
    rm -rf "$SLOT_DIR" 2>/dev/null || true
  fi
  SLOT_DIR=""
}

describe_slot() { # <n> <dir> -> one human line
  local n="$1" dir="$2" pid sim age
  if [[ ! -d "$dir" ]]; then
    echo "  slot $n: free"
    return
  fi
  pid="$(slot_field "$dir" pid)"
  sim="$(slot_field "$dir" sim)"
  age="$(slot_age_seconds "$dir")"
  echo "  slot $n: held by pid ${pid:-?} on ${sim:-?} for ${age}s"
}

sim_available() { # <udid>
  xcrun simctl list devices available 2>/dev/null | grep -q "$1"
}

acquire_slot() {
  local -a candidates=()
  local -a sims=()
  local -a dds=()
  local forced="${IOS_VERIFY_SLOT:-}"
  local started now waited next_announce n

  if [[ -n "$forced" && "$forced" != 1 && "$forced" != 2 ]]; then
    fail "IOS_VERIFY_SLOT must be 1 or 2 (got '$forced')."
  fi

  sims+=("$SLOT1_SIM")
  dds+=("$SLOT1_DD")

  if [[ -n "$SLOT2_SIM" ]]; then
    if [[ "$SLOT2_SIM" == "$SLOT1_SIM" ]]; then
      fail "IOS_VERIFY_SIM_2 must differ from the slot 1 simulator ($SLOT1_SIM); two slots on one device is not a second lane."
    fi
    sims+=("$SLOT2_SIM")
    dds+=("$SLOT2_DD")
  fi

  for n in "${!sims[@]}"; do
    local idx=$(( n + 1 ))
    if [[ -n "$forced" && "$forced" != "$idx" ]]; then
      continue
    fi
    if ! sim_available "${sims[$n]}"; then
      if [[ -n "$forced" ]]; then
        fail "simulator ${sims[$n]} for slot $idx is not installed/available (IOS_VERIFY_SLOT=$forced)."
      fi
      echo "ios-verify: slot $idx simulator ${sims[$n]} is unavailable — not offering that slot"
      continue
    fi
    candidates+=("$idx:${sims[$n]}:${dds[$n]}")
  done

  if [[ "${#candidates[@]}" -eq 0 ]]; then
    if [[ -n "$forced" ]]; then
      fail "IOS_VERIFY_SLOT=$forced is not usable: slot 2 needs IOS_VERIFY_SIM_2 (slot 1 sim: $SLOT1_SIM)."
    fi
    fail "no usable build slot (simulators checked: ${sims[*]})." \
      "List candidates with 'xcrun simctl list devices available', then set IOS_VERIFY_SIM / IOS_VERIFY_SIM_2."
  fi

  started="$(date +%s)"
  next_announce=$SLOT_ANNOUNCE_SECONDS
  # `looped` is 1 only after a real wait pass, so a second-boundary crossing is never reported as
  # a wait ("acquired after waiting 1s" when it was instant).
  local looped=0
  while true; do
    local reclaimed=0 attempt
    for entry in "${candidates[@]}"; do
      IFS=':' read -r n _sim _dd <<<"$entry"
      local dir
      if [[ "$n" == 1 ]]; then dir="$SLOT1_DIR"; else dir="$SLOT2_DIR"; fi
      for attempt in 1 2; do
        if try_acquire_slot "$n" "$dir" "$_sim" "$_dd"; then
          now="$(date +%s)"
          waited=$(( now - started ))
          if (( looped )); then
            echo "ios-verify: build slot $n acquired after waiting ${waited}s (sim $_sim, DerivedData $_dd)"
          else
            echo "ios-verify: build slot $n acquired (no wait; sim $_sim, DerivedData $_dd)"
          fi
          return 0
        fi
        # One recovery attempt per candidate per pass: reclaim a stale lock, then retry it right
        # away so a freed slot is used before we fall through to the next one.
        if (( attempt == 1 )) && reclaim_stale_slot "$dir"; then
          reclaimed=1
          continue
        fi
        break
      done
    done

    now="$(date +%s)"
    waited=$(( now - started ))
    if (( waited >= next_announce )); then
      echo "ios-verify: still queued for a build slot after ${waited}s (2 slots max on this Mac)"
      for entry in "${candidates[@]}"; do
        IFS=':' read -r n _sim _dd <<<"$entry"
        if [[ "$n" == 1 ]]; then describe_slot 1 "$SLOT1_DIR"; else describe_slot 2 "$SLOT2_DIR"; fi
      done
      next_announce=$(( waited + SLOT_ANNOUNCE_SECONDS ))
    fi
    # A just-reclaimed slot is retried immediately; otherwise poll.
    looped=1
    if (( reclaimed )); then continue; fi
    sleep "$SLOT_POLL_SECONDS"
  done
}

# --- disk: purge then refuse --------------------------------------------------------------

free_kb() {
  if [[ -n "$FAKE_FREE_KB" ]]; then
    echo "$FAKE_FREE_KB"
  else
    df -k / | awk 'NR == 2 {print $4}'
  fi
}

size_kb() { # <path> -> KB on disk (0 when unknown)
  local kb
  kb="$(du -sk "$1" 2>/dev/null | awk 'NR == 1 {print $1}' || true)"
  echo "${kb:-0}"
}

PURGED_KB=0
purge_add() { PURGED_KB=$(( PURGED_KB + ${1:-0} )); }

live_slot_dds() {
  local n dd
  for n in 1 2; do
    local pid dir
    if [[ "$n" == 1 ]]; then dir="$SLOT1_DIR"; else dir="$SLOT2_DIR"; fi
    [[ -d "$dir" ]] || continue
    pid="$(slot_field "$dir" pid)"
    slot_pid_alive "$pid" || continue
    dd="$(slot_field "$dir" dd)"
    if [[ -n "$dd" ]]; then echo "$dd"; fi
  done
}

live_slot_sims() {
  local n dir pid sim
  for n in 1 2; do
    if [[ "$n" == 1 ]]; then dir="$SLOT1_DIR"; else dir="$SLOT2_DIR"; fi
    [[ -d "$dir" ]] || continue
    pid="$(slot_field "$dir" pid)"
    slot_pid_alive "$pid" || continue
    sim="$(slot_field "$dir" sim)"
    if [[ -n "$sim" ]]; then echo "$sim"; fi
  done
}

running_xcodebuild_cmds() {
  local pid
  pgrep -x xcodebuild 2>/dev/null | while read -r pid; do
    ps -o command= -p "$pid" 2>/dev/null
  done || true
}

# The user approved this list once (ledger rule 13 / analysis/OPUS-REVIEW.md §4 R2).
purge_approved_caches() {
  local -a protected_dds=()
  # Both configured slot simulators are off limits, held or not: they are the lanes' devices.
  local -a guarded_sims=()
  [[ -n "$SLOT1_SIM" ]] && guarded_sims+=("$SLOT1_SIM")
  [[ -n "$SLOT2_SIM" ]] && guarded_sims+=("$SLOT2_SIM")
  local d dev tmp_path guarded live_sim kb skip p xb_cmds

  PURGED_KB=0
  echo "ios-verify: free space below $(fmt_mb "$PURGE_TRIGGER_KB") — purging the approved cache list"

  while IFS= read -r d; do
    if [[ -n "$d" ]]; then protected_dds+=("$d"); fi
  done < <(live_slot_dds)
  if [[ -n "${IOS_VERIFY_DD:-}" ]]; then protected_dds+=("${IOS_VERIFY_DD%/}"); fi

  while IFS= read -r live_sim; do
    if [[ -n "$live_sim" ]]; then guarded_sims+=("$live_sim"); fi
  done < <(live_slot_sims)

  xb_cmds="$(running_xcodebuild_cmds)"

  # 1. testmanagerd attachments on every simulator that is not in use. Files younger than 10 min
  #    are left alone: a Maestro run on a sim this script does not hold can still be writing.
  for d in "$HOME"/Library/Developer/CoreSimulator/Devices/*/data/Containers/Data/InternalDaemon/*/Attachments; do
    [[ -d "$d" ]] || continue
    dev="${d#"$HOME"/Library/Developer/CoreSimulator/Devices/}"
    dev="${dev%%/*}"
    skip=0
    for guarded in ${guarded_sims[@]+"${guarded_sims[@]}"}; do
      if [[ "$dev" == "$guarded" ]]; then skip=1; fi
    done
    if (( skip )); then
      continue
    fi
    kb=0
    while IFS= read -r -d '' p; do
      local file_kb
      file_kb="$(size_kb "$p")"
      if rm -rf -- "$p" 2>/dev/null; then
        kb=$(( kb + file_kb ))
      fi
    done < <(find "$d" -mindepth 1 -maxdepth 1 -mmin +10 -print0 2>/dev/null)
    if (( kb > 0 )); then
      purge_add "$kb"
      echo "  purge: simulator attachments ($dev): $(fmt_mb "$kb")"
    fi
  done

  # 2. Maestro xctest-runner scratch dirs older than 10 min.
  tmp_path="${TMPDIR:-/tmp}"
  tmp_path="${tmp_path%/}"
  for d in "$tmp_path"/maestro_xctestrunner_*; do
    [[ -e "$d" ]] || continue
    [[ -n "$(find "$d" -maxdepth 0 -mmin +10 -print 2>/dev/null)" ]] || continue
    kb="$(size_kb "$d")"
    if rm -rf -- "$d" 2>/dev/null; then
      purge_add "$kb"
      echo "  purge: $d: $(fmt_mb "$kb")"
    fi
  done

  # 3. /tmp/dd-* roots that nothing holds. A live slot's DerivedData, and any root named on a live
  #    xcodebuild command line (archive/release path, other lanes), is skipped.
  for d in /tmp/dd-*; do
    [[ -d "$d" ]] || continue
    skip=0
    for p in ${protected_dds[@]+"${protected_dds[@]}"}; do
      case "$p" in "$d" | "$d"/*) skip=1 ;; esac
    done
    if [[ -n "$xb_cmds" ]] && grep -qF -- "$d" <<<"$xb_cmds"; then
      skip=1
    fi
    if (( skip )); then
      echo "  purge: keeping $d (in use by a live slot or a running xcodebuild)"
      continue
    fi
    kb="$(size_kb "$d")"
    if rm -rf -- "$d" 2>/dev/null; then
      purge_add "$kb"
      echo "  purge: $d: $(fmt_mb "$kb")"
    fi
  done

  # 4. Archives/exports that are already uploaded: NOT IMPLEMENTED. The release skill has no
  #    `uploaded` marker convention, so there is no safe way to tell an uploaded archive from one
  #    that is still needed. Add the item only when such a marker exists.

  echo "ios-verify: purge freed $(fmt_mb "$PURGED_KB")"
}

ensure_disk() {
  local free_before free_after real_kb
  free_before="$(free_kb)"
  if [[ -n "$FAKE_FREE_KB" ]]; then
    real_kb="$(df -k / | awk 'NR == 2 {print $4}')"
    echo "ios-verify: free-space reading overridden by IOS_VERIFY_FAKE_FREE_KB ($(fmt_mb "$FAKE_FREE_KB")); real free is $(fmt_mb "${real_kb:-0}")"
  fi

  free_after="$free_before"
  if (( free_before < PURGE_TRIGGER_KB )); then
    purge_approved_caches
    if [[ -n "$FAKE_FREE_KB" ]]; then
      # Faked reading: the purge really ran (the approval list is exclusion-guarded, so it is safe
      # regardless of the number we were given), but the decision uses fake + bytes actually freed.
      free_after=$(( free_before + PURGED_KB ))
      echo "ios-verify: after purge (fake reading + $(fmt_mb "$PURGED_KB") freed) = $(fmt_mb "$free_after") free"
    else
      free_after="$(free_kb)"
      echo "ios-verify: after purge: $(fmt_mb "$free_after") free"
    fi
  fi

  if (( free_after < MIN_FREE_KB )); then
    fail "not enough free disk on / — need >= $(fmt_mb "$MIN_FREE_KB") after the purge, have $(fmt_mb "$free_after")." \
      "The approved caches were already purged. Clear simulator data or an old /tmp/dd-* by hand and retry."
  fi
  echo "disk ok: $(fmt_mb "$free_after") free on / (need >= $(fmt_mb "$MIN_FREE_KB") after purge)"
}

# --- teardown -----------------------------------------------------------------------------

# Dead app containers: every build-for-testing/test run reinstalls the app, and CoreSimulator leaves
# one container per install behind in `com.apple.containermanagerd/Dead`. This Mac runs close to its
# disk floor, so each run drops them — on success **and** on failure (GL rule).
#
# Guarded by construction: only a slot simulator, only that
# `Dead/` directory's contents, and nothing happens when the directory does not exist. Never changes
# the exit status.
cleanup_dead_containers() { # <sim> <status>
  local sim="$1" status="$2" dir before_kb after_kb freed_bytes
  [[ -n "$sim" && ( "$sim" == "$SLOT1_SIM" || "$sim" == "$SLOT2_SIM" ) ]] || return 0
  dir="$HOME/Library/Developer/CoreSimulator/Devices/$sim/data/Library/Caches/com.apple.containermanagerd/Dead"
  [[ -d "$dir" ]] || return 0
  before_kb="$(du -sk "$dir" 2>/dev/null | awk 'NR == 1 {print $1}')"
  find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
  after_kb="$(du -sk "$dir" 2>/dev/null | awk 'NR == 1 {print $1}')"
  freed_bytes=$(( (${before_kb:-0} - ${after_kb:-0}) * 1024 ))
  echo "ios-verify: dead app containers ($sim): $freed_bytes bytes freed"
  return 0
}

kill_children() {
  local child
  for child in $(pgrep -P $$ 2>/dev/null || true); do
    kill -TERM "$child" 2>/dev/null || true
  done
}

# Idempotent: reached from EXIT and from the INT/TERM handler, whichever fires first.
teardown() { # <status>
  local status="$1" waited=0
  (( CLEANED_UP )) && return 0
  CLEANED_UP=1
  if (( SIGNALLED )); then
    echo "ios-verify: interrupted (status $status) — stopping the build and releasing slot ${SLOT_NUMBER:-none}" >&2
  fi
  # A `kill <script>` only signals the shell, so the xcodebuild we started must be taken down
  # before the slot is released: an orphan build would keep writing into a DerivedData that the
  # next slot holder may purge. SIGTERM first, SIGKILL if it does not go in ~2 s.
  if [[ -n "${CHILD_PID:-}" ]] && kill -0 "$CHILD_PID" 2>/dev/null; then
    kill -TERM "$CHILD_PID" 2>/dev/null || true
    while (( waited < 10 )) && kill -0 "$CHILD_PID" 2>/dev/null; do
      sleep 0.2
      waited=$(( waited + 1 ))
    done
    kill -KILL "$CHILD_PID" 2>/dev/null || true
  fi
  kill_children
  release_slot
  cleanup_dead_containers "$SIM_ID" "$status"
  return 0
}

on_exit() {
  local status=$?
  teardown "$status"
  exit "$status"
}

on_signal() { # <code>
  SIGNALLED=1
  teardown "$1"
  exit "$1"
}

trap on_exit EXIT
trap 'on_signal 130' INT
trap 'on_signal 143' TERM

check_env() {
  ensure_disk
  describe_slot 1 "$SLOT1_DIR"
  if [[ -n "$SLOT2_SIM" ]]; then
    describe_slot 2 "$SLOT2_DIR"
  else
    echo "slot 2: disabled (set IOS_VERIFY_SIM_2 to enable the second lane)"
  fi
  local xb_now
  xb_now="$(running_xcodebuild_cmds)"
  if [[ -n "$xb_now" ]]; then
    echo "xcodebuild running (informational, the script queues instead of failing):"
    printf '%s\n' "$xb_now" | awk 'NR <= 3 {print "  " $0}'
  else
    echo "no xcodebuild running machine-wide"
  fi
  echo "simulators: slot 1 = $SLOT1_SIM, slot 2 = ${SLOT2_SIM:-<disabled>}"
}

check_env

if [[ "$CHECK_ENV_ONLY" -eq 1 ]]; then
  echo "ios-verify: env check passed (no build executed)"
  exit 0
fi

[[ -e "$WORKSPACE" ]] || fail "missing workspace $WORKSPACE (run 'cd mobile/iosApp && xcodegen generate')"
command -v xcodebuild >/dev/null || fail "xcodebuild not found — install Xcode and run 'xcode-select -p'"
command -v perl >/dev/null || fail "perl not found — required for the wall-clock guard"

acquire_slot

# Visibility, never a failure (R1): a build started outside the slot system cannot be queued behind,
# so say it out loud instead of silently running two compilers against one machine.
other_builds="$(running_xcodebuild_cmds)"
if [[ -n "$other_builds" ]]; then
  echo "ios-verify: warning — xcodebuild already running outside the slot system (this run will not be serialised behind it):"
  printf '%s\n' "$other_builds" | awk 'NR <= 3 {print "  " $0}'
fi

mkdir -p "$DERIVED_DATA"
LOG_DIR="${TMPDIR:-/tmp}"
# Per-slot log names: two concurrent lanes share $TMPDIR, and a shared log let one run parse the
# other run's output ("executed=unknown", and a green build read from someone else's log).
BUILD_LOG="$LOG_DIR/ios-verify-slot-$SLOT_NUMBER-build.log"
TEST_LOG="$LOG_DIR/ios-verify-slot-$SLOT_NUMBER-test.log"

if [[ "${#TEST_ARGS[@]}" -gt 0 ]]; then
  echo "selection: ${TEST_ARGS[*]}"
fi

run_guarded() {
  local log="$1"
  shift
  # Backgrounded on purpose: a trapped signal interrupts `wait` immediately, so Ctrl-C or
  # `kill <pid>` tears the build down and frees the slot right away. With a foreground child bash
  # defers the handler until xcodebuild finishes, which left the lock and the build alive.
  perl -e 'alarm shift; exec @ARGV' "$TIMEOUT_SECONDS" "$@" >"$log" 2>&1 &
  CHILD_PID=$!
  local status=0
  wait "$CHILD_PID" || status=$?
  CHILD_PID=""
  return "$status"
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

echo "ios-verify: $TEST_RESULT · executed=$EXECUTED · failures=$FAILURES · simulator=$SIM_ID · slot=$SLOT_NUMBER · log=$TEST_LOG"

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
