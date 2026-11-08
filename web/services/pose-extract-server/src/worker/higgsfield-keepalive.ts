import { logger } from "../utils/logger";
import {
  backupCredential,
  readCredentialSnapshot,
  withCredentialLock,
  type CredentialSnapshot
} from "../services/higgsfieldCredentialGuard";
import {
  REFRESH_WINDOW_SEC,
  isHiggsfieldSelfRefreshEnabled,
  refreshCredentials,
  type RefreshResult
} from "../services/higgsfieldSelfRefresh";
import type { ProviderAlertPayload } from "../services/providerAlert";
import {
  dispatchProviderAuthAlertOnce,
  providerAuthStatePathFor,
  recordProviderAuthFailure,
  recordProviderAuthSuccess
} from "../services/providerAuthStateFile";

/**
 * Worker-side credential owner for Higgsfield.
 *
 * Two modes, chosen by `HIGGSFIELD_SELF_REFRESH`:
 *
 * 1. **Self-refresh on** (`1|true`): once the token has one hour or less left, the worker refreshes
 *    it itself, inside the shared credential mutex, and re-reads the file after taking the lock (a
 *    job's CLI spawn may have rotated it while we waited). On failure it leaves `credentials.json`
 *    untouched, records `PROVIDER_AUTH_REQUIRED` with a `refresh_<reason>` and alerts once. Success
 *    is backed up and recorded. This makes the worker the only writer of `credentials.json`, so no
 *    CLI spawn and no tick can ever rotate the same refresh token twice.
 *
 * 2. **Self-refresh off** (default): detect-only. The CLI does not refresh on its own
 *    (owner-confirmed) and running `higgsfield account status` on an expired token would only make
 *    the CLI delete the credential file and possibly burn the refresh token, so this side never
 *    spawns the CLI: it records the expiry in the shared state file (PROVIDER_AUTH_REQUIRED, reason
 *    "expired") and lets the existing health/alert path report it.
 */

export const DEFAULT_INTERVAL_MS = 15 * 60 * 1000;
/** At most one detection per hour, so a long-expired credential cannot flood the log. */
export const FAILURE_BACKOFF_MS = 60 * 60 * 1000;

export type KeepaliveTickResult = "disabled" | "skipped" | "expired" | "refreshed" | "refresh_failed";

/**
 * Refresh failures that a retry cannot fix: the stored refresh token is dead, unreadable or
 * malformed, so the next attempt waits an hour instead of hammering the token endpoint.
 */
const PERMANENT_REFRESH_FAILURES = new Set(["invalid_grant", "invalid_credentials", "read_error"]);

export interface RefreshFailureInput {
  statePath: string;
  nowMs: number;
  reason: string;
  expiresInSec: number;
  env?: Record<string, string | undefined>;
}

export interface HiggsfieldKeepaliveDeps {
  credentialsPath: string;
  statePath?: string;
  env?: Record<string, string | undefined>;
  now?: () => number;
  intervalMs?: number;
  readSnapshot?: (credentialsPath: string, nowMs: number) => Promise<CredentialSnapshot>;
  /** Test seam: the default records the expiry in the state file and dispatches the alert. */
  recordExpiry?: (input: {
    statePath: string;
    nowMs: number;
    expiresInSec: number;
    env?: Record<string, string | undefined>;
  }) => Promise<void>;
  /** Test seam: defaults to `refreshCredentials`. Always called inside `lock`. */
  refresh?: (credentialsPath: string) => Promise<RefreshResult>;
  /** Test seam: defaults to the process-wide credential mutex. */
  lock?: <T>(task: () => Promise<T>) => Promise<T>;
  /** Test seam: defaults to the atomic 0600 credential backup. Runs inside `lock`, after a refresh. */
  backup?: (input: { credentialsPath: string }) => Promise<unknown>;
  /** Test seam: defaults to `recordProviderAuthSuccess`. */
  recordRefreshSuccess?: (input: { statePath: string; nowMs: number }) => Promise<unknown>;
  /** Test seam: defaults to recording the failure and dispatching the alert once. */
  recordRefreshFailure?: (input: RefreshFailureInput) => Promise<void>;
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
  env?: Record<string, string | undefined>;
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
  await dispatchProviderAuthAlertOnce({
    statePath: input.statePath,
    payload,
    nowMs: input.nowMs,
    env: input.env
  });
}

async function defaultRecordRefreshFailure(input: RefreshFailureInput): Promise<void> {
  await recordProviderAuthFailure({
    statePath: input.statePath,
    code: "PROVIDER_AUTH_REQUIRED",
    reason: `refresh_${input.reason}`,
    nowMs: input.nowMs
  });
  // Reason and remaining lifetime only: never a token, never a response body.
  const payload: ProviderAlertPayload = {
    event: "provider_auth",
    status: "degraded",
    state: "refresh_failed",
    expiresInSec: input.expiresInSec
  };
  await dispatchProviderAuthAlertOnce({
    statePath: input.statePath,
    payload,
    nowMs: input.nowMs,
    env: input.env
  });
}

