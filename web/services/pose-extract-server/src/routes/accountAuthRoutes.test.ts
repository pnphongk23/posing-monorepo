import { createHash, createSign, generateKeyPairSync } from "node:crypto";
import express from "express";
import request from "supertest";
import { describe, expect, it, vi } from "vitest";

import { createApp } from "../app";
import type { AccountStore } from "../db/accountStore";
import { PendingAuthStore } from "../services/pendingAuthStore";
import { createAccountAuthRoutes } from "./accountAuthRoutes";

const SUPABASE_URL = "https://project-ref.supabase.co";
const BACKEND_PUBLIC_URL = "https://api.example.test";
const CALLBACK_URI = `${BACKEND_PUBLIC_URL}/api/auth/google/callback`;
const KEY_ID = "test-key-id";
const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
const jwk = { ...publicKey.export({ format: "jwk" }), alg: "ES256", kid: KEY_ID, kty: "EC", crv: "P-256", use: "sig" };

function encode(value: unknown): string { return Buffer.from(JSON.stringify(value)).toString("base64url"); }
function jwt(sub = "user-a", overrides: Record<string, unknown> = {}): string {
  const input = `${encode({ alg: "ES256", typ: "JWT", kid: KEY_ID })}.${encode({ iss: `${SUPABASE_URL}/auth/v1`, aud: "authenticated", exp: 2_000_000_000, sub, name: "Test User", ...overrides })}`;
  const signer = createSign("sha256");
  signer.update(input);
  signer.end();
  return `${input}.${signer.sign({ key: privateKey, dsaEncoding: "ieee-p1363" }).toString("base64url")}`;
}

function accountStore(): AccountStore {
  return { upsert: async ({ id, displayName }) => ({ id, displayName, createdAt: "2026-01-01T00:00:00.000Z" }) } as AccountStore;
}

function configuredRoutes(overrides: Partial<Parameters<typeof createAccountAuthRoutes>[0]> = {}) {
  return createAccountAuthRoutes({
    supabaseUrl: SUPABASE_URL,
    anonKey: "mock-anon-key",
    backendPublicUrl: BACKEND_PUBLIC_URL,
    keyId: KEY_ID,
    accountStore: accountStore(),
    pendingAuthStore: new PendingAuthStore(),
    fetchImpl: vi.fn(async () => new Response(JSON.stringify({ access_token: jwt(), refresh_token: "mock-refresh" }), { status: 200 })),
    fetchJwks: vi.fn(async () => new Response(JSON.stringify({ keys: [jwk] }), { status: 200 })),
    ...overrides
  });
}

