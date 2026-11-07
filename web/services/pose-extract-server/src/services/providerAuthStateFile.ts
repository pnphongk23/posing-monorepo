import fs from "node:fs/promises";
import path from "node:path";

import { dispatchProviderAuthAlert, type ProviderAlertPayload } from "./providerAlert";

/**
 * Cross-process provider auth state.
 *
 * The API and the worker are two separate Node processes, so an auth failure recorded in the
 * worker's memory is invisible to `/api/health`. This small file next to the credential is the
 * single shared record: timestamps and a code only — never a token, never CLI output.
 */

export const PROVIDER_AUTH_STATE_DIR = "state";
export const PROVIDER_AUTH_STATE_FILE = "provider-auth.json";

/** A repeat of the same alert is suppressed for this long (persisted, so it survives restarts). */
export const PROVIDER_ALERT_DEBOUNCE_MS = 6 * 60 * 60 * 1000;

export interface ProviderAuthState {
  lastAuthErrorAt: string | null;
  lastAuthErrorCode: string | null;
  /** Why the failure was recorded, e.g. "expired" (local detection) or "cli_auth_failure". */
  lastAuthErrorReason: string | null;
  lastSuccessAt: string | null;
  lastAlertAt: string | null;
  lastAlertKey: string | null;
}

export const EMPTY_PROVIDER_AUTH_STATE: ProviderAuthState = {
  lastAuthErrorAt: null,
  lastAuthErrorCode: null,
  lastAuthErrorReason: null,
  lastSuccessAt: null,
  lastAlertAt: null,
  lastAlertKey: null
};

export function providerAuthStatePathFor(credentialsPath: string): string {
  return path.join(path.dirname(credentialsPath), PROVIDER_AUTH_STATE_DIR, PROVIDER_AUTH_STATE_FILE);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isoOrNull(value: unknown): string | null {
  return typeof value === "string" && !Number.isNaN(Date.parse(value)) ? value : null;
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

/** Tolerant read: a missing or corrupt state file means "nothing recorded yet". */
export async function readProviderAuthState(statePath: string): Promise<ProviderAuthState> {
  try {
    const parsed: unknown = JSON.parse(await fs.readFile(statePath, "utf8"));
    if (!isRecord(parsed)) {
      return { ...EMPTY_PROVIDER_AUTH_STATE };
    }
    return {
      lastAuthErrorAt: isoOrNull(parsed.lastAuthErrorAt),
      lastAuthErrorCode: stringOrNull(parsed.lastAuthErrorCode),
      lastAuthErrorReason: stringOrNull(parsed.lastAuthErrorReason),
      lastSuccessAt: isoOrNull(parsed.lastSuccessAt),
      lastAlertAt: isoOrNull(parsed.lastAlertAt),
      lastAlertKey: stringOrNull(parsed.lastAlertKey)
    };
  } catch {
    return { ...EMPTY_PROVIDER_AUTH_STATE };
  }
}

/** Atomic 0600 write (temp file + rename) so a reader never sees a half-written record. */
export async function writeProviderAuthState(statePath: string, state: ProviderAuthState): Promise<boolean> {
  const tempPath = `${statePath}.tmp.${process.pid}.${Math.random().toString(16).slice(2)}`;
  try {
    await fs.mkdir(path.dirname(statePath), { recursive: true, mode: 0o700 });
    await fs.writeFile(tempPath, `${JSON.stringify(state)}\n`, { mode: 0o600 });
    await fs.chmod(tempPath, 0o600);
    await fs.rename(tempPath, statePath);
    return true;
  } catch {
    await fs.rm(tempPath, { force: true }).catch(() => undefined);
    return false;
  }
}

let stateWriteQueue: Promise<unknown> = Promise.resolve();

/** Serialise read-modify-write inside the process so one record cannot drop another's field. */
function updateProviderAuthState(
  statePath: string,
  mutate: (current: ProviderAuthState) => ProviderAuthState
): Promise<ProviderAuthState> {
  const run = stateWriteQueue.then(async () => {
    const next = mutate(await readProviderAuthState(statePath));
    await writeProviderAuthState(statePath, next);
    return next;
  });
  stateWriteQueue = run.then(
    () => undefined,
    () => undefined
  );
  return run;
}

export async function recordProviderAuthFailure(input: {
  statePath: string;
  code?: string;
  reason?: string;
  nowMs?: number;
}): Promise<ProviderAuthState> {
  const nowMs = input.nowMs ?? Date.now();
  return updateProviderAuthState(input.statePath, (current) => ({
    ...current,
    lastAuthErrorAt: new Date(nowMs).toISOString(),
    lastAuthErrorCode: input.code ?? "PROVIDER_AUTH_REQUIRED",
    lastAuthErrorReason: input.reason ?? "cli_auth_failure"
  }));
}

export async function recordProviderAuthSuccess(input: {
  statePath: string;
  nowMs?: number;
}): Promise<ProviderAuthState> {
  const nowMs = input.nowMs ?? Date.now();
  return updateProviderAuthState(input.statePath, (current) => ({
    ...current,
    lastSuccessAt: new Date(nowMs).toISOString()
  }));
}

export interface DispatchAlertOnceDeps {
  statePath: string;
  payload: ProviderAlertPayload;
  nowMs?: number;
  env?: Record<string, string | undefined>;
  fetchImpl?: typeof fetch;
  debounceMs?: number;
}

/**
 * Send at most one alert per transition window. The debounce lives in the state file, so a
 * restart or a second process cannot re-send it.
 */
export async function dispatchProviderAuthAlertOnce(deps: DispatchAlertOnceDeps): Promise<boolean> {
  const nowMs = deps.nowMs ?? Date.now();
  const debounceMs = deps.debounceMs ?? PROVIDER_ALERT_DEBOUNCE_MS;
  const current = await readProviderAuthState(deps.statePath);
  const key = `${deps.payload.status}:${deps.payload.state}`;

  if (current.lastAlertKey === key && current.lastAlertAt !== null) {
    const lastAtMs = Date.parse(current.lastAlertAt);
    if (!Number.isNaN(lastAtMs) && nowMs - lastAtMs < debounceMs) {
      return false;
    }
  }

  const sent = await dispatchProviderAuthAlert(deps.payload, {
    env: deps.env,
    fetchImpl: deps.fetchImpl,
    now: () => nowMs,
    debounce: false
  });
  if (!sent) {
    return false;
  }

  await updateProviderAuthState(deps.statePath, (latest) => ({
    ...latest,
    lastAlertAt: new Date(nowMs).toISOString(),
    lastAlertKey: key
  }));
  return true;
}
