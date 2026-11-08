#!/usr/bin/env bash
# Higgsfield credential health probe (S1).
#
# Exit codes:
#   0  credential valid and the Higgsfield API answered
#   2  authentication problem: credential missing/unreadable/expired, or the CLI reported an auth
#      failure (not authenticated / session expired / invalid credentials / older auth flow /
#      unauthorized)
#   3  credential still valid but expires in less than 24 hours (re-login window)
#   1  anything else: CLI or node missing, network error, timeout, unknown CLI failure
#
# Rules this probe follows, learned from @higgsfield/cli@1.1.23:
#   * `higgsfield auth token` only reads the file locally and therefore proves nothing — the
#     server round-trip is `higgsfield account status`.
#   * An expired access token makes the CLI try a refresh; when that refresh fails the CLI
#     DELETES credentials.json and leaves credentials.json.lock behind. The probe therefore never
#     calls the CLI with an already-expired credential, and it takes an atomic backup before any
#     call.
#   * The probe never restores: restoring is the worker guard's job, so a probe can never overwrite
#     a credential that a job or a human just put back.
#
# No token material is ever printed: only the state, the remaining lifetime and the names of the
# fields that failed validation.
set -uo pipefail

EXPIRING_SOON_SEC="${HIGGSFIELD_EXPIRING_SOON_SEC:-86400}"
CREDENTIALS_PATH="${HIGGSFIELD_CREDENTIALS_PATH:-$HOME/.config/higgsfield/credentials.json}"
export HIGGSFIELD_CREDENTIALS_PATH="$CREDENTIALS_PATH"
CREDENTIALS_DIR="$(dirname "$CREDENTIALS_PATH")"
BACKUP_DIR="$CREDENTIALS_DIR/backup"
BACKUP_PATH="$BACKUP_DIR/credentials.latest.json"

log() { printf 'PROBE: %s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

# Reads the credential exactly once, validates it, backs up those same bytes, then prints
# "<state> <expiresInSec>" or "invalid - <missing fields>".
prepare_credential() {
  node -e '
    const fs = require("fs");
    const path = require("path");
    const [credPath, backupPath, expiringRaw] = [process.argv[1], process.argv[2], process.argv[3]];
    const expiring = Number(expiringRaw);
    const nowSec = Math.floor(Date.now() / 1000);

    let bytes;
    try {
      bytes = fs.readFileSync(credPath);
    } catch (_) {
      process.stdout.write("invalid - unreadable\n");
      process.exit(0);
    }

    let parsed;
    try {
      parsed = JSON.parse(bytes.toString("utf8"));
    } catch (_) {
      process.stdout.write("invalid - json\n");
      process.exit(0);
    }

    const missing = [];
    if (!parsed || typeof parsed.access_token !== "string" || parsed.access_token.length === 0) missing.push("access_token");
    if (!parsed || typeof parsed.refresh_token !== "string" || parsed.refresh_token.length === 0) missing.push("refresh_token");
    if (!parsed || typeof parsed.expires_at !== "number" || !Number.isFinite(parsed.expires_at)) missing.push("expires_at");
    if (missing.length > 0) {
      process.stdout.write("invalid - " + missing.join(",") + "\n");
      process.exit(0);
    }

    // Backup the bytes that were just validated, and only when they are newer than the backup.
    const expiryOf = (file) => {
      try {
        const raw = JSON.parse(fs.readFileSync(file, "utf8"));
        return raw && typeof raw.expires_at === "number" ? raw.expires_at : null;
      } catch (_) {
        return null;
      }
    };
    const mtimeOf = (file) => {
      try { return fs.statSync(file).mtimeMs; } catch (_) { return -1; }
    };
    const backupExpiry = expiryOf(backupPath);
    const newer =
      backupExpiry === null ||
      parsed.expires_at > backupExpiry ||
      (parsed.expires_at === backupExpiry && mtimeOf(credPath) > mtimeOf(backupPath));
    if (newer) {
      try {
        fs.mkdirSync(path.dirname(backupPath), { recursive: true, mode: 0o700 });
        const tmp = backupPath + ".tmp." + process.pid;
        fs.writeFileSync(tmp, bytes, { mode: 0o600 });
        fs.chmodSync(tmp, 0o600);
        fs.renameSync(tmp, backupPath);
      } catch (_) {
        process.stdout.write("invalid - backup_failed\n");
        process.exit(0);
      }
    }

    const left = Math.floor(parsed.expires_at - nowSec);
    const state = left <= 0 ? "expired" : left < expiring ? "expiring_soon" : "ok";
    process.stdout.write(state + " " + left + "\n");
  ' "$CREDENTIALS_PATH" "$BACKUP_PATH" "$EXPIRING_SOON_SEC" 2>/dev/null || printf 'invalid - node_failed\n'
}

command -v node >/dev/null 2>&1 || { err "node is required by the credential probe"; exit 1; }
command -v higgsfield >/dev/null 2>&1 || { err "higgsfield CLI not found on PATH"; exit 1; }

if [ ! -f "$CREDENTIALS_PATH" ]; then
  err "credentials file missing at $CREDENTIALS_PATH (a human must run 'higgsfield auth login' and upload it)"
  exit 2
fi

read -r state detail <<<"$(prepare_credential)"
case "$state" in
  ok | expiring_soon | expired) ;;
  *)
    err "credentials file at $CREDENTIALS_PATH is not a usable Higgsfield credential (missing or bad: ${detail:-unknown})"
    exit 2
    ;;
esac

if [ "$state" = "expired" ]; then
  # Refreshing here is the CLI's destructive path: a rejected refresh deletes the file.
  err "access token expired ${detail}s ago; re-login required (the CLI would delete the credential on a failed refresh)"
  exit 2
fi

log "checking account with the Higgsfield API (credential state=$state expiresInSec=$detail)"
# Keep stderr (it carries the CLI's verdict) and drop stdout, which can contain account details.
account_error="$(higgsfield account status 2>&1 >/dev/null)"
account_exit=$?
if [ "$account_exit" -ne 0 ]; then
  account_error_lower="$(printf '%s' "$account_error" | tr '[:upper:]' '[:lower:]')"
  case "$account_error_lower" in
    *"not authenticated"* | *"session expired"* | *"invalid credentials"* | *"older auth flow"* | *"unauthorized"*)
      err "higgsfield account status reported an authentication failure (exit $account_exit)"
      exit 2
      ;;
    *)
      err "higgsfield account status failed with exit $account_exit but that is not an authentication failure"
      exit 1
      ;;
  esac
fi

if [ "$state" = "expiring_soon" ]; then
  err "credential expires in ${detail}s (< ${EXPIRING_SOON_SEC}s); re-login and upload a fresh file"
  exit 3
fi

log "account status OK; credential valid for ${detail}s"
exit 0
