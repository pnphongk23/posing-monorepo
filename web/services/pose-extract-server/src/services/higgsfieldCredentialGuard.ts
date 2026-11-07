import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

/**
 * Higgsfield CLI credential guard.
 *
 * The CLI keeps its OAuth credentials in a single JSON file (`credentials.json`) whose
 * `expires_at` is an **epoch-seconds number**. Two behaviours of the CLI drive this module:
 *
 * 1. It refreshes the access token on its own once `expires_at` is roughly two minutes away,
 *    writing the rotated refresh token back into the same file.
 * 2. When a refresh fails it **deletes the credential file** and leaves `credentials.json.lock`
 *    behind, so the only copy of the refresh token is gone.
 *
 * Everything here therefore reads the file, never returns or logs token material, and keeps an
 * atomic 0600 backup so a destructive refresh failure is recoverable.
 */

/** Below this remaining lifetime the credential is reported as expiring soon. */
export const EXPIRING_SOON_SEC = 24 * 60 * 60;

export const BACKUP_DIR_NAME = "backup";
export const BACKUP_FILE_NAME = "credentials.latest.json";

export type CredentialState = "ok" | "expiring_soon" | "expired" | "missing" | "invalid";

export interface CredentialSnapshot {
  state: CredentialState;
  /** Seconds until `expires_at`; negative when expired, null when unknown. */
  expiresInSec: number | null;
  /** Raw `expires_at` epoch seconds; null when the file is missing or unparseable. */
  expiresAtSec: number | null;
  /** File mtime in ms, used only to break expiry ties when deciding a backup. */
  mtimeMs: number | null;
}

const MISSING_SNAPSHOT: CredentialSnapshot = {
  state: "missing",
  expiresInSec: null,
  expiresAtSec: null,
  mtimeMs: null
};

const INVALID_SNAPSHOT: CredentialSnapshot = {
  state: "invalid",
  expiresInSec: null,
  expiresAtSec: null,
  mtimeMs: null
};

/** `HIGGSFIELD_CREDENTIALS_PATH` wins; otherwise the CLI default under `$HOME/.config`. */
export function defaultCredentialsPath(
  env: Record<string, string | undefined> = process.env,
  homedir?: string
): string {
  const configured = env.HIGGSFIELD_CREDENTIALS_PATH?.trim();
  if (configured) {
    return configured;
  }
  const home = homedir ?? env.HOME?.trim() ?? os.homedir();
  return path.join(home, ".config", "higgsfield", "credentials.json");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Read the credential file into a token-free snapshot. Only `state`, the expiry and the mtime
 * leave this function: the access/refresh tokens are parsed but never returned.
 */
export async function readCredentialSnapshot(
  credentialsPath: string,
  nowMs: number = Date.now()
): Promise<CredentialSnapshot> {
  let raw: string;
  let mtimeMs: number;
  try {
    const stat = await fs.stat(credentialsPath);
    mtimeMs = stat.mtimeMs;
    raw = await fs.readFile(credentialsPath, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      return MISSING_SNAPSHOT;
    }
    return INVALID_SNAPSHOT;
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return INVALID_SNAPSHOT;
  }

  if (!isRecord(parsed) || typeof parsed.expires_at !== "number" || !Number.isFinite(parsed.expires_at)) {
    return { ...INVALID_SNAPSHOT, mtimeMs };
  }

  const nowSec = Math.floor(nowMs / 1000);
  const expiresAtSec = parsed.expires_at;
  const expiresInSec = Math.floor(expiresAtSec - nowSec);
  const state: CredentialState =
    expiresInSec <= 0 ? "expired" : expiresInSec < EXPIRING_SOON_SEC ? "expiring_soon" : "ok";

  return { state, expiresInSec, expiresAtSec, mtimeMs };
}

export function backupPathFor(credentialsPath: string): string {
  return path.join(path.dirname(credentialsPath), BACKUP_DIR_NAME, BACKUP_FILE_NAME);
}

export interface BackupResult {
  written: boolean;
  backupPath: string;
  /** Why the backup was skipped; absent when written. */
  skipped?: "unusable-credential" | "not-newer" | "write-failed";
}

/**
 * Copy the credential to `<dir>/backup/credentials.latest.json` atomically (temp file + rename,
 * mode 0600). Only a parseable credential that is newer than the existing backup overwrites it,
 * so a stale or corrupt file can never replace the last known-good copy.
 */
export async function backupCredential(input: {
  credentialsPath: string;
  nowMs?: number;
}): Promise<BackupResult> {
  const { credentialsPath, nowMs = Date.now() } = input;
  const backupPath = backupPathFor(credentialsPath);
  const snapshot = await readCredentialSnapshot(credentialsPath, nowMs);

  if (snapshot.state === "missing" || snapshot.state === "invalid" || snapshot.expiresAtSec === null) {
    return { written: false, backupPath, skipped: "unusable-credential" };
  }

  const existing = await readCredentialSnapshot(backupPath, nowMs);
  const existingExpiry = existing.expiresAtSec;
  const existingMtime = existing.mtimeMs ?? 0;
  const isNewer =
    existingExpiry === null ||
    snapshot.expiresAtSec > existingExpiry ||
    (snapshot.expiresAtSec === existingExpiry && (snapshot.mtimeMs ?? 0) > existingMtime);

  if (!isNewer) {
    return { written: false, backupPath, skipped: "not-newer" };
  }

  const tempPath = `${backupPath}.tmp.${process.pid}.${Math.random().toString(16).slice(2)}`;
  try {
    await fs.mkdir(path.dirname(backupPath), { recursive: true, mode: 0o700 });
    const contents = await fs.readFile(credentialsPath);
    await fs.writeFile(tempPath, contents, { mode: 0o600 });
    await fs.chmod(tempPath, 0o600);
    await fs.rename(tempPath, backupPath);
    return { written: true, backupPath };
  } catch {
    await fs.rm(tempPath, { force: true }).catch(() => undefined);
    return { written: false, backupPath, skipped: "write-failed" };
  }
}

/**
 * Put the last backup back when the CLI deleted the credential file. Returns true only when a
 * restore actually happened, so the caller can report the destructive refresh failure.
 */
export async function restoreCredential(input: { credentialsPath: string }): Promise<boolean> {
  const { credentialsPath } = input;
  const backupPath = backupPathFor(credentialsPath);

  try {
    await fs.stat(credentialsPath);
    return false;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") {
      return false;
    }
  }

  let contents: Buffer;
  try {
    contents = await fs.readFile(backupPath);
  } catch {
    return false;
  }

  const tempPath = `${credentialsPath}.restore.${process.pid}.${Math.random().toString(16).slice(2)}`;
  try {
    await fs.writeFile(tempPath, contents, { mode: 0o600 });
    await fs.chmod(tempPath, 0o600);
    await fs.rename(tempPath, credentialsPath);
    return true;
  } catch {
    await fs.rm(tempPath, { force: true }).catch(() => undefined);
    return false;
  }
}

let credentialQueue: Promise<unknown> = Promise.resolve();

/**
 * Single credential owner: every CLI spawn runs through this queue so two commands can never
 * refresh the same refresh token concurrently (the loser of that race would get `invalid_grant`
 * and the CLI would delete the credential file).
 */
export function withCredentialLock<T>(task: () => Promise<T>): Promise<T> {
  const run = credentialQueue.then(task, task);
  credentialQueue = run.then(
    () => undefined,
    () => undefined
  );
  return run;
}
