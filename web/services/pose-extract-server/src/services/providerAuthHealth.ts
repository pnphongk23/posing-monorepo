import { logger as defaultLogger } from "../utils/logger";
import {
  defaultCredentialsPath,
  readCredentialSnapshot,
  type CredentialSnapshot,
  type CredentialState
} from "./higgsfieldCredentialGuard";
import { dispatchProviderAuthAlert, type ProviderAlertPayload } from "./providerAlert";

/**
 * Provider (Higgsfield CLI) authentication health.
 *
 * The app never owns the OAuth token; it only reports what the credential file says plus whether
 * the last CLI invocation was rejected. Nothing here logs or returns token material.
 */

export type ProviderAuthState = CredentialState | "not_configured";

export interface ProviderAuthHealth {
  /** True when a credential path is configured (env) or a credential file is present. */
  enabled: boolean;
  state: ProviderAuthState;
  expiresInSec: number | null;
  lastAuthError: { at: string; code: string } | null;
}

export type OverallHealthStatus = "ok" | "warn" | "degraded";

interface LastAuthErrorRecord {
  atMs: number;
  code: string;
}

let lastAuthError: LastAuthErrorRecord | null = null;
let lastReportedStatus: OverallHealthStatus | null = null;

export function recordProviderAuthFailure(input: { code?: string; nowMs?: number } = {}): void {
  lastAuthError = {
    atMs: input.nowMs ?? Date.now(),
    code: input.code ?? "PROVIDER_AUTH_REQUIRED"
  };
}

export function recordProviderAuthSuccess(): void {
  lastAuthError = null;
}

export function getLastProviderAuthError(): { at: string; code: string } | null {
  if (!lastAuthError) {
    return null;
  }
  return { at: new Date(lastAuthError.atMs).toISOString(), code: lastAuthError.code };
}

/** Test seam: clear both the recorded failure and the transition memory. */
export function resetProviderAuthState(): void {
  lastAuthError = null;
  lastReportedStatus = null;
}

export function overallStatusFor(health: ProviderAuthHealth): OverallHealthStatus {
  if (health.lastAuthError) {
    return "degraded";
  }
  if (!health.enabled) {
    return "ok";
  }
  switch (health.state) {
    case "expired":
    case "missing":
    case "invalid":
      return "degraded";
    case "expiring_soon":
      return "warn";
    default:
      return "ok";
  }
}

interface HealthLogger {
  error: (...args: unknown[]) => void;
}

export interface EvaluateProviderAuthHealthDeps {
  env?: Record<string, string | undefined>;
  now?: () => number;
  readSnapshot?: (credentialsPath: string, nowMs: number) => Promise<CredentialSnapshot>;
  logger?: HealthLogger;
  dispatchAlert?: (payload: ProviderAlertPayload) => Promise<boolean>;
}

/**
 * Read the credential file and fold it together with the last CLI auth failure. Never throws: a
 * health endpoint that throws would let a credential problem take the API down.
 */
export async function evaluateProviderAuthHealth(
  deps: EvaluateProviderAuthHealthDeps = {}
): Promise<ProviderAuthHealth> {
  const env = deps.env ?? process.env;
  const now = deps.now ?? Date.now;
  const logger = deps.logger ?? defaultLogger;
  const dispatchAlert = deps.dispatchAlert ?? ((payload: ProviderAlertPayload) => dispatchProviderAuthAlert(payload));
  const nowMs = now();
  const configuredPath = env.HIGGSFIELD_CREDENTIALS_PATH?.trim();
  const credentialsPath = configuredPath || defaultCredentialsPath(env);

  let snapshot: CredentialSnapshot;
  try {
    const readSnapshot = deps.readSnapshot ?? readCredentialSnapshot;
    snapshot = await readSnapshot(credentialsPath, nowMs);
  } catch {
    snapshot = { state: "invalid", expiresInSec: null, expiresAtSec: null, mtimeMs: null };
  }

  const enabled = Boolean(configuredPath) || snapshot.state !== "missing";
  const health: ProviderAuthHealth = {
    enabled,
    state: enabled ? snapshot.state : "not_configured",
    expiresInSec: enabled ? snapshot.expiresInSec : null,
    lastAuthError: getLastProviderAuthError()
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
      await dispatchAlert({ event: "provider_auth", status: "degraded", state: health.state, expiresInSec: health.expiresInSec });
    } else if (status === "warn") {
      logger.error(
        { providerState: health.state, expiresInSec: health.expiresInSec },
        "higgsfield provider credential expires within 24h; re-login before jobs start failing"
      );
      await dispatchAlert({ event: "provider_auth", status: "warn", state: health.state, expiresInSec: health.expiresInSec });
    }
    lastReportedStatus = status;
  }

  return health;
}
