import { createVerify, generateKeyPairSync } from "node:crypto";
import { describe, expect, it, vi } from "vitest";

import {
  APPLE_CLIENT_SECRET_TTL_SECONDS,
  APPLE_ISSUER,
  APPLE_REVOKE_URL,
  APPLE_TOKEN_EXCHANGE_URL,
  AppleRevocationError,
  createAppleClientSecret,
  revokeAppleAuthorizationCode
} from "./appleRevocation";

const TEAM_ID = "TEAMID1234";
const CLIENT_ID = "com.example.aipose";
const KEY_ID = "KEYID5678";
const APPLE_SUB = "001234.abcdef.0900";
const CODE = "c-authorization-code";

const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
const PEM = privateKey.export({ format: "pem", type: "pkcs8" }).toString();

const config = { teamId: TEAM_ID, clientId: CLIENT_ID, keyId: KEY_ID, privateKey: PEM };

function encode(value: unknown): string {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

function decodeSegment(segment: string): Record<string, unknown> {
  return JSON.parse(Buffer.from(segment, "base64url").toString("utf8")) as Record<string, unknown>;
}

function idToken(overrides: { iss?: string; aud?: string; sub?: string } = {}): string {
  const payload = {
    iss: overrides.iss ?? APPLE_ISSUER,
    aud: overrides.aud ?? CLIENT_ID,
    sub: overrides.sub ?? APPLE_SUB,
    exp: 2_000_000_000
  };
  return `${encode({ alg: "ES256", kid: KEY_ID })}.${encode(payload)}.signature-not-verified`;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function formBody(init: RequestInit | undefined): URLSearchParams {
  return new URLSearchParams(String(init?.body ?? ""));
}

interface FetchCall {
  url: string;
  body: URLSearchParams;
}

/** Stubs Apple by URL, recording the exact form each call carried. */
function stubApple(responses: {
  exchange?: () => Response;
  revoke?: () => Response;
}): { fetchImpl: typeof fetch; calls: FetchCall[] } {
  const calls: FetchCall[] = [];
  const fetchImpl = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
    const target = String(url);
    calls.push({ url: target, body: formBody(init) });
    if (target === APPLE_TOKEN_EXCHANGE_URL) {
      return responses.exchange ? responses.exchange() : jsonResponse({ refresh_token: "r-token", id_token: idToken() });
    }
    if (target === APPLE_REVOKE_URL) {
      return responses.revoke ? responses.revoke() : new Response(null, { status: 200 });
    }
    throw new Error(`Unexpected Apple URL ${target}`);
  }) as unknown as typeof fetch;
  return { fetchImpl, calls };
}

function revoke(overrides: Partial<Parameters<typeof revokeAppleAuthorizationCode>[0]> = {}) {
  const stub = stubApple({
    exchange: () => jsonResponse({ refresh_token: "r-token", id_token: idToken() }),
    ...(overrides as { exchange?: () => Response; revoke?: () => Response })
  });
  return revokeAppleAuthorizationCode({
    authorizationCode: CODE,
    appleSub: APPLE_SUB,
    config,
    fetchImpl: stub.fetchImpl,
    now: () => 1_700_000_000,
    ...overrides
  }).then((result) => ({ result, calls: stub.calls }));
}

