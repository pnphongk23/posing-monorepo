import { logger } from "../utils/logger";
import { readCredentialSnapshot, type CredentialSnapshot } from "../services/higgsfieldCredentialGuard";

/**
 * Worker-side credential *detector* for Higgsfield.
 *
 * The CLI does not refresh on its own (owner-confirmed), and a 24h access token that nobody checks
 * only reveals itself when a real user runs a job. This timer therefore only **detects**: once the
 * access token has actually expired it runs one `account status` through the guarded path (mutex,
 * backup, shared auth state) and records the outcome.
 *
 * It never writes, restores or repairs `credentials.json` — the file stays exactly as the CLI left
 * it. Writing the credential will be the job of the self-refresh scheduler in a follow-up change,
 * which must remain the single owner of the file.
 */

export const DEFAULT_INTERVAL_MS = 15 * 60 * 1000;
/** At most one attempt per hour after a failure, so a broken credential cannot hammer the CLI. */
export const FAILURE_BACKOFF_MS = 60 * 60 * 1000;

export type KeepaliveTickResult = "disabled" | "skipped" | "busy" | "detected" | "auth_failed" | "failed";

export interface AccountStatusResult {
  ok: boolean;
  authFailure: boolean;
}

export interface HiggsfieldKeepaliveDeps {
  credentialsPath: string;
  /** Runs `account status` through the credential guard; resolves null when the lock is taken. */
  tryCheckAccountStatus: () => Promise<AccountStatusResult | null>;
  env?: Record<string, string | undefined>;
  now?: () => number;
  intervalMs?: number;
  readSnapshot?: (credentialsPath: string, nowMs: number) => Promise<CredentialSnapshot>;
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

export function startHiggsfieldKeepalive(deps: HiggsfieldKeepaliveDeps): HiggsfieldKeepaliveHandle {
  const env = deps.env ?? process.env;
  const now = deps.now ?? Date.now;
  const intervalMs = deps.intervalMs ?? DEFAULT_INTERVAL_MS;
  const readSnapshot = deps.readSnapshot ?? readCredentialSnapshot;
  const enabled = isHiggsfieldKeepaliveEnabled(env);

  let nextAllowedAtMs = 0;
  let stopped = false;
  let running = false;

  const tick = async (): Promise<KeepaliveTickResult> => {
    if (!enabled || stopped) {
      return "disabled";
    }
    if (running) {
      return "busy";
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
    // Detector only: nothing touches the credential before `expires_at`, so the refresh token stays
    // untouched until it is actually needed.
    if (snapshot.expiresInSec > 0) {
      return "skipped";
    }

    running = true;
    try {
      const result = await deps.tryCheckAccountStatus();
      if (result === null) {
        return "busy";
      }
      if (result.ok) {
        nextAllowedAtMs = 0;
        logger.info(
          { expiresInSec: snapshot.expiresInSec },
          "higgsfield keepalive detector confirmed the credential against the API"
        );
        return "detected";
      }
      nextAllowedAtMs = now() + FAILURE_BACKOFF_MS;
      if (result.authFailure) {
        return "auth_failed";
      }
      return "failed";
    } catch (error) {
      nextAllowedAtMs = now() + FAILURE_BACKOFF_MS;
      logger.warn(
        { message: error instanceof Error ? error.message : "unknown error" },
        "higgsfield keepalive detector threw"
      );
      return "failed";
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