type SelfRefreshOutcome =
  | { kind: "skipped" }
  | { kind: "refreshed"; expiresAt: number }
  | { kind: "failed"; reason: string; expiresInSec: number };

function hasUsableExpiry(snapshot: CredentialSnapshot): snapshot is CredentialSnapshot & { expiresInSec: number } {
  return snapshot.state !== "missing" && snapshot.state !== "invalid" && snapshot.expiresInSec !== null;
}

export function startHiggsfieldKeepalive(deps: HiggsfieldKeepaliveDeps): HiggsfieldKeepaliveHandle {
  const env = deps.env ?? process.env;
  const now = deps.now ?? Date.now;
  const intervalMs = deps.intervalMs ?? DEFAULT_INTERVAL_MS;
  const readSnapshot = deps.readSnapshot ?? readCredentialSnapshot;
  const recordExpiry = deps.recordExpiry ?? ((input) => defaultRecordExpiry({ ...input, env }));
  const refresh = deps.refresh ?? ((credentialsPath: string) => refreshCredentials({ credentialsPath, now }));
  const lock = deps.lock ?? withCredentialLock;
  const backup = deps.backup ?? backupCredential;
  const recordRefreshSuccess = deps.recordRefreshSuccess ?? recordProviderAuthSuccess;
  const recordRefreshFailure = deps.recordRefreshFailure ?? ((input) => defaultRecordRefreshFailure({ ...input, env }));
  const statePath = deps.statePath ?? providerAuthStatePathFor(deps.credentialsPath);
  const enabled = isHiggsfieldKeepaliveEnabled(env);
  const selfRefreshEnabled = isHiggsfieldSelfRefreshEnabled(env);

  let nextAllowedAtMs = 0;
  let stopped = false;
  let running = false;

  /**
   * Refresh decision + call. Everything that reads or writes the credential happens inside the
   * mutex: no CLI spawn can be refreshing the same refresh token at the same time.
   */
  const runSelfRefresh = async (): Promise<SelfRefreshOutcome> => {
    try {
      return await lock<SelfRefreshOutcome>(async () => {
        // Re-read under the lock: a job's CLI spawn may have rotated the file while we waited.
        const fresh = await readSnapshot(deps.credentialsPath, now());
        if (!hasUsableExpiry(fresh) || fresh.expiresInSec > REFRESH_WINDOW_SEC) {
          return { kind: "skipped" };
        }
        const result = await refresh(deps.credentialsPath);
        if (!result.ok) {
          return { kind: "failed", reason: result.reason, expiresInSec: fresh.expiresInSec };
        }
        // Back up the refreshed credential before the CLI can delete/rewrite it, so a later CLI
        // refresh failure is recoverable.
        await backup({ credentialsPath: deps.credentialsPath });
        return { kind: "refreshed", expiresAt: result.expiresAt };
      });
    } catch (error) {
      return {
        kind: "failed",
        reason: error instanceof Error && error.message === "write_error" ? "write_error" : "internal_error",
        expiresInSec: 0
      };
    }
  };

  const selfRefreshTick = async (): Promise<KeepaliveTickResult> => {
    const outcome = await runSelfRefresh();

    if (outcome.kind === "skipped") {
      return "skipped";
    }

    if (outcome.kind === "refreshed") {
      nextAllowedAtMs = 0;
      try {
        await recordRefreshSuccess({ statePath, nowMs: now() });
      } catch (error) {
        logger.warn(
          { message: error instanceof Error ? error.message : "unknown error" },
          "higgsfield self-refresh could not record the success"
        );
      }
      logger.info({ expiresAt: outcome.expiresAt }, "higgsfield credential refreshed by the worker");
      return "refreshed";
    }

    // The credential file is left exactly as it was: no rewrite, no delete, no restore.
    // This failure is the only record written even when the token had already expired — the health
    // endpoint is degraded by it, and a second "expired" record would only duplicate the alert.
    nextAllowedAtMs = PERMANENT_REFRESH_FAILURES.has(outcome.reason) ? now() + FAILURE_BACKOFF_MS : 0;
    try {
      await recordRefreshFailure({
        statePath,
        nowMs: now(),
        reason: outcome.reason,
        expiresInSec: outcome.expiresInSec
      });
    } catch (error) {
      logger.warn(
        { message: error instanceof Error ? error.message : "unknown error" },
        "higgsfield self-refresh could not record the failure"
      );
    }
    logger.warn({ reason: outcome.reason }, "higgsfield self-refresh failed; re-login may be required");
    return "refresh_failed";
  };

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
    if (!hasUsableExpiry(snapshot)) {
      // Nothing to work with: a missing or unreadable file needs a human, not a CLI call.
      return "skipped";
    }

    if (selfRefreshEnabled) {
      // Only the last hour of the token's life (expired included) justifies a refresh.
      if (snapshot.expiresInSec > REFRESH_WINDOW_SEC) {
        return "skipped";
      }
      running = true;
      try {
        return await selfRefreshTick();
      } finally {
        running = false;
      }
    }

    // Detect-only: nothing happens before `expires_at`, so the refresh token stays untouched.
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