describe("Google-only backend OAuth handoff (mocked provider/JWKS; live Pending-validation)", () => {
  it("fails closed when the fixed backend public URL is absent", async () => {
    const app = express().use("/api/auth", configuredRoutes({ backendPublicUrl: undefined }));
    const response = await request(app).get("/api/auth/google/start");
    expect(response.status).toBe(503);
    expect(response.body).toEqual({ error: { code: "AUTH_PENDING_VALIDATION", message: "OAuth exchange is pending runtime validation" } });
  });

  it("uses oauth_tx in the nested redirect and preserves a valid S256 challenge", async () => {
    const app = createApp({ version: "test", accountStore: accountStore(), supabaseUrl: SUPABASE_URL, supabaseAnonKey: "mock-anon-key", supabaseJwtKeyId: KEY_ID, backendPublicUrl: BACKEND_PUBLIC_URL, pendingAuthStore: new PendingAuthStore() });
    const response = await request(app).get("/api/auth/google/start").set("Host", "evil.example").set("X-Forwarded-Proto", "http");
    const location = new URL(response.headers.location);
    const redirectTo = new URL(location.searchParams.get("redirect_to")!);
    expect(response.status).toBe(302);
    expect(location.searchParams.get("provider")).toBe("google");
    expect(location.searchParams.get("state")).toBeNull();
    expect(redirectTo.origin + redirectTo.pathname).toBe(CALLBACK_URI);
    expect(redirectTo.searchParams.get("oauth_tx")).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(location.searchParams.get("code_challenge_method")).toBe("S256");
    expect(location.searchParams.get("code_challenge")).toHaveLength(43);
    const pending = new PendingAuthStore();
    const record = pending.create(CALLBACK_URI);
    expect(createHash("sha256").update(record.codeVerifier).digest("base64url")).toHaveLength(43);
  });

  it("rejects unknown and replay transactions, then hands off only an opaque code", async () => {
    const store = new PendingAuthStore();
    const app = express().use(express.json()).use("/api/auth", configuredRoutes({ pendingAuthStore: store }));
    const startUrl = new URL((await request(app).get("/api/auth/google/start")).headers.location);
    const transactionId = new URL(startUrl.searchParams.get("redirect_to")!).searchParams.get("oauth_tx")!;
    expect((await request(app).get("/api/auth/google/callback?oauth_tx=wrong&code=provider-code")).status).toBe(401);
    const callback = await request(app).get(`/api/auth/google/callback?oauth_tx=${transactionId}&code=provider-code`);
    expect(callback.status).toBe(302);
    expect(callback.headers.location).toMatch(/^aipose:\/\/auth\/callback\?code=[A-Za-z0-9_-]+$/);
    expect(callback.headers.location).not.toContain("access_token");
    expect((await request(app).get(`/api/auth/google/callback?oauth_tx=${transactionId}&code=provider-code`)).status).toBe(401);
  });

  it("uses the exact GoTrue PKCE JSON exchange contract", async () => {
    const fetchImpl = vi.fn(async () => new Response(JSON.stringify({ access_token: jwt(), refresh_token: "mock-refresh" }), { status: 200 }));
    const app = express().use(express.json()).use("/api/auth", configuredRoutes({ fetchImpl }));
    const startUrl = new URL((await request(app).get("/api/auth/google/start")).headers.location);
    const redirectTo = new URL(startUrl.searchParams.get("redirect_to")!);
    const transactionId = redirectTo.searchParams.get("oauth_tx")!;
    await request(app).get(`/api/auth/google/callback?oauth_tx=${transactionId}&code=provider-code`);
    const [url, init] = fetchImpl.mock.calls[0] as [string, RequestInit];
    expect(url).toBe(`${SUPABASE_URL}/auth/v1/token?grant_type=pkce`);
    expect(init.method).toBe("POST");
    expect(init.headers).toEqual({ apikey: "mock-anon-key", "content-type": "application/json" });
    const body = JSON.parse(String(init.body));
    expect(body.auth_code).toBe("provider-code");
    expect(createHash("sha256").update(body.code_verifier).digest("base64url")).toBe(startUrl.searchParams.get("code_challenge"));
    expect(body).not.toHaveProperty("redirect_uri");
  });

  it("expires pending transactions and consumes session handoff exactly once", async () => {
    let now = 1_000;
    const store = new PendingAuthStore(10, () => now);
    const app = express().use(express.json()).use("/api/auth", configuredRoutes({ pendingAuthStore: store }));
    const startUrl = new URL((await request(app).get("/api/auth/google/start")).headers.location);
    const transactionId = new URL(startUrl.searchParams.get("redirect_to")!).searchParams.get("oauth_tx")!;
    now = 2_000;
    expect((await request(app).get(`/api/auth/google/callback?oauth_tx=${transactionId}&code=provider-code`)).status).toBe(401);
    const session = store.createSession({ accessToken: "mock-access", refreshToken: "mock-refresh", account: { id: "user-a", displayName: "Test User", createdAt: "2026-01-01T00:00:00.000Z" } });
    const first = await request(app).post("/api/auth/session").send({ code: session });
    const second = await request(app).post("/api/auth/session").send({ code: session });
    expect(first.status).toBe(200);
    expect(first.body).toEqual(expect.objectContaining({ accessToken: "mock-access", refreshToken: "mock-refresh" }));
    expect(second.status).toBe(401);
  });

  it("uses the exact JSON refresh contract and fails callback closed", async () => {
    const fetchImpl = vi.fn(async (url: string) => String(url).includes("refresh_token")
      ? new Response(JSON.stringify({ access_token: jwt(), refresh_token: "new-refresh" }), { status: 200 })
      : new Response("provider failure", { status: 500 }));
    const app = express().use(express.json()).use("/api/auth", configuredRoutes({ fetchImpl }));
    const refresh = await request(app).post("/api/auth/refresh").send({ refreshToken: "refresh-token" });
    expect(refresh.status).toBe(200);
    const [url, init] = fetchImpl.mock.calls[0] as [string, RequestInit];
    expect(url).toBe(`${SUPABASE_URL}/auth/v1/token?grant_type=refresh_token`);
    expect(init.method).toBe("POST");
    expect(init.headers).toEqual({ apikey: "mock-anon-key", "content-type": "application/json" });
    expect(JSON.parse(String(init.body))).toEqual({ refresh_token: "refresh-token" });
    const startUrl = new URL((await request(app).get("/api/auth/google/start")).headers.location);
    const transactionId = new URL(startUrl.searchParams.get("redirect_to")!).searchParams.get("oauth_tx")!;
    const callback = await request(app).get(`/api/auth/google/callback?oauth_tx=${transactionId}&code=provider-code`);
    expect(callback.status).toBe(503);
    expect(callback.text).not.toContain("access_token");
    expect(callback.text).not.toContain("refresh_token");
  });
});

