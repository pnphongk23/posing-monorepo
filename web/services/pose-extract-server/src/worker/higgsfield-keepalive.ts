import { logger } from "../utils/logger";
import { readCredentialSnapshot, type CredentialSnapshot } from "../services/higgsfieldCredentialGuard";
import type { ProviderAlertPayload } from "../services/providerAlert";
import {
  dispatchProviderAuthAlertOnce,
  providerAuthStatePathFor,
  recordProviderAuthFailure
} from "../services/providerAuthStateFile";

/**
 * Worker-side credential *detector* for Higgsfield.
 *
 * The CLI does not refresh on its own (owner-confirmed). Once the access token has actually
 * expired, running `higgsfield account status` would only make the CLI delete the credential file
 * and possibly burn the refresh token, so this detector never spawns the CLI: it records the
 * expiry in the shared state file (PROVIDER_AUTH_REQUIRED, reason "expired") and lets the existing
 * health/alert path report it. A later successful job clears the state through `lastSuccessAt`.
 *
 * It never writes, restores or repairs `credentials.json`. Writing the credential is the job of the
 * self-refresh scheduler in a follow-up change, which must remain the single owner of the file.
 */

export const DEFAULT_INTERVAL_MS = 15 * 60 * 1000;
/** At most one detection per hour, so a long-expired credential cannot flood the log. */
export const FAILURE_BACKOFF_MS = 60 * 60 * 1000;

export type KeepaliveTickResult = "disabled" | "skipped" | "expired";

export interface HiggsfieldKeepaliveDeps {
  credentialsPath: string;
  statePath?: string;
  env?: Record<string, string | undefined>;
  now?: () => number;
  intervalMs?: number;
  readSnapshot?: (credentialsPath: string, nowMs: number) => Promise<CredentialSnapshot>;
  /** Test seam: the default records the expiry in the state file and dispatches the alert. */
  recordExpiry?: (input: { statePath: string; nowMs: number; expiresInSec: number }) => Promise<void>;
  setIntervalImpl?: (handler: () => void, intervalMs: number) => ReturnType<typeof setInterval>;
  clearIntervalImpl?: (handle: ReturnType<typeof setInterval>) => void;
}

export interface HiggsfieldKeepaliveHandle {
  tick(): Promise<KeepaliveTickResult>;
  stop(): void;
}

const DISABLED_VALUES = new Set(["0", "false", "off", "no", "disabled"]);

export function isHiggsfieldKeepaliveEnabled(env: Record<string, string | undefined> = process.env): boolean {
  const raw = env.HIGGSFIELD_KEEPALIVE?.trim().toLowerCase();
  if (!raw) {
    return true;
  }
  return !DISABLED_VALUES.has(raw);
}

async function defaultRecordExpiry(input: {
  statePath: string;
  nowMs: number;
  expiresInSec: number;
}): Promise<void> {
  await recordProviderAuthFailure({
    statePath: input.statePath,
    code: "PROVIDER_AUTH_REQUIRED",
    reason: "expired",
    nowMs: input.nowMs
  });
  const payload: ProviderAlertPayload = {
    event: "provider_auth",
    status: "degraded",
    state: "expired",
    expiresInSec: input.expiresInSec
  };
  await dispatchProviderAuthAlertOnce({ statePath: input.statePath, payload, nowMs: input.nowMs });
}

export function startHiggsfieldKeepalive(deps: HiggsfieldKeepaliveDeps): HiggsfieldKeepaliveHandle {
  const env = deps.env ?? process.env;
  const now = deps.now ?? Date.now;
  const intervalMs = deps.intervalMs ?? DEFAULT_INTERVAL_MS;
  const readSnapshot = deps.readSnapshot ?? readCredentialSnapshot;
  const recordExpiry = deps.recordExpiry ?? defaultRecordExpiry;
  const statePath = deps.statePath ?? providerAuthStatePathFor(deps.credentialsPath);
  const enabled = isHiggsfieldKeepaliveEnabled(env);

  let nextAllowedAtMs = 0;
  let stopped = false;
  let running = false;

  const tick = async (): Promise<KeepaliveTickResult> => {
    if (!enabled || stopped) {
      return "disabled";
    }
    if (running) {
      return "skipped";
    }
    const nowMs = now();
    if (nowMs < nextAllowedAtMs) {
      return "skipped";
    }

    const snapshot = await readSnapshot(deps.credentialsPath, nowMs);
    if (snapshot.state === "missing" || snapshot.state === "invalid" || snapshot.expiresInSec === null) {
      // Nothing to detect against: a missing or unreadable file needs a human, not a CLI call.
      return "skipped";
    }
    // Detector only: nothing happens before `expires_at`, so the refresh token stays untouched
    // until a human (or the future self-refresh scheduler) needs it.
    if (snapshot.expiresInSec > 0) {
      return "skipped";
    }

    running = true;
    try {
      await recordExpiry({ statePath, nowMs, expiresInSec: snapshot.expiresInSec });
      nextAllowedAtMs = now() + FAILURE_BACKOFF_MS;
      logger.warn(
        { expiresInSec: snapshot.expiresInSec },
        "higgsfield detector recorded an expired credential; re-login required"
      );
      return "expired";
    } catch (error) {
      nextAllowedAtMs = now() + FAILURE_BACKOFF_MS;
      logger.warn(
        { message: error instanceof Error ? error.message : "unknown error" },
        "higgsfield detector could not record the expiry"
      );
      return "skipped";
    } finally {
      running = false;
    }
  };

  const setIntervalImpl = deps.setIntervalImpl ?? setInterval;
  const clearIntervalImpl = deps.clearIntervalImpl ?? clearInterval;
  const timer = setIntervalImpl(() => {
    void tick();
  }, intervalMs);
  // The timer must never keep the worker process alive on its own.
  (timer as { unref?: () => void }).unref?.();

  return {
    tick,
    stop(): void {
      stopped = true;
      clearIntervalImpl(timer);
    }
  };
}
