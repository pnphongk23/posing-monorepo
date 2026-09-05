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
function jwt(sub = "user-a"): string {
  const input = `${encode({ alg: "ES256", typ: "JWT", kid: KEY_ID })}.${encode({ iss: `${SUPABASE_URL}/auth/v1`, aud: "authenticated", exp: 2_000_000_000, sub, name: "Test User" })}`;
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