describe("POST /api/auth/email/signin (email/password grant; mocked provider/JWKS)", () => {
  const EMAIL = "appreview@example.test";
  const PASSWORD = "correct-horse-battery";

  function passwordRoutes(overrides: Partial<Parameters<typeof createAccountAuthRoutes>[0]> = {}) {
    const upsert = vi.fn(async ({ id, displayName }: { id: string; displayName: string }) => ({
      id,
      displayName,
      createdAt: "2026-01-01T00:00:00.000Z"
    }));
    const store = { upsert } as unknown as AccountStore;
    return {
      app: express().use(express.json()).use("/api/auth", configuredRoutes({ accountStore: store, ...overrides })),
      upsert
    };
  }

  it("returns the exact session/refresh 200 body shape and upserts the account", async () => {
    const token = jwt();
    const { app, upsert } = passwordRoutes({ fetchImpl: vi.fn(async () => new Response(JSON.stringify({ access_token: token, refresh_token: "mock-refresh" }), { status: 200 })) });
    const response = await request(app).post("/api/auth/email/signin").send({ email: EMAIL, password: PASSWORD });
    expect(response.status).toBe(200);
    expect(response.body).toEqual({
      accessToken: token,
      refreshToken: "mock-refresh",
      account: { id: "user-a", displayName: "Test User", createdAt: "2026-01-01T00:00:00.000Z" }
    });
    expect(Object.keys(response.body).sort()).toEqual(["accessToken", "account", "refreshToken"]);
    expect(Object.keys(response.body.account).sort()).toEqual(["createdAt", "displayName", "id"]);
    expect(upsert).toHaveBeenCalledWith({ id: "user-a", displayName: "Test User" });
  });

  it("uses the exact GoTrue password grant contract with snake_case mapping", async () => {
    const token = jwt();
    const fetchImpl = vi.fn(async () => new Response(JSON.stringify({ access_token: token, refresh_token: "mock-refresh" }), { status: 200 }));
    const { app } = passwordRoutes({ fetchImpl });
    const response = await request(app).post("/api/auth/email/signin").send({ email: EMAIL, password: PASSWORD });
    expect(response.status).toBe(200);
    const [url, init] = fetchImpl.mock.calls[0] as [string, RequestInit];
    expect(url).toBe(`${SUPABASE_URL}/auth/v1/token?grant_type=password`);
    expect(init.method).toBe("POST");
    expect(init.headers).toEqual({ apikey: "mock-anon-key", "content-type": "application/json" });
    expect(JSON.parse(String(init.body))).toEqual({ email: EMAIL, password: PASSWORD });
    expect(response.body).toHaveProperty("accessToken", token);
    expect(response.body).toHaveProperty("refreshToken", "mock-refresh");
  });

  it("rejects missing or invalid email/password with 400 BAD_REQUEST", async () => {
    const { app } = passwordRoutes({ fetchImpl: vi.fn() });
    for (const body of [{}, { email: EMAIL }, { password: PASSWORD }, { email: "not-an-email", password: PASSWORD }]) {
      const response = await request(app).post("/api/auth/email/signin").send(body);
      expect(response.status).toBe(400);
      expect(response.body.error.code).toBe("BAD_REQUEST");
    }
  });

  it("returns ONE indistinguishable 401 for unknown email and wrong password across different provider errors", async () => {
    const wrongPasswordBody = { code: 400, error_code: "invalid_credentials", msg: "Invalid login credentials" };
    const unknownEmailBody = { code: 400, error_code: "user_not_found", msg: "User not found" };
    const legacyBody = { error: "invalid_grant", error_description: "Invalid login credentials" };
    const cases = [wrongPasswordBody, unknownEmailBody, legacyBody];
    const responses = [];
    for (const providerBody of cases) {
      const { app } = passwordRoutes({ fetchImpl: vi.fn(async () => new Response(JSON.stringify(providerBody), { status: 400 })) });
      responses.push(await request(app).post("/api/auth/email/signin").send({ email: EMAIL, password: PASSWORD }));
    }
    const [a, b, c] = responses;
    for (const response of responses) {
      expect(response.status).toBe(401);
      expect(response.body).toEqual({ error: { code: "INVALID_CREDENTIALS", message: "Incorrect email or password" } });
    }
    expect(a.text).toBe(b.text);
    expect(b.text).toBe(c.text);
    for (const leaked of ["User not found", "Invalid login credentials", "user_not_found", "invalid_grant"]) {
      expect(a.text).not.toContain(leaked);
      expect(b.text).not.toContain(leaked);
      expect(c.text).not.toContain(leaked);
    }
  });

  it("returns 403 EMAIL_NOT_CONFIRMED when the provider says so", async () => {
    for (const body of [
      { code: 400, error_code: "email_not_confirmed", msg: "Email not confirmed" },
      { error: "invalid_grant", error_description: "Email not confirmed" }
    ]) {
      const { app } = passwordRoutes({ fetchImpl: vi.fn(async () => new Response(JSON.stringify(body), { status: 400 })) });
      const response = await request(app).post("/api/auth/email/signin").send({ email: EMAIL, password: PASSWORD });
      expect(response.status).toBe(403);
      expect(response.body.error.code).toBe("EMAIL_NOT_CONFIRMED");
    }
  });

  it("rate limits to 10 attempts per ip+email in 15 minutes with 429 RATE_LIMITED", async () => {
    const { app } = passwordRoutes({ authRateLimitMaxPerEmail: 10, authRateLimitMaxPerIp: 100 });
    for (let i = 0; i < 10; i += 1) {
      const response = await request(app).post("/api/auth/email/signin").send({ email: EMAIL, password: PASSWORD });
      expect(response.status).toBe(200);
    }
    const eleventh = await request(app).post("/api/auth/email/signin").send({ email: EMAIL, password: PASSWORD });
    expect(eleventh.status).toBe(429);
    expect(eleventh.body.error.code).toBe("RATE_LIMITED");
  });

  function createAppUnderTest(): express.Express {
    return createApp({
      version: "test",
      accountStore: accountStore(),
      supabaseUrl: SUPABASE_URL,
      supabaseAnonKey: "mock-anon-key",
      supabaseJwtKeyId: KEY_ID,
      pendingAuthStore: new PendingAuthStore(),
      fetchImpl: vi.fn(async () => new Response(JSON.stringify({ access_token: jwt(), refresh_token: "mock-refresh" }), { status: 200 })),
      fetchJwks: vi.fn(async () => new Response(JSON.stringify({ keys: [jwk] }), { status: 200 }))
    });
  }

  it("caps ONE account globally: the same email from 40 different X-Forwarded-For values hits 429 at attempt 11", async () => {
    const app = createAppUnderTest();
    for (let i = 0; i < 10; i += 1) {
      const response = await request(app).post("/api/auth/email/signin")
        .set("X-Forwarded-For", `203.0.113.${i}`)
        .send({ email: EMAIL, password: PASSWORD });
      expect(response.status).toBe(200);
    }
    const eleventh = await request(app).post("/api/auth/email/signin")
      .set("X-Forwarded-For", "203.0.113.199")
      .send({ email: EMAIL, password: PASSWORD });
    expect(eleventh.status).toBe(429);
    expect(eleventh.body.error.code).toBe("RATE_LIMITED");
  });

  it("caps ONE host: a single ip hammering 40 different emails hits 429 at attempt 31", async () => {
    const app = createAppUnderTest();
    for (let i = 0; i < 30; i += 1) {
      const response = await request(app).post("/api/auth/email/signin")
        .set("X-Forwarded-For", "198.51.100.7")
        .send({ email: `user-${i}@example.test`, password: PASSWORD });
      expect(response.status).toBe(200);
    }
    const thirtyFirst = await request(app).post("/api/auth/email/signin")
      .set("X-Forwarded-For", "198.51.100.7")
      .send({ email: "user-30@example.test", password: PASSWORD });
    expect(thirtyFirst.status).toBe(429);
    expect(thirtyFirst.body.error.code).toBe("RATE_LIMITED");
  });

  it("surfaces an upstream provider 429 as 429 RATE_LIMITED, never as a wrong password", async () => {
    const { app } = passwordRoutes({
      fetchImpl: vi.fn(async () => new Response(JSON.stringify({ code: 429, error_code: "over_request_rate_limit", msg: "Too many requests" }), { status: 429 }))
    });
    const response = await request(app).post("/api/auth/email/signin").send({ email: EMAIL, password: PASSWORD });
    expect(response.status).toBe(429);
    expect(response.body).toEqual({ error: { code: "RATE_LIMITED", message: "Too many sign-in attempts" } });
    expect(response.body.error.code).not.toBe("INVALID_CREDENTIALS");
  });

  it("returns 503 AUTH_PENDING_VALIDATION when the upstream exchange throws, without upserting", async () => {
    const { app, upsert } = passwordRoutes({ fetchImpl: vi.fn(async () => { throw new Error("DNS failure"); }) });
    const response = await request(app).post("/api/auth/email/signin").send({ email: EMAIL, password: PASSWORD });
    expect(response.status).toBe(503);
    expect(response.body).toEqual({ error: { code: "AUTH_PENDING_VALIDATION", message: "Sign-in is temporarily unavailable" } });
    expect(upsert).not.toHaveBeenCalled();
    expect(response.text).not.toContain("access_token");
    expect(response.text).not.toContain("refresh_token");
  });

  it("returns 401 INVALID_CREDENTIALS when verifyJwt rejects a provider-issued token", async () => {
    const { app, upsert } = passwordRoutes({
      fetchImpl: vi.fn(async () => new Response(JSON.stringify({ access_token: "not-a-jwt", refresh_token: "mock-refresh" }), { status: 200 }))
    });
    const response = await request(app).post("/api/auth/email/signin").send({ email: EMAIL, password: PASSWORD });
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("INVALID_CREDENTIALS");
    expect(upsert).not.toHaveBeenCalled();
  });

  it("fails closed with 503 AUTH_PENDING_VALIDATION without the anon key", async () => {
    const { app } = passwordRoutes({ anonKey: undefined, fetchImpl: vi.fn() });
    const response = await request(app).post("/api/auth/email/signin").send({ email: EMAIL, password: PASSWORD });
    expect(response.status).toBe(503);
    expect(response.body).toEqual({ error: { code: "AUTH_PENDING_VALIDATION", message: "OAuth exchange is pending runtime validation" } });
  });

  it("returns 503 on every attempt while misconfigured, never 429 and never consuming quota", async () => {
    const { app } = passwordRoutes({ anonKey: undefined, fetchImpl: vi.fn(), authRateLimitMaxPerEmail: 10, authRateLimitMaxPerIp: 10 });
    for (let i = 0; i < 15; i += 1) {
      const response = await request(app).post("/api/auth/email/signin").send({ email: EMAIL, password: PASSWORD });
      expect(response.status).toBe(503);
      expect(response.body.error.code).toBe("AUTH_PENDING_VALIDATION");
    }
  });

  it("never rate limits /refresh", async () => {
    const { app } = passwordRoutes({ authRateLimitMaxPerEmail: 1, authRateLimitMaxPerIp: 1 });
    await request(app).post("/api/auth/email/signin").send({ email: EMAIL, password: PASSWORD });
    expect((await request(app).post("/api/auth/email/signin").send({ email: EMAIL, password: PASSWORD })).status).toBe(429);
    for (let i = 0; i < 35; i += 1) {
      const refresh = await request(app).post("/api/auth/refresh").send({ refreshToken: "refresh-token" });
      expect(refresh.status).toBe(200);
    }
  });

  it("honours AUTH_RATE_LIMIT_MAX from the environment end-to-end via createApp", async () => {
    const saved = process.env.AUTH_RATE_LIMIT_MAX;
    process.env.AUTH_RATE_LIMIT_MAX = "2";
    try {
      const app = createApp({
        version: "test",
        accountStore: accountStore(),
        supabaseUrl: SUPABASE_URL,
        supabaseAnonKey: "mock-anon-key",
        supabaseJwtKeyId: KEY_ID,
        pendingAuthStore: new PendingAuthStore(),
        fetchImpl: vi.fn(async () => new Response(JSON.stringify({ access_token: jwt(), refresh_token: "mock-refresh" }), { status: 200 })),
        fetchJwks: vi.fn(async () => new Response(JSON.stringify({ keys: [jwk] }), { status: 200 }))
      });
      expect((await request(app).post("/api/auth/email/signin").send({ email: EMAIL, password: PASSWORD })).status).toBe(200);
      expect((await request(app).post("/api/auth/email/signin").send({ email: EMAIL, password: PASSWORD })).status).toBe(200);
      const third = await request(app).post("/api/auth/email/signin").send({ email: EMAIL, password: PASSWORD });
      expect(third.status).toBe(429);
      expect(third.body.error.code).toBe("RATE_LIMITED");
    } finally {
      if (saved === undefined) {
        delete process.env.AUTH_RATE_LIMIT_MAX;
      } else {
        process.env.AUTH_RATE_LIMIT_MAX = saved;
      }
    }
  });

  it("prefers explicit CreateAppOptions over env-supplied AUTH_RATE_LIMIT_MAX", async () => {
    const saved = process.env.AUTH_RATE_LIMIT_MAX;
    process.env.AUTH_RATE_LIMIT_MAX = "2";
    try {
      const app = createApp({
        version: "test",
        accountStore: accountStore(),
        supabaseUrl: SUPABASE_URL,
        supabaseAnonKey: "mock-anon-key",
        supabaseJwtKeyId: KEY_ID,
        pendingAuthStore: new PendingAuthStore(),
        authRateLimitMaxPerEmail: 5,
        fetchImpl: vi.fn(async () => new Response(JSON.stringify({ access_token: jwt(), refresh_token: "mock-refresh" }), { status: 200 })),
        fetchJwks: vi.fn(async () => new Response(JSON.stringify({ keys: [jwk] }), { status: 200 }))
      });
      for (let i = 0; i < 5; i += 1) {
        expect((await request(app).post("/api/auth/email/signin").send({ email: EMAIL, password: PASSWORD })).status).toBe(200);
      }
      const sixth = await request(app).post("/api/auth/email/signin").send({ email: EMAIL, password: PASSWORD });
      expect(sixth.status).toBe(429);
    } finally {
      if (saved === undefined) {
        delete process.env.AUTH_RATE_LIMIT_MAX;
      } else {
        process.env.AUTH_RATE_LIMIT_MAX = saved;
      }
    }
  });
});

