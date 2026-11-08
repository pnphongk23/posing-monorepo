import { randomBytes } from "node:crypto";
import { open, readFile, rename, rm } from "node:fs/promises";
import path from "node:path";

const TOKEN_ENDPOINT = "https://clerk.higgsfield.ai/oauth/token";
const CLIENT_ID = "sRGCQJvvJkPrrtRj";

/** The token is refreshed no earlier than this, so a live token is never rotated for nothing. */
export const REFRESH_WINDOW_SEC = 60 * 60;

/** Hard ceiling on the token request so a stalled socket cannot wedge the credential mutex. */
export const DEFAULT_REFRESH_TIMEOUT_MS = 15_000;

/**
 * Attempts to persist a freshly rotated token. Clerk has already rotated it by then, so the only
 * safe move is to keep retrying the local write from memory — never to POST again.
 */
const WRITE_ATTEMPTS = 3;

/** Pause between write attempts; overridable so tests do not wait on wall-clock time. */
export const WRITE_RETRY_DELAY_MS = 1_000;

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
  /** Pause between local write attempts after a rotated token was received. */
  writeRetryDelayMs?: number;
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

/**
 * Prove the credential can be written *before* the token is rotated. Create, fsync and rename a
 * throwaway file inside the credential's own directory (a read-only or full volume, or a single-file
 * bind mount where rename gives EBUSY, is then a plain `write_error` with no rotation to lose).
 */
async function probeWritable(credentialsPath: string): Promise<boolean> {
  const directory = path.dirname(credentialsPath);
  const suffix = `${process.pid}.${randomBytes(8).toString("hex")}`;
  const probePath = path.join(directory, `.${path.basename(credentialsPath)}.${suffix}.probe.tmp`);
  const probeTarget = path.join(directory, `.${path.basename(credentialsPath)}.${suffix}.probe`);
  let file;
  try {
    file = await open(probePath, "wx", 0o600);
    await file.writeFile("probe", "utf8");
    await file.sync();
    await file.close();
    file = undefined;
    await rename(probePath, probeTarget);
    await rm(probeTarget, { force: true });
    return true;
  } catch {
    if (file) await file.close().catch(() => undefined);
    await rm(probePath, { force: true }).catch(() => undefined);
    await rm(probeTarget, { force: true }).catch(() => undefined);
    return false;
  }
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => {
    const timer = setTimeout(resolve, ms);
    // A pending retry must never keep the process alive on its own.
    (timer as { unref?: () => void }).unref?.();
  });
}

/**
 * Persist a rotated token, retrying only the local write. `write_error_after_rotation` is terminal:
 * the refresh token on disk is the old one and Clerk has already rotated it, so POSTing it again
 * would burn it (`invalid_grant`).
 */
async function writeRotated(
  credentialsPath: string,
  contents: string,
  retryDelayMs: number
): Promise<RefreshResult | null> {
  for (let attempt = 1; attempt <= WRITE_ATTEMPTS; attempt += 1) {
    try {
      await writeAtomic(credentialsPath, contents);
      return null;
    } catch {
      if (attempt < WRITE_ATTEMPTS) {
        await delay(retryDelayMs);
      }
    }
  }
  return { ok: false, reason: "write_error_after_rotation" };
}

/** Refresh OAuth credentials in place; token values never leave this module's file/request path. */
export async function refreshCredentials({
  credentialsPath,
  fetchImpl = globalThis.fetch,
  now = Date.now,
  timeoutMs = DEFAULT_REFRESH_TIMEOUT_MS,
  writeRetryDelayMs = WRITE_RETRY_DELAY_MS
}: RefreshCredentialsInput): Promise<RefreshResult> {
  let credentials: unknown;
  try {
    credentials = JSON.parse(await readFile(credentialsPath, "utf8"));
  } catch {
    return { ok: false, reason: "read_error" };
  }
  if (!isCredentials(credentials)) return { ok: false, reason: "invalid_credentials" };

  // Never rotate the token on a volume that cannot take the result back.
  if (!(await probeWritable(credentialsPath))) {
    return { ok: false, reason: "write_error" };
  }

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
    // The 200 may already have rotated the refresh token: never POST again.
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

  const writeFailure = await writeRotated(
    credentialsPath,
    `${JSON.stringify(updated, null, 2)}\n`,
    writeRetryDelayMs
  );
  if (writeFailure) {
    return writeFailure;
  }
  return { ok: true, expiresAt, refreshed: true };
}
