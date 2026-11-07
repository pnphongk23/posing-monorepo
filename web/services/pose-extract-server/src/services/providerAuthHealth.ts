import { logger as defaultLogger } from "../utils/logger";
import {
  defaultCredentialsPath,
  readCredentialSnapshot,
  type CredentialSnapshot,
  type CredentialState
} from "./higgsfieldCredentialGuard";
import type { ProviderAlertPayload } from "./providerAlert";
import {
  dispatchProviderAuthAlertOnce,
  providerAuthStatePathFor,
  readProviderAuthState,
  type ProviderAuthState
} from "./providerAuthStateFile";

/**
 * Provider (Higgsfield CLI) authentication health.
 *
 * The app never owns the OAuth token; it reports what the credential file says plus what the
 * worker recorded in the shared state file (`<credential dir>/state/provider-auth.json`). The API
 * and the worker are separate processes, so the file — not process memory — is the source of
 * truth. Nothing here logs or returns token material.
 */

export type ProviderAuthStateName = CredentialState | "not_configured";

export interface ProviderAuthHealth {
  /** True when a credential path is configured (env) or a credential file is present. */
  enabled: boolean;
  state: ProviderAuthStateName;
  expiresInSec: number | null;
  lastAuthError: { at: string; code: string } | null;
  lastSuccessAt: string | null;
}

export type OverallHealthStatus = "ok" | "warn" | "degraded";

/**
 * How long an expired access token may sit unrefreshed before the deployment is called out.
 * The token only lives 24h and the CLI refreshes it on its next call, so a token that expired an
 * hour ago is normal; one that has been expired for two days means nobody (no job, no keepalive)
 * has managed to refresh it.
 */
export const EXPIRED_WARN_AFTER_SEC = 48 * 60 * 60;

/** An auth error recorded after the last successful CLI call is still an open failure. */
function hasOpenAuthError(state: ProviderAuthState): boolean {
  if (!state.lastAuthErrorAt) {
    return false;
  }
  if (!state.lastSuccessAt) {
    return true;
  }
  return Date.parse(state.lastAuthErrorAt) > Date.parse(state.lastSuccessAt);
}

export function overallStatusFor(health: ProviderAuthHealth): OverallHealthStatus {
  if (!health.enabled) {
    return "ok";
  }
  if (health.state === "missing" || health.state === "invalid") {
    return "degraded";
  }
  if (health.lastAuthError && (health.lastSuccessAt === null || Date.parse(health.lastAuthError.at) > Date.parse(health.lastSuccessAt))) {
    return "degraded";
  }
  // A 24h token is expiring every day; warning on that alone would alert forever. Only an expiry
  // that nobody refreshed for two days is worth a (non-alerting) warning.
  if (health.state === "expired" && health.expiresInSec !== null && health.expiresInSec <= -EXPIRED_WARN_AFTER_SEC) {
    return "warn";
  }
  return "ok";
}

interface HealthLogger {
  error: (...args: unknown[]) => void;
  warn?: (...args: unknown[]) => void;
}

export interface EvaluateProviderAuthHealthDeps {
  env?: Record<string, string | undefined>;
  now?: () => number;
  readSnapshot?: (credentialsPath: string, nowMs: number) => Promise<CredentialSnapshot>;
  readState?: (statePath: string) => Promise<ProviderAuthState>;
  logger?: HealthLogger;
  dispatchAlert?: (payload: ProviderAlertPayload) => Promise<boolean>;
}

let lastReportedStatus: OverallHealthStatus | null = null;

/** Test seam: forget the transition memory used for one-shot logging/alerts. */
export function resetProviderAuthHealthMemory(): void {
  lastReportedStatus = null;
}

/**
 * Read the credential file and the shared worker state. Never throws: a health endpoint that
 * throws would let a credential problem take the API down.
 */
export async function evaluateProviderAuthHealth(
  deps: EvaluateProviderAuthHealthDeps = {}
): Promise<ProviderAuthHealth> {
  const env = deps.env ?? process.env;
  const now = deps.now ?? Date.now;
  const logger = deps.logger ?? defaultLogger;
  const nowMs = now();
  const configuredPath = env.HIGGSFIELD_CREDENTIALS_PATH?.trim();
  const credentialsPath = configuredPath || defaultCredentialsPath(env);
  const statePath = providerAuthStatePathFor(credentialsPath);

  let snapshot: CredentialSnapshot;
  try {
    const readSnapshot = deps.readSnapshot ?? readCredentialSnapshot;
    snapshot = await readSnapshot(credentialsPath, nowMs);
  } catch {
    snapshot = { state: "invalid", expiresInSec: null, expiresAtSec: null, mtimeMs: null };
  }

  let record: ProviderAuthState;
  try {
    const readState = deps.readState ?? readProviderAuthState;
    record = await readState(statePath);
  } catch {
    record = {
      lastAuthErrorAt: null,
      lastAuthErrorCode: null,
      lastSuccessAt: null,
      lastAlertAt: null,
      lastAlertKey: null
    };
  }

  const enabled = Boolean(configuredPath) || snapshot.state !== "missing";
  const health: ProviderAuthHealth = {
    enabled,
    state: enabled ? snapshot.state : "not_configured",
    expiresInSec: enabled ? snapshot.expiresInSec : null,
    lastAuthError: hasOpenAuthError(record) && record.lastAuthErrorAt
      ? { at: record.lastAuthErrorAt, code: record.lastAuthErrorCode ?? "PROVIDER_AUTH_REQUIRED" }
      : null,
    lastSuccessAt: record.lastSuccessAt
  };

  const status = overallStatusFor(health);
  if (status !== lastReportedStatus) {
    if (status === "degraded") {
      logger.error(
        {
          providerState: health.state,
          expiresInSec: health.expiresInSec,
          lastAuthErrorCode: health.lastAuthError?.code ?? null
        },
        "higgsfield provider authentication is degraded"
      );
      await dispatchAlert({ status: "degraded", state: health.state, expiresInSec: health.expiresInSec, statePath, nowMs, env, deps });
    } else if (status === "warn") {
      // Informational only: no webhook, no error-level log, because a stale expiry usually just
      // means no job has run since the token lapsed.
      const warn = logger.warn?.bind(logger) ?? logger.error;
      warn(
        { providerState: health.state, expiresInSec: health.expiresInSec },
        "higgsfield credential has been expired for more than 48h without a successful refresh"
      );
    }
    lastReportedStatus = status;
  }

  return health;
}

async function dispatchAlert(input: {
  status: "degraded";
  state: string;
  expiresInSec: number | null;
  statePath: string;
  nowMs: number;
  env: Record<string, string | undefined>;
  deps: EvaluateProviderAuthHealthDeps;
}): Promise<void> {
  const payload: ProviderAlertPayload = {
    event: "provider_auth",
    status: input.status,
    state: input.state,
    expiresInSec: input.expiresInSec
  };
  try {
    if (input.deps.dispatchAlert) {
      await input.deps.dispatchAlert(payload);
      return;
    }
    await dispatchProviderAuthAlertOnce({
      statePath: input.statePath,
      payload,
      nowMs: input.nowMs,
      env: input.env
    });
  } catch {
    // Alerting must never break the health endpoint.
  }
}