describe("upstream 429 is decided before the body is parsed", () => {
  const EMAIL = "appreview@example.test";
  const PASSWORD = "correct-horse-battery";

  it("returns 429 RATE_LIMITED even when the upstream 429 body is not JSON", async () => {
    const upsert = vi.fn();
    const store = { upsert } as unknown as AccountStore;
    const routes = createAccountAuthRoutes({
      supabaseUrl: SUPABASE_URL,
      anonKey: "mock-anon-key",
      backendPublicUrl: BACKEND_PUBLIC_URL,
      keyId: KEY_ID,
      accountStore: store,
      pendingAuthStore: new PendingAuthStore(),
      // A CDN/edge block page, not GoTrue JSON: `res.json()` would throw on this.
      fetchImpl: vi.fn(async () => new Response("<html><body>Too Many Requests</body></html>", {
        status: 429,
        headers: { "content-type": "text/html" }
      }))
    });
    const app = express().use(express.json()).use("/api/auth", routes);
    const response = await request(app).post("/api/auth/email/signin").send({ email: EMAIL, password: PASSWORD });
    expect(response.status).toBe(429);
    expect(response.body).toEqual({ error: { code: "RATE_LIMITED", message: "Too many sign-in attempts" } });
    expect(response.body.error.code).not.toBe("INVALID_CREDENTIALS");
    expect(upsert).not.toHaveBeenCalled();
  });
});

