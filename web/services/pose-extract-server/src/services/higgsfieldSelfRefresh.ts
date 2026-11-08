import { randomBytes } from "node:crypto";
import { open, readFile, rename, rm } from "node:fs/promises";
import path from "node:path";

import { defaultCredentialsPath } from "./higgsfieldCredentialGuard";

const TOKEN_ENDPOINT = "https://clerk.higgsfield.ai/oauth/token";
const CLIENT_ID = "sRGCQJvvJkPrrtRj";

/** The token is refreshed no earlier than this, so a live token is never rotated for nothing. */
export const REFRESH_WINDOW_SEC = 60 * 60;

/** Hard ceiling on the token request so a stalled socket cannot wedge the credential mutex. */
export const DEFAULT_REFRESH_TIMEOUT_MS = 15_000;

/**
 * Self-refresh is opt-in: only `HIGGSFIELD_SELF_REFRESH=1|true` (any casing) turns it on. Unset,
 * empty, `0`, `false` or anything else leaves the worker on the detect-only path.
 */
export function isHiggsfieldSelfRefreshEnabled(
  env: Record<string, string | undefined> = process.env
): boolean {
  return /^(1|true)$/i.test(env.HIGGSFIELD_SELF_REFRESH?.trim() ?? "");
}

export type RefreshResult =
  | { ok: true; expiresAt: number; refreshed: true }
  | { ok: false; reason: string };

interface Credentials {
  access_token: string;
  refresh_token: string;
  expires_at: number;
  [field: string]: unknown;
}

export interface RefreshCredentialsInput {
  credentialsPath: string;
  fetchImpl?: typeof fetch;
  /** Current time in milliseconds since epoch. */
  now?: () => number;
  /** Abort the token request after this long; the failure is reported as `network_error`. */
  timeoutMs?: number;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isCredentials(value: unknown): value is Credentials {
  return isRecord(value) &&
    typeof value.access_token === "string" && value.access_token.length > 0 &&
    typeof value.refresh_token === "string" && value.refresh_token.length > 0 &&
    typeof value.expires_at === "number" && Number.isFinite(value.expires_at);
}

async function writeAtomic(credentialsPath: string, contents: string): Promise<void> {
  const directory = path.dirname(credentialsPath);
  const tempPath = path.join(
    directory,
    `.${path.basename(credentialsPath)}.${process.pid}.${randomBytes(8).toString("hex")}.tmp`
  );
  let file;
  try {
    file = await open(tempPath, "wx", 0o600);
    await file.chmod(0o600);
    await file.writeFile(contents, "utf8");
    await file.sync();
    await file.close();
    file = undefined;
    await rename(tempPath, credentialsPath);
  } catch {
    if (file) await file.close().catch(() => undefined);
    await rm(tempPath, { force: true }).catch(() => undefined);
    throw new Error("write_error");
  }
}

/** Refresh OAuth credentials in place; token values never leave this module's file/request path. */
export async function refreshCredentials({
  credentialsPath,
  fetchImpl = globalThis.fetch,
  now = Date.now,
  timeoutMs = DEFAULT_REFRESH_TIMEOUT_MS
}: RefreshCredentialsInput): Promise<RefreshResult> {
  let credentials: unknown;
  try {
    credentials = JSON.parse(await readFile(credentialsPath, "utf8"));
  } catch {
    return { ok: false, reason: "read_error" };
  }
  if (!isCredentials(credentials)) return { ok: false, reason: "invalid_credentials" };

  const body = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: credentials.refresh_token,
    client_id: CLIENT_ID
  });
  // The signal aborts the request itself; the race also covers an implementation that ignores it,
  // so a stalled endpoint can never hold the credential mutex past the timeout.
  const signal = AbortSignal.timeout(Number.isFinite(timeoutMs) && timeoutMs > 0 ? timeoutMs : DEFAULT_REFRESH_TIMEOUT_MS);
  let response: Response;
  try {
    const timedOut = new Promise<never>((_, reject) => {
      signal.addEventListener("abort", () => reject(new Error("timeout")), { once: true });
    });
    response = await Promise.race([
      fetchImpl(TOKEN_ENDPOINT, {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: body.toString(),
        signal
      }),
      timedOut
    ]);
  } catch {
    return { ok: false, reason: "network_error" };
  }
  if (response.status !== 200) {
    if (response.status === 400) {
      try {
        const errorBody: unknown = await response.json();
        if (isRecord(errorBody) && errorBody.error === "invalid_grant") {
          return { ok: false, reason: "invalid_grant" };
        }
      } catch {
        // The response body is intentionally not surfaced or logged.
      }
    }
    return { ok: false, reason: "http_error" };
  }

  let tokenResponse: unknown;
  try {
    tokenResponse = await response.json();
  } catch {
    return { ok: false, reason: "invalid_response" };
  }
  if (!isRecord(tokenResponse) || typeof tokenResponse.access_token !== "string" ||
      tokenResponse.access_token.length === 0 || typeof tokenResponse.expires_in !== "number" ||
      !Number.isFinite(tokenResponse.expires_in) || tokenResponse.expires_in <= 0) {
    return { ok: false, reason: "invalid_response" };
  }

  const expiresAt = Math.floor(now() / 1000) + tokenResponse.expires_in;
  const updated: Credentials = {
    ...credentials,
    access_token: tokenResponse.access_token,
    refresh_token: typeof tokenResponse.refresh_token === "string" && tokenResponse.refresh_token.length > 0
      ? tokenResponse.refresh_token
      : credentials.refresh_token,
    expires_at: expiresAt
  };
  for (const field of ["token_type", "expires_in", "scope"] as const) {
    if (tokenResponse[field] !== undefined) updated[field] = tokenResponse[field];
  }

  try {
    await writeAtomic(credentialsPath, `${JSON.stringify(updated, null, 2)}\n`);
  } catch {
    return { ok: false, reason: "write_error" };
  }
  return { ok: true, expiresAt, refreshed: true };
}

/**
 * Ad-hoc entry point (CLI/one-off use). Disabled by default and only refreshes inside the one-hour
 * expiry window. The worker does not call this: its keepalive tick runs `refreshCredentials` inside
 * the shared credential mutex, which is what makes the worker the single writer of the file.
 */
export async function maybeSelfRefresh(options: {
  credentialsPath?: string;
  fetchImpl?: typeof fetch;
  now?: () => number;
  env?: Record<string, string | undefined>;
} = {}): Promise<RefreshResult | { ok: true; expiresAt: number; refreshed: false }> {
  const env = options.env ?? process.env;
  if (!isHiggsfieldSelfRefreshEnabled(env)) {
    return { ok: false, reason: "disabled" };
  }
  const credentialsPath = options.credentialsPath ?? defaultCredentialsPath(env);
  const now = options.now ?? Date.now;
  let credentials: unknown;
  try {
    credentials = JSON.parse(await readFile(credentialsPath, "utf8"));
  } catch {
    return { ok: false, reason: "read_error" };
  }
  if (!isCredentials(credentials)) return { ok: false, reason: "invalid_credentials" };
  const expiresAt = credentials.expires_at;
  if (expiresAt - Math.floor(now() / 1000) > REFRESH_WINDOW_SEC) {
    return { ok: true, expiresAt, refreshed: false };
  }
  return refreshCredentials({ credentialsPath, fetchImpl: options.fetchImpl, now });
}
