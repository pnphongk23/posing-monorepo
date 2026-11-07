import { logger } from "../utils/logger";

/**
 * Optional, opt-in alerting for provider authentication health.
 *
 * `ALERT_WEBHOOK_URL` is absent by default: nothing is sent and nothing is required. When it is
 * set, a short JSON body (state and remaining lifetime only — never token material) is POSTed on
 * a health transition. Repeats of the same transition are debounced so a failing probe cannot
 * flood the webhook.
 */

export const ALERT_DEBOUNCE_MS = 6 * 60 * 60 * 1000;

export interface ProviderAlertPayload {
  event: "provider_auth";
  status: "warn" | "degraded";
  state: string;
  expiresInSec: number | null;
}

export interface DispatchProviderAlertDeps {
  env?: Record<string, string | undefined>;
  fetchImpl?: typeof fetch;
  now?: () => number;
}

let lastSentKey: string | null = null;
let lastSentAtMs: number | null = null;

/** Test seam: forget the debounce memory. */
export function resetProviderAlertState(): void {
  lastSentKey = null;
  lastSentAtMs = null;
}

/**
 * Returns true only when a request was attempted and accepted. Every failure path is swallowed:
 * alerting must never turn a health check into an error.
 */
export async function dispatchProviderAuthAlert(
  payload: ProviderAlertPayload,
  deps: DispatchProviderAlertDeps = {}
): Promise<boolean> {
  const env = deps.env ?? process.env;
  const url = env.ALERT_WEBHOOK_URL?.trim();
  if (!url) {
    return false;
  }

  const now = deps.now ?? Date.now;
  const nowMs = now();
  const key = `${payload.event}:${payload.status}:${payload.state}`;
  if (lastSentKey === key && lastSentAtMs !== null && nowMs - lastSentAtMs < ALERT_DEBOUNCE_MS) {
    return false;
  }

  const body = JSON.stringify({
    event: payload.event,
    status: payload.status,
    state: payload.state,
    expiresInSec: payload.expiresInSec,
    at: new Date(nowMs).toISOString()
  });

  try {
    const fetchImpl = deps.fetchImpl ?? fetch;
    const response = await fetchImpl(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body
    });
    if (!response.ok) {
      logger.warn({ status: response.status, state: payload.state }, "provider auth alert webhook rejected the payload");
      return false;
    }
    lastSentKey = key;
    lastSentAtMs = nowMs;
    return true;
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown error";
    logger.warn({ message, state: payload.state }, "provider auth alert webhook failed");
    return false;
  }
}