describe("POST /api/auth/apple/signin (id_token grant; mocked provider/JWKS)", () => {
  function appleApp(overrides: Partial<Parameters<typeof createAccountAuthRoutes>[0]> = {}): express.Express {
    return express().use(express.json()).use("/api/auth", configuredRoutes(overrides));
  }

  it("forwards the raw nonce and exact Apple exchange contract", async () => {
    const token = jwt("apple-user");
    const fetchImpl = vi.fn(async () => new Response(JSON.stringify({ access_token: token, refresh_token: "apple-refresh" }), { status: 200 }));
    const response = await request(appleApp({ fetchImpl })).post("/api/auth/apple/signin").send({
      identityToken: "apple-identity-token",
      nonce: "raw-nonce-not-hex",
      fullName: "  Apple User  "
    });

    expect(response.status).toBe(200);
    const [url, init] = fetchImpl.mock.calls[0] as [string, RequestInit];
    expect(url).toBe(`${SUPABASE_URL}/auth/v1/token?grant_type=id_token`);
    expect(init.method).toBe("POST");
    expect(init.headers).toEqual({ apikey: "mock-anon-key", "content-type": "application/json" });
    expect(JSON.parse(String(init.body))).toEqual({ provider: "apple", id_token: "apple-identity-token", nonce: "raw-nonce-not-hex" });
    expect(response.body.account.displayName).toBe("Apple User");
  });

  it("uses the claims display-name fallback when fullName is absent and accepts a private relay identity", async () => {
    const token = jwt("relay-user", { name: undefined, email: "xyz@privaterelay.appleid.com" });
    const upsert = vi.fn(async ({ id, displayName }: { id: string; displayName: string }) => ({ id, displayName, createdAt: "2026-01-01T00:00:00.000Z" }));
    const store = { upsert } as unknown as AccountStore;
    const response = await request(appleApp({
      accountStore: store,
      fetchImpl: vi.fn(async () => new Response(JSON.stringify({ access_token: token, refresh_token: "apple-refresh" }), { status: 200 }))
    })).post("/api/auth/apple/signin").send({ identityToken: "apple-token", nonce: "relay-raw-nonce" });

    expect(response.status).toBe(200);
    expect(upsert).toHaveBeenCalledWith({ id: "relay-user", displayName: "xyz@privaterelay.appleid.com" });
    expect(response.body.account.id).toBe("relay-user");
  });

  it("returns 400 BAD_REQUEST for invalid identityToken, nonce, or body", async () => {
    for (const body of [{}, { identityToken: "token", nonce: "short" }, { identityToken: "", nonce: "long-enough" }]) {
      const response = await request(appleApp()).post("/api/auth/apple/signin").send(body);
      expect(response.status).toBe(400);
      expect(response.body.error.code).toBe("BAD_REQUEST");
    }
  });

  it("returns the same session body keys as email sign-in", async () => {
    const token = jwt("apple-user");
    const response = await request(appleApp({
      fetchImpl: vi.fn(async () => new Response(JSON.stringify({ access_token: token, refresh_token: "apple-refresh" }), { status: 200 }))
    })).post("/api/auth/apple/signin").send({ identityToken: "apple-token", nonce: "raw-nonce-value" });

    expect(response.status).toBe(200);
    expect(Object.keys(response.body).sort()).toEqual(["accessToken", "account", "refreshToken"]);
  });

  it("returns one indistinguishable 401 for upstream failure, network failure, and incomplete tokens", async () => {
    const cases = [
      vi.fn(async () => new Response("provider error", { status: 500 })),
      vi.fn(async () => { throw new Error("network failure"); }),
      vi.fn(async () => new Response(JSON.stringify({ access_token: "only-access" }), { status: 200 }))
    ];
    for (const fetchImpl of cases) {
      const response = await request(appleApp({ fetchImpl })).post("/api/auth/apple/signin").send({ identityToken: "apple-token", nonce: "raw-nonce-value" });
      expect(response.status).toBe(401);
      expect(response.body).toEqual({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
      expect(response.text).not.toContain("provider error");
    }
  });

  it("keys Apple email buckets by caller IP instead of the empty string", async () => {
    const token = jwt("apple-user");
    const app = express().set("trust proxy", 1).use(express.json()).use("/api/auth", configuredRoutes({
      authRateLimitMaxPerEmail: 1,
      authRateLimitMaxPerIp: 10,
      fetchImpl: vi.fn(async () => new Response(JSON.stringify({ access_token: token, refresh_token: "apple-refresh" }), { status: 200 }))
    }));
    const body = { identityToken: "apple-token", nonce: "raw-nonce-value" };
    expect((await request(app).post("/api/auth/apple/signin").set("X-Forwarded-For", "203.0.113.1").send(body)).status).toBe(200);
    expect((await request(app).post("/api/auth/apple/signin").set("X-Forwarded-For", "203.0.113.2").send(body)).status).toBe(200);
  });
});
