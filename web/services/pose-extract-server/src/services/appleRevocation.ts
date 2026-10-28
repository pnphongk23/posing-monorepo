import { createPrivateKey, createSign, type KeyObject } from "node:crypto";

/**
 * Sign in with Apple token revocation (App Store guideline 5.1.1(v)).
 *
 * The app stores no Apple token: at deletion time iOS sends a fresh authorization code, this
 * module trades it for Apple's refresh token and revokes it before any of our data is deleted.
 * Nothing here logs, throws or returns a secret: errors carry a stage name only.
 */
export const APPLE_ISSUER = "https://appleid.apple.com";
export const APPLE_TOKEN_EXCHANGE_URL = "https://appleid.apple.com/auth/token";
export const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";
/**
 * Apple rejects a client secret valid for more than six months. Five minutes is enough for one
 * exchange plus one revoke and bounds what a leaked assertion is worth.
 */
export const APPLE_CLIENT_SECRET_TTL_SECONDS = 300;
export const APPLE_REQUEST_TIMEOUT_MS = 5_000;

/** The four values that only Railway holds. Referenced by env name, never by value. */
export interface AppleSignInConfig {
  teamId: string;
  clientId: string;
  keyId: string;
  privateKey: string;
}

/**
 * `reauth_required` means the user's authorization code was refused (expired or already used), which a
 * fresh code can fix. `identity_mismatch` means the code belongs to a different Apple account, so
 * revoking it would leave this account's grant alive.
 */
export type AppleRevocationResult =
  | { outcome: "revoked" }
  | { outcome: "reauth_required"; reason: "invalid_grant" }
  | { outcome: "identity_mismatch" };

/**
 * Transport or upstream failure: nothing is known about the tokens, so callers must not delete.
 * `appleError` carries Apple's own error code (`invalid_client`, `invalid_request`, …) — a token
 * from Apple's error vocabulary, never a code, secret or token — so ops can tell our misconfiguration
 * apart from a user-side refusal.
 */
export class AppleRevocationError extends Error {
  readonly stage: "token_exchange" | "revoke";
  readonly appleError?: string;

  constructor(stage: "token_exchange" | "revoke", appleError?: string) {
    super(stage === "token_exchange" ? "Apple token exchange failed" : "Apple token revocation failed");
    this.name = "AppleRevocationError";
    this.stage = stage;
    this.appleError = appleError;
  }
}

export interface AppleRevocationOptions {
  authorizationCode: string;
  /** `sub` of the Apple identity Supabase recorded for this account. */
  appleSub: string;
  config: AppleSignInConfig;
  fetchImpl?: typeof fetch;
  now?: () => number;
  timeoutMs?: number;
}

export interface AppleClientSecretOptions {
  config: AppleSignInConfig;
  /** Seconds since the epoch; the JWT's `iat`. */
  issuedAt?: number;
  ttlSeconds?: number;
}

function base64url(value: string | Buffer): string {
  return Buffer.from(value).toString("base64url");
}

/**
 * Railway stores the key as a single-line value, so the PEM newlines usually arrive escaped.
 * Accept both spellings: a malformed key has to fail here, not inside Apple's 400.
 */
function normalizePrivateKey(privateKey: string): KeyObject {
  const pem = privateKey.includes("\\n") ? privateKey.replace(/\\n/g, "\n") : privateKey;
  return createPrivateKey(pem);
}

/**
 * The ES256 client secret Apple expects: `iss` is the team, `sub` the bundle/client id, and the
 * header carries the Sign in with Apple key id. Node's `ieee-p1363` encoding is the raw r||s
 * form JWS requires, not DER.
 */
export function createAppleClientSecret(options: AppleClientSecretOptions): string {
  const issuedAt = options.issuedAt ?? Math.floor(Date.now() / 1000);
  const ttl = options.ttlSeconds ?? APPLE_CLIENT_SECRET_TTL_SECONDS;
  const header = { alg: "ES256", kid: options.config.keyId, typ: "JWT" };
  const payload = {
    iss: options.config.teamId,
    iat: issuedAt,
    exp: issuedAt + ttl,
    aud: APPLE_ISSUER,
    sub: options.config.clientId
  };
  const signingInput = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;
  const signer = createSign("sha256");
  signer.update(signingInput);
  signer.end();
  const signature = signer.sign({ key: normalizePrivateKey(options.config.privateKey), dsaEncoding: "ieee-p1363" });
  return `${signingInput}.${signature.toString("base64url")}`;
}

interface AppleIdTokenClaims {
  iss?: unknown;
  aud?: unknown;
  sub?: unknown;
}