describe("createAppleClientSecret", () => {
  it("signs an ES256 assertion with Apple's audience, subject and key id", () => {
    const secret = createAppleClientSecret({ config, issuedAt: 1_700_000_000 });
    const [header, payload, signature] = secret.split(".");

    expect(decodeSegment(header!)).toEqual({ alg: "ES256", kid: KEY_ID, typ: "JWT" });
    expect(decodeSegment(payload!)).toEqual({
      iss: TEAM_ID,
      iat: 1_700_000_000,
      exp: 1_700_000_000 + APPLE_CLIENT_SECRET_TTL_SECONDS,
      aud: APPLE_ISSUER,
      sub: CLIENT_ID
    });

    const verifier = createVerify("sha256");
    verifier.update(`${header}.${payload}`);
    verifier.end();
    expect(verifier.verify({ key: publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(signature!, "base64url"))).toBe(true);
  });

  it("accepts a PEM whose newlines arrive escaped, the way an env var stores it", () => {
    const escaped = { ...config, privateKey: PEM.replace(/\n/g, "\\n") };
    expect(createAppleClientSecret({ config: escaped, issuedAt: 1_700_000_000 }).split(".")).toHaveLength(3);
  });
});

describe("revokeAppleAuthorizationCode", () => {
  it("exchanges the code, proves the identity, then revokes the refresh token", async () => {
    const { result, calls } = await revoke();

    expect(result).toEqual({ outcome: "revoked" });
    expect(calls.map((call) => call.url)).toEqual([APPLE_TOKEN_EXCHANGE_URL, APPLE_REVOKE_URL]);

    const exchange = calls[0]!.body;
    expect(exchange.get("grant_type")).toBe("authorization_code");
    expect(exchange.get("code")).toBe(CODE);
    expect(exchange.get("client_id")).toBe(CLIENT_ID);
    expect(exchange.get("client_secret")?.split(".")).toHaveLength(3);

    const revokeCall = calls[1]!.body;
    expect(revokeCall.get("token")).toBe("r-token");
    expect(revokeCall.get("token_type_hint")).toBe("refresh_token");
    expect(revokeCall.get("client_id")).toBe(CLIENT_ID);
    expect(revokeCall.get("client_secret")).toBe(exchange.get("client_secret"));
  });

  it("refuses a code minted for another Apple account and never calls revoke", async () => {
    const stub = stubApple({
      exchange: () => jsonResponse({ refresh_token: "r-token", id_token: idToken({ sub: "someone-else" }) })
    });
    const result = await revokeAppleAuthorizationCode({
      authorizationCode: CODE,
      appleSub: APPLE_SUB,
      config,
      fetchImpl: stub.fetchImpl
    });

    expect(result).toEqual({ outcome: "identity_mismatch" });
    expect(stub.calls.map((call) => call.url)).toEqual([APPLE_TOKEN_EXCHANGE_URL]);
  });

  it.each([
    ["audience", { aud: "com.example.other" }],
    ["issuer", { iss: "https://evil.example.com" }]
  ])("treats a mismatched %s as an identity mismatch", async (_label, claim) => {
    const stub = stubApple({ exchange: () => jsonResponse({ refresh_token: "r-token", id_token: idToken(claim) }) });
    const result = await revokeAppleAuthorizationCode({
      authorizationCode: CODE,
      appleSub: APPLE_SUB,
      config,
      fetchImpl: stub.fetchImpl
    });

    expect(result).toEqual({ outcome: "identity_mismatch" });
    expect(stub.calls).toHaveLength(1);
  });

  /**
   * `invalid_grant` is an expired/reused code; `invalid_request` covers a revoked authorization (the
   * user removed the app in Apple ID settings, TN3107). A fresh sheet fixes both, so both must stay
   * recoverable — otherwise guideline 5.1.1(v) deletion is blocked forever.
   */
  it.each(["invalid_grant", "invalid_request"])("reports %s as reauth required, never as revoked", async (error) => {
    const stub = stubApple({ exchange: () => jsonResponse({ error }, 400) });
    const result = await revokeAppleAuthorizationCode({
      authorizationCode: CODE,
      appleSub: APPLE_SUB,
      config,
      fetchImpl: stub.fetchImpl
    });

    expect(result).toEqual({ outcome: "reauth_required", reason: error });
    expect(stub.calls).toHaveLength(1);
  });

  /**
   * These are our fault, not the user's: a fresh authorization code cannot fix a wrong client secret,
   * key id, team or scope, so they must never come back as "ask the user to confirm again".
   */
  it.each(["invalid_client", "unauthorized_client", "unsupported_grant_type", "invalid_scope"])(
    "throws on an exchange %s refusal and reports Apple's error code",
    async (error) => {
      const stub = stubApple({ exchange: () => jsonResponse({ error }, 400) });
      const failure = await revokeAppleAuthorizationCode({
        authorizationCode: CODE,
        appleSub: APPLE_SUB,
        config,
        fetchImpl: stub.fetchImpl
      }).catch((thrown: unknown) => thrown);

      expect(failure).toBeInstanceOf(AppleRevocationError);
      expect(failure).toMatchObject({ stage: "token_exchange", appleError: error });
      expect(stub.calls).toHaveLength(1);
    }
  );

  /**
   * The allowlist is fixed, not a shape test: a plausible-looking snake_case value must not reach the
   * log just because it is lowercase, or an upstream body could smuggle a credential through.
   */
  it.each([
    "secret_access_token",
    "code=SECRET-CODE",
    "client_secret",
    "invalid_grant ",
    "INVALID_GRANT",
    ""
  ])("reports an undocumented upstream error field %j as unrecognized", async (rawError) => {
    const stub = stubApple({ exchange: () => jsonResponse({ error: rawError }, 400) });
    const failure = await revokeAppleAuthorizationCode({
      authorizationCode: CODE,
      appleSub: APPLE_SUB,
      config,
      fetchImpl: stub.fetchImpl
    }).catch((thrown: unknown) => thrown);

    expect(failure).toMatchObject({ stage: "token_exchange", appleError: "unrecognized" });
    expect(JSON.stringify(failure)).not.toContain(rawError.trim() || "nothing-to-find");
    expect(stub.calls).toHaveLength(1);
  });

  it("throws on an exchange 5xx", async () => {
    await expect(revoke({ exchange: () => new Response("boom", { status: 503 }) })).rejects.toMatchObject({
      name: "AppleRevocationError",
      stage: "token_exchange",
      appleError: "status_503"
    });
  });

  /**
   * A real stall: the stub honours the abort signal the client sends, so this asserts the timeout is
   * wired (it takes at least the timeout to fail), not that a pre-broken fetch throws.
   */
  it("aborts a stalled exchange after the timeout and throws", async () => {
    let aborted = false;
    const stalling = vi.fn(
      (_url: string | URL | Request, init?: RequestInit) =>
        new Promise<Response>((_resolve, reject) => {
          init?.signal?.addEventListener("abort", () => {
            aborted = true;
            reject(Object.assign(new Error("The operation was aborted"), { name: "AbortError" }));
          });
        })
    ) as unknown as typeof fetch;

    const startedAt = Date.now();
    const failure = await revokeAppleAuthorizationCode({
      authorizationCode: CODE,
      appleSub: APPLE_SUB,
      config,
      fetchImpl: stalling,
      timeoutMs: 25
    }).catch((thrown: unknown) => thrown);

    expect(failure).toMatchObject({ name: "AppleRevocationError", stage: "token_exchange", appleError: "transport" });
    expect(aborted).toBe(true);
    expect(Date.now() - startedAt).toBeGreaterThanOrEqual(20);
  });

  it("throws on a revoke 5xx instead of reporting the tokens as revoked", async () => {
    await expect(
      revoke({ revoke: () => new Response("boom", { status: 500 }) })
    ).rejects.toMatchObject({ name: "AppleRevocationError", stage: "revoke" });
  });

  it("throws when a 200 exchange body carries no refresh token", async () => {
    await expect(revoke({ exchange: () => jsonResponse({ id_token: idToken() }) })).rejects.toMatchObject({
      name: "AppleRevocationError",
      stage: "token_exchange"
    });
  });

  it("never puts the private key in an error message", async () => {
    const failure = await revoke({ exchange: () => new Response("boom", { status: 500 }) }).catch((error: Error) => error);
    expect(failure).toBeInstanceOf(Error);
    const text = `${(failure as Error).message}${(failure as Error).stack ?? ""}`;
    expect(text).not.toContain("PRIVATE KEY");
    expect(text).not.toContain(PEM.split("\n")[1]!);
  });
});
