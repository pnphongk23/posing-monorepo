#!/usr/bin/env bash
# Higgsfield credential health probe (S1).
#
# Exit codes:
#   0  credential valid and the Higgsfield API answered
#   2  authentication problem: credential missing/unreadable/expired, or the API rejected it
#   3  credential still valid but expires in less than 24 hours (re-login window)
#   1  anything else (CLI or node missing, unexpected failure)
#
# Rules this probe follows, learned from @higgsfield/cli@1.1.23:
#   * `higgsfield auth token` only reads the file locally and therefore proves nothing — the
#     server round-trip is `higgsfield account status`.
#   * An expired access token makes the CLI try a refresh; when that refresh fails the CLI
#     DELETES credentials.json and leaves credentials.json.lock behind. So the probe backs the
#     file up before any CLI call, never calls the CLI with an already-expired credential, and
#     restores the backup if the CLI removed the file.
#
# No token material is ever printed: only the state and the remaining lifetime.
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

# Prints "<state> <expiresInSec>"; state is one of ok|expiring_soon|expired|invalid.
read_credential_state() {
  node -e '
    const fs = require("fs");
    const file = process.argv[1];
    const expiring = Number(process.argv[2]);
    const nowSec = Math.floor(Date.now() / 1000);
    let state = "invalid";
    let left = "-";
    try {
      const raw = JSON.parse(fs.readFileSync(file, "utf8"));
      if (raw && typeof raw.expires_at === "number" && Number.isFinite(raw.expires_at)) {
        left = String(Math.floor(raw.expires_at - nowSec));
        state = Number(left) <= 0 ? "expired" : Number(left) < expiring ? "expiring_soon" : "ok";
      }
    } catch (_) {
      state = "invalid";
    }
    process.stdout.write(state + " " + left + "\n");
  ' "$1" "$EXPIRING_SOON_SEC" 2>/dev/null || printf 'invalid -\n'
}

# Atomic 0600 backup; skips unparseable or older credentials so a stale file cannot win.
backup_credential() {
  node -e '
    const fs = require("fs");
    const path = require("path");
    const [credPath, backupPath] = [process.argv[1], process.argv[2]];
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
    const currentExpiry = expiryOf(credPath);
    if (currentExpiry === null) process.exit(0);
    const backupExpiry = expiryOf(backupPath);
    const newer =
      backupExpiry === null ||
      currentExpiry > backupExpiry ||
      (currentExpiry === backupExpiry && mtimeOf(credPath) > mtimeOf(backupPath));
    if (!newer) process.exit(0);
    fs.mkdirSync(path.dirname(backupPath), { recursive: true, mode: 0o700 });
    const tmp = backupPath + ".tmp." + process.pid;
    fs.writeFileSync(tmp, fs.readFileSync(credPath), { mode: 0o600 });
    fs.chmodSync(tmp, 0o600);
    fs.renameSync(tmp, backupPath);
  ' "$CREDENTIALS_PATH" "$BACKUP_PATH" 2>/dev/null
  return 0
}

# Restores the backup when the CLI deleted the credential. Returns 0 when it restored.
restore_credential() {
  [ -f "$CREDENTIALS_PATH" ] && return 1
  [ -f "$BACKUP_PATH" ] || return 1
  node -e '
    const fs = require("fs");
    const [backupPath, credPath] = [process.argv[1], process.argv[2]];
    const tmp = credPath + ".restore." + process.pid;
    fs.writeFileSync(tmp, fs.readFileSync(backupPath), { mode: 0o600 });
    fs.chmodSync(tmp, 0o600);
    fs.renameSync(tmp, credPath);
  ' "$BACKUP_PATH" "$CREDENTIALS_PATH" 2>/dev/null
}

command -v node >/dev/null 2>&1 || { err "node is required by the credential probe"; exit 1; }
command -v higgsfield >/dev/null 2>&1 || { err "higgsfield CLI not found on PATH"; exit 1; }

if [ ! -f "$CREDENTIALS_PATH" ]; then
  err "credentials file missing at $CREDENTIALS_PATH (a human must run 'higgsfield auth login' and upload it)"
  exit 2
fi

read -r state left <<<"$(read_credential_state "$CREDENTIALS_PATH")"
case "$state" in
  ok | expiring_soon | expired) ;;
  *)
    err "credentials file at $CREDENTIALS_PATH is not a usable Higgsfield credential"
    exit 2
    ;;
esac

if [ "$state" = "expired" ]; then
  # Refreshing here is the CLI's destructive path: a rejected refresh deletes the file.
  err "access token expired ${left}s ago; re-login required (the CLI would delete the credential on a failed refresh)"
  exit 2
fi

backup_credential

log "checking account with the Higgsfield API (credential state=$state expiresInSec=$left)"
if ! higgsfield account status >/dev/null; then
  if restore_credential; then
    warn "restored credentials from backup after the CLI removed the file"
  fi
  err "higgsfield account status failed; the stored credential is no longer accepted"
  exit 2
fi

if [ "$state" = "expiring_soon" ]; then
  err "credential expires in ${left}s (< ${EXPIRING_SOON_SEC}s); re-login and upload a fresh file"
  exit 3
fi

log "account status OK; credential valid for ${left}s"
exit 0