/** The id_token arrives over TLS straight from Apple, so its claims are read, not re-signed. */
function decodeIdTokenClaims(idToken: string): AppleIdTokenClaims | null {
  const segment = idToken.split(".")[1];
  if (!segment) return null;
  try {
    const parsed: unknown = JSON.parse(Buffer.from(segment, "base64url").toString("utf8"));
    return typeof parsed === "object" && parsed !== null ? (parsed as AppleIdTokenClaims) : null;
  } catch {
    return null;
  }
}

function audienceMatches(aud: unknown, clientId: string): boolean {
  if (typeof aud === "string") return aud === clientId;
  return Array.isArray(aud) && aud.includes(clientId);
}

async function postForm(
  fetchImpl: typeof fetch,
  url: string,
  params: Record<string, string>,
  timeoutMs: number
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  timer.unref?.();
  try {
    return await fetchImpl(url, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams(params).toString(),
      signal: controller.signal
    });
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Apple's error vocabulary is a small set of `snake_case` identifiers (TN3107). Only a value that
 * looks like one is logged; anything else is reported as `unrecognized` so an upstream body can never
 * smuggle a credential into the log line.
 */
function appleErrorCode(body: unknown): string {
  const error = typeof body === "object" && body !== null ? (body as { error?: unknown }).error : undefined;
  return typeof error === "string" && /^[a-z][a-z_]{1,39}$/.test(error) ? error : "unrecognized";
}

async function readJson(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    return null;
  }
}

/**
 * Trades the fresh authorization code for Apple's refresh token, proves the code belongs to the
 * account being deleted, and only then revokes.
 *
 * Only `invalid_grant` is a user-side refusal a fresh code can fix, so it is the only 4xx reported as
 * `reauth_required`. Everything else — `invalid_client` (our client secret, key id or team is wrong),
 * `invalid_request`, `unauthorized_client`, a 5xx, a timeout, a malformed success body — throws,
 * because a new user code cannot fix it and an error is never evidence that the tokens were revoked.
 */
export async function revokeAppleAuthorizationCode(options: AppleRevocationOptions): Promise<AppleRevocationResult> {
  const fetchImpl = options.fetchImpl ?? fetch;
  const now = options.now ?? (() => Math.floor(Date.now() / 1000));
  const timeoutMs = options.timeoutMs ?? APPLE_REQUEST_TIMEOUT_MS;
  const clientSecret = createAppleClientSecret({ config: options.config, issuedAt: now() });

  let tokenResponse: Response;
  try {
    tokenResponse = await postForm(
      fetchImpl,
      APPLE_TOKEN_EXCHANGE_URL,
      {
        client_id: options.config.clientId,
        client_secret: clientSecret,
        code: options.authorizationCode,
        grant_type: "authorization_code"
      },
      timeoutMs
    );
  } catch {
    throw new AppleRevocationError("token_exchange", "transport");
  }

  if (tokenResponse.status >= 400 && tokenResponse.status < 500) {
    const body = await readJson(tokenResponse);
    if (appleErrorCode(body) === "invalid_grant") {
      return { outcome: "reauth_required", reason: "invalid_grant" };
    }
    // A refusal we caused (credentials, signing, request shape) is not something the user can retry.
    throw new AppleRevocationError("token_exchange", appleErrorCode(body));
  }
  if (!tokenResponse.ok) {
    throw new AppleRevocationError("token_exchange", `status_${tokenResponse.status}`);
  }

  const tokenBody = (await readJson(tokenResponse)) as { refresh_token?: unknown; id_token?: unknown } | null;
  const refreshToken = typeof tokenBody?.refresh_token === "string" ? tokenBody.refresh_token : null;
  const idToken = typeof tokenBody?.id_token === "string" ? tokenBody.id_token : null;
  if (!refreshToken || !idToken) {
    throw new AppleRevocationError("token_exchange", "malformed_response");
  }

  const claims = decodeIdTokenClaims(idToken);
  if (
    !claims ||
    claims.iss !== APPLE_ISSUER ||
    claims.sub !== options.appleSub ||
    !audienceMatches(claims.aud, options.config.clientId)
  ) {
    return { outcome: "identity_mismatch" };
  }

  let revokeResponse: Response;
  try {
    revokeResponse = await postForm(
      fetchImpl,
      APPLE_REVOKE_URL,
      {
        client_id: options.config.clientId,
        client_secret: clientSecret,
        token: refreshToken,
        token_type_hint: "refresh_token"
      },
      timeoutMs
    );
  } catch {
    throw new AppleRevocationError("revoke", "transport");
  }
  if (!revokeResponse.ok) {
    throw new AppleRevocationError("revoke", `status_${revokeResponse.status}`);
  }

  return { outcome: "revoked" };
}
