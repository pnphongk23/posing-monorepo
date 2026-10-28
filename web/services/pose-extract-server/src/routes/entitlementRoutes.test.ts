import { createSign, generateKeyPairSync } from "node:crypto";

import request from "supertest";
import { describe, expect, it, vi } from "vitest";

import { createApp } from "../app";
import type { AccountStore } from "../db/accountStore";
import type { EntitlementSnapshot } from "../db/entitlementStore";
import { createRevenueCatClient } from "../services/revenueCatClient";
import { EntitlementStore } from "../db/entitlementStore";
import { setupTestDatabase } from "../db/testDb";

const SUPABASE_URL = "https://project-ref.supabase.co";
const KEY_ID = "test-key-id";
const WEBHOOK_AUTH = "webhook-auth-token-for-tests-only-32";
const API_KEY = "rc-secret-key-for-tests";
const ENTITLEMENT_ID = "premium";
const NOW_MS = Date.parse("2026-02-01T00:00:00.000Z");
const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
const jwk = { ...publicKey.export({ format: "jwk" }), alg: "ES256", kid: KEY_ID, kty: "EC", crv: "P-256", use: "sig" };

function encode(value: unknown): string {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

function jwt(accountId: string): string {
  const input = `${encode({ alg: "ES256", typ: "JWT", kid: KEY_ID })}.${encode({
    iss: `${SUPABASE_URL}/auth/v1`,
    aud: "authenticated",
    exp: 2_000_000_000,
    sub: accountId,
    name: accountId
  })}`;
  const signer = createSign("sha256");
  signer.update(input);
  signer.end();
  return `${input}.${signer.sign({ key: privateKey, dsaEncoding: "ieee-p1363" }).toString("base64url")}`;
}

function jwksFetch(): Promise<Response> {
  return Promise.resolve(new Response(JSON.stringify({ keys: [jwk] }), { status: 200 }));
}

function accountStore(accountIds: readonly string[]): AccountStore {
  return {
    getById: async (id: string) =>
      accountIds.includes(id) ? { id, displayName: id, createdAt: new Date(NOW_MS).toISOString() } : null
  } as unknown as AccountStore;
}

function subscriberBody(input: { expiresAt: Date | null; isSandbox?: boolean; upstreamAt: Date }): Record<string, unknown> {
  const expiresDate = input.expiresAt ? input.expiresAt.toISOString() : null;
  return {
    request_date: input.upstreamAt.toISOString(),
    request_date_ms: input.upstreamAt.getTime(),
    subscriber: {
      entitlements: {
        [ENTITLEMENT_ID]: {
          expires_date: expiresDate,
          grace_period_expires_date: null,
          product_identifier: "com.example.premium.monthly",
          purchase_date: new Date(NOW_MS - 30 * DAY_MS).toISOString()
        }
      },
      subscriptions: {
        "com.example.premium.monthly": {
          expires_date: expiresDate,
          grace_period_expires_date: null,
          is_sandbox: input.isSandbox ?? false,
          store: "app_store"
        }
      }
    }
  };
}

type UpstreamHandler = (accountId: string) => { status?: number; body?: unknown } | Error;

function upstreamFetch(handler: UpstreamHandler): typeof fetch {
  return vi.fn(async (input: string | URL | Request) => {
    const accountId = decodeURIComponent(String(input).split("/v1/subscribers/")[1] ?? "");
    const result = handler(accountId);
    if (result instanceof Error) {
      throw result;
    }
    return new Response(result.body === undefined ? null : JSON.stringify(result.body), { status: result.status ?? 200 });
  }) as unknown as typeof fetch;
}

interface TestAppOptions {
  sql: Awaited<ReturnType<typeof setupTestDatabase>>;
  accountIds: readonly string[];
  now: () => number;
  fetchImpl: typeof fetch;
  configured?: boolean;
}

function testApp(options: TestAppOptions) {
  return createApp({
    version: "test",
    accountStore: accountStore(options.accountIds),
    supabaseUrl: SUPABASE_URL,
    supabaseJwtKeyId: KEY_ID,
    fetchJwks: jwksFetch,
    entitlementStore: new EntitlementStore(options.sql),
    revenueCat: options.configured === false
      ? {}
      : {
          secretApiKey: API_KEY,
          entitlementId: ENTITLEMENT_ID,
          webhookAuth: WEBHOOK_AUTH,
          fetchImpl: options.fetchImpl,
          now: options.now
        }
  });
}

function activeSnapshot(overrides: Partial<EntitlementSnapshot> = {}): EntitlementSnapshot {
  return {
    entitlementId: ENTITLEMENT_ID,
    isActive: true,
    expiresAt: new Date(NOW_MS + 30 * DAY_MS),
    productId: "com.example.premium.monthly",
    store: "app_store",
    environment: "PRODUCTION",
    upstreamAt: new Date(NOW_MS),
    syncedAt: new Date(NOW_MS),
    ...overrides
  };
}

async function seedAccount(sql: TestAppOptions["sql"], accountId: string): Promise<void> {
  await sql`INSERT INTO accounts (id, display_name) VALUES (${accountId}, ${accountId})`;
}

describe("GET /api/me/entitlement", () => {
  it("serves a fresh stored row without calling the subscription platform", async () => {
    const sql = await setupTestDatabase();
    const accountId = "11111111-1111-4111-8111-111111111111";
    await seedAccount(sql, accountId);
    const store = new EntitlementStore(sql);
    await store.upsert(accountId, activeSnapshot());
    const fetchImpl = upstreamFetch(() => new Error("must not be called"));

    const response = await request(testApp({ sql, accountIds: [accountId], now: () => NOW_MS, fetchImpl }))
      .get("/api/me/entitlement")
      .set("Authorization", `Bearer ${jwt(accountId)}`)
      .expect(200);

    expect(fetchImpl).not.toHaveBeenCalled();
    expect(response.body).toEqual({
      data: {
        entitlementId: ENTITLEMENT_ID,
        isActive: true,
        expiresAt: new Date(NOW_MS + 30 * DAY_MS).toISOString(),
        productId: "com.example.premium.monthly",
        store: "app_store",
        environment: "PRODUCTION",
        syncedAt: new Date(NOW_MS).toISOString(),
        stale: false
      }
    });
  });

  it("re-reads a row that has not been refreshed for a day", async () => {
    const sql = await setupTestDatabase();
    const accountId = "11111111-1111-4111-8111-111111111111";
    await seedAccount(sql, accountId);
    const store = new EntitlementStore(sql);
    await store.upsert(
      accountId,
      activeSnapshot({ syncedAt: new Date(NOW_MS - 25 * HOUR_MS), upstreamAt: new Date(NOW_MS - 25 * HOUR_MS) })
    );
    const upstreamAt = new Date(NOW_MS - HOUR_MS);
    const fetchImpl = upstreamFetch(() => ({ body: subscriberBody({ expiresAt: new Date(NOW_MS + 60 * DAY_MS), upstreamAt }) }));

    const response = await request(testApp({ sql, accountIds: [accountId], now: () => NOW_MS, fetchImpl }))
      .get("/api/me/entitlement")
      .set("Authorization", `Bearer ${jwt(accountId)}`)
      .expect(200);

    expect(fetchImpl).toHaveBeenCalledTimes(1);
    expect(response.body.data).toMatchObject({
      isActive: true,
      expiresAt: new Date(NOW_MS + 60 * DAY_MS).toISOString(),
      syncedAt: new Date(NOW_MS).toISOString(),
      stale: false
    });
    expect(await store.get(accountId)).toMatchObject({ upstreamAt: upstreamAt.toISOString() });
  });

  it("serves the stored row as stale when the refresh fails, expiring it fail-closed", async () => {
    const sql = await setupTestDatabase();
    const accountId = "11111111-1111-4111-8111-111111111111";
    await seedAccount(sql, accountId);
    const store = new EntitlementStore(sql);
    await store.upsert(accountId, activeSnapshot({ expiresAt: new Date(NOW_MS - HOUR_MS) }));
    const fetchImpl = upstreamFetch(() => ({ status: 500 }));

    const response = await request(testApp({ sql, accountIds: [accountId], now: () => NOW_MS, fetchImpl }))
      .get("/api/me/entitlement")
      .set("Authorization", `Bearer ${jwt(accountId)}`)
      .expect(200);

    expect(response.body.data).toMatchObject({
      isActive: false,
      expiresAt: null,
      productId: null,
      environment: null,
      stale: true
    });
    // The stored row keeps the evidence; only the served view is expired.
    expect(await store.get(accountId)).toMatchObject({ isActive: true });
  });

  it("answers inactive and stale without a row when the refresh fails", async () => {
    const sql = await setupTestDatabase();
    const accountId = "11111111-1111-4111-8111-111111111111";
    await seedAccount(sql, accountId);
    const fetchImpl = upstreamFetch(() => new Error("upstream down"));

    const response = await request(testApp({ sql, accountIds: [accountId], now: () => NOW_MS, fetchImpl }))
      .get("/api/me/entitlement")
      .set("Authorization", `Bearer ${jwt(accountId)}`)
      .expect(200);

    expect(response.body).toEqual({
      data: {
        entitlementId: ENTITLEMENT_ID,
        isActive: false,
        expiresAt: null,
        productId: null,
        store: null,
        environment: null,
        syncedAt: null,
        stale: true
      }
    });
  });

  it("requires a session", async () => {
    const sql = await setupTestDatabase();
    const app = testApp({ sql, accountIds: [], now: () => NOW_MS, fetchImpl: upstreamFetch(() => new Error("unused")) });

    await request(app).get("/api/me/entitlement").expect(401);
    await request(app).get("/api/me/entitlement").set("Authorization", "Bearer not-a-token").expect(401);
  });

  it("returns the caller's own row and ignores account selectors in the query or headers", async () => {
    const sql = await setupTestDatabase();
    const accountA = "11111111-1111-4111-8111-111111111111";
    const accountB = "22222222-2222-4222-8222-222222222222";
    await seedAccount(sql, accountA);
    await seedAccount(sql, accountB);
    const store = new EntitlementStore(sql);
    await store.upsert(accountA, activeSnapshot({ environment: "SANDBOX" }));
    await store.upsert(accountB, activeSnapshot({ isActive: false, expiresAt: null, environment: null }));

    const app = testApp({
      sql,
      accountIds: [accountA, accountB],
      now: () => NOW_MS,
      fetchImpl: upstreamFetch(() => new Error("must not be called"))
    });

    const asA = await request(app)
      .get(`/api/me/entitlement?accountId=${accountB}`)
      .set("Authorization", `Bearer ${jwt(accountA)}`)
      .set("X-Account-Id", accountB)
      .expect(200);
    expect(asA.body.data).toMatchObject({ isActive: true, environment: "SANDBOX" });

    const asB = await request(app).get("/api/me/entitlement").set("Authorization", `Bearer ${jwt(accountB)}`).expect(200);
    expect(asB.body.data).toMatchObject({ isActive: false, environment: null });
  });

  it("serves stale instead of writing when a 200 body is unreadable", async () => {
    const sql = await setupTestDatabase();
    const accountId = "11111111-1111-4111-8111-111111111111";
    await seedAccount(sql, accountId);
    const store = new EntitlementStore(sql);
    await store.upsert(accountId, activeSnapshot({ expiresAt: new Date(NOW_MS - HOUR_MS) }));
    const app = testApp({
      sql,
      accountIds: [accountId],
      now: () => NOW_MS,
      fetchImpl: (async () => new Response("{ not json", { status: 200 })) as unknown as typeof fetch
    });

    const response = await request(app)
      .get("/api/me/entitlement")
      .set("Authorization", `Bearer ${jwt(accountId)}`)
      .expect(200);

    expect(response.body.data).toMatchObject({ isActive: false, expiresAt: null, stale: true });
    expect(await store.get(accountId)).toMatchObject({ isActive: true });
  });

  it("never serves an active row cached under another entitlement id", async () => {
    const sql = await setupTestDatabase();
    const accountId = "11111111-1111-4111-8111-111111111111";
    await seedAccount(sql, accountId);
    const store = new EntitlementStore(sql);
    await store.upsert(accountId, activeSnapshot({ entitlementId: "legacy-entitlement" }));
    const failing = upstreamFetch(() => ({ status: 500 }));

    const staleResponse = await request(testApp({ sql, accountIds: [accountId], now: () => NOW_MS, fetchImpl: failing }))
      .get("/api/me/entitlement")
      .set("Authorization", `Bearer ${jwt(accountId)}`)
      .expect(200);

    expect(failing).toHaveBeenCalledTimes(1);
    expect(staleResponse.body.data).toMatchObject({
      entitlementId: ENTITLEMENT_ID,
      isActive: false,
      expiresAt: null,
      syncedAt: null,
      stale: true
    });

    const refreshed = upstreamFetch(() => ({
      body: subscriberBody({ expiresAt: new Date(NOW_MS + 15 * DAY_MS), upstreamAt: new Date(NOW_MS) })
    }));
    const refreshedResponse = await request(testApp({ sql, accountIds: [accountId], now: () => NOW_MS, fetchImpl: refreshed }))
      .get("/api/me/entitlement")
      .set("Authorization", `Bearer ${jwt(accountId)}`)
      .expect(200);

    expect(refreshedResponse.body.data).toMatchObject({
      entitlementId: ENTITLEMENT_ID,
      isActive: true,
      expiresAt: new Date(NOW_MS + 15 * DAY_MS).toISOString(),
      stale: false
    });
  });

  it("answers 503 when the feature is not configured", async () => {
    const sql = await setupTestDatabase();
    const accountId = "11111111-1111-4111-8111-111111111111";
    await seedAccount(sql, accountId);
    const app = testApp({
      sql,
      accountIds: [accountId],
      now: () => NOW_MS,
      fetchImpl: upstreamFetch(() => new Error("unused")),
      configured: false
    });

    await request(app)
      .get("/api/me/entitlement")
      .set("Authorization", `Bearer ${jwt(accountId)}`)
      .expect(503)
      .expect({ error: { code: "ENTITLEMENT_UNAVAILABLE", message: "Entitlement service is not configured" } });
    await request(app)
      .post("/api/me/entitlement/sync")
      .set("Authorization", `Bearer ${jwt(accountId)}`)
      .expect(503)
      .expect({ error: { code: "ENTITLEMENT_UNAVAILABLE", message: "Entitlement service is not configured" } });
    await request(app).post("/api/webhooks/revenuecat").expect(404);
  });
});

describe("POST /api/me/entitlement/sync", () => {
  it("forces an upstream read even when the row is fresh", async () => {
    const sql = await setupTestDatabase();
    const accountId = "11111111-1111-4111-8111-111111111111";
    await seedAccount(sql, accountId);
    const store = new EntitlementStore(sql);
    await store.upsert(accountId, activeSnapshot({ expiresAt: new Date(NOW_MS - DAY_MS), upstreamAt: new Date(NOW_MS - 3 * HOUR_MS) }));
    const upstreamAt = new Date(NOW_MS - 2 * HOUR_MS);
    const fetchImpl = upstreamFetch(() => ({
      body: subscriberBody({ expiresAt: new Date(NOW_MS + 45 * DAY_MS), isSandbox: true, upstreamAt })
    }));

    const response = await request(testApp({ sql, accountIds: [accountId], now: () => NOW_MS, fetchImpl }))
      .post("/api/me/entitlement/sync")
      .set("Authorization", `Bearer ${jwt(accountId)}`)
      .expect(200);

    expect(fetchImpl).toHaveBeenCalledTimes(1);
    expect(response.body).toEqual({
      data: {
        entitlementId: ENTITLEMENT_ID,
        isActive: true,
        expiresAt: new Date(NOW_MS + 45 * DAY_MS).toISOString(),
        productId: "com.example.premium.monthly",
        store: "app_store",
        environment: "SANDBOX",
        syncedAt: new Date(NOW_MS).toISOString(),
        stale: false
      }
    });
  });

  it("forces an upstream read for a genuinely fresh active row and stores the result", async () => {
    const sql = await setupTestDatabase();
    const accountId = "11111111-1111-4111-8111-111111111111";
    await seedAccount(sql, accountId);
    const store = new EntitlementStore(sql);
    const fresh = activeSnapshot();
    await store.upsert(accountId, fresh);
    const fetchImpl = upstreamFetch(() => ({
      body: subscriberBody({ expiresAt: new Date(NOW_MS + 90 * DAY_MS), upstreamAt: new Date(NOW_MS) })
    }));

    const response = await request(testApp({ sql, accountIds: [accountId], now: () => NOW_MS, fetchImpl }))
      .post("/api/me/entitlement/sync")
      .set("Authorization", `Bearer ${jwt(accountId)}`)
      .expect(200);

    expect(fetchImpl).toHaveBeenCalledTimes(1);
    expect(response.body.data).toMatchObject({
      isActive: true,
      expiresAt: new Date(NOW_MS + 90 * DAY_MS).toISOString()
    });
    expect(await store.get(accountId)).toMatchObject({
      expiresAt: new Date(NOW_MS + 90 * DAY_MS).toISOString()
    });
  });

  it("ignores an account id in the body, query or headers", async () => {
    const sql = await setupTestDatabase();
    const accountA = "11111111-1111-4111-8111-111111111111";
    const accountB = "22222222-2222-4222-8222-222222222222";
    await seedAccount(sql, accountA);
    await seedAccount(sql, accountB);
    const store = new EntitlementStore(sql);
    await store.upsert(accountB, activeSnapshot({ expiresAt: new Date(NOW_MS + 10 * DAY_MS) }));
    const fetchImpl = upstreamFetch((requested) => ({
      body: subscriberBody({
        expiresAt: new Date(NOW_MS + (requested === accountA ? 20 : 10) * DAY_MS),
        upstreamAt: new Date(NOW_MS)
      })
    }));

    const response = await request(testApp({ sql, accountIds: [accountA, accountB], now: () => NOW_MS, fetchImpl }))
      .post(`/api/me/entitlement/sync?accountId=${accountB}`)
      .set("Authorization", `Bearer ${jwt(accountA)}`)
      .set("X-Account-Id", accountB)
      .send({ accountId: accountB })
      .expect(200);

    expect(response.body.data).toMatchObject({ expiresAt: new Date(NOW_MS + 20 * DAY_MS).toISOString() });
    expect(await store.get(accountA)).toMatchObject({
      expiresAt: new Date(NOW_MS + 20 * DAY_MS).toISOString()
    });
    expect(await store.get(accountB)).toMatchObject({
      expiresAt: new Date(NOW_MS + 10 * DAY_MS).toISOString()
    });
  });

  it("answers 503 when a 200 body is unreadable and leaves the row untouched", async () => {
    const sql = await setupTestDatabase();
    const accountId = "11111111-1111-4111-8111-111111111111";
    await seedAccount(sql, accountId);
    const store = new EntitlementStore(sql);
    await store.upsert(accountId, activeSnapshot());
    const app = testApp({
      sql,
      accountIds: [accountId],
      now: () => NOW_MS,
      fetchImpl: (async () => new Response("[]", { status: 200 })) as unknown as typeof fetch
    });

    await request(app)
      .post("/api/me/entitlement/sync")
      .set("Authorization", `Bearer ${jwt(accountId)}`)
      .expect(503);

    expect(await store.get(accountId)).toMatchObject({ isActive: true });
  });

  it("answers 503 when the upstream read fails and leaves the row untouched", async () => {
    const sql = await setupTestDatabase();
    const accountId = "11111111-1111-4111-8111-111111111111";
    await seedAccount(sql, accountId);
    const store = new EntitlementStore(sql);
    await store.upsert(accountId, activeSnapshot());
    const fetchImpl = upstreamFetch(() => ({ status: 503 }));

    await request(testApp({ sql, accountIds: [accountId], now: () => NOW_MS, fetchImpl }))
      .post("/api/me/entitlement/sync")
      .set("Authorization", `Bearer ${jwt(accountId)}`)
      .expect(503)
      .expect({ error: { code: "ENTITLEMENT_UNAVAILABLE", message: "Entitlement service is temporarily unavailable" } });

    expect(await store.get(accountId)).toMatchObject({ isActive: true, syncedAt: new Date(NOW_MS).toISOString() });
  });

  it("rate limits reconciles to ten per minute per account", async () => {
    const sql = await setupTestDatabase();
    const accountId = "11111111-1111-4111-8111-111111111111";
    await seedAccount(sql, accountId);
    const fetchImpl = upstreamFetch(() => ({
      body: subscriberBody({ expiresAt: new Date(NOW_MS + 20 * DAY_MS), upstreamAt: new Date(NOW_MS) })
    }));
    const app = testApp({ sql, accountIds: [accountId], now: () => NOW_MS, fetchImpl });
    const token = `Bearer ${jwt(accountId)}`;

    for (let attempt = 0; attempt < 10; attempt += 1) {
      await request(app).post("/api/me/entitlement/sync").set("Authorization", token).expect(200);
    }
    await request(app)
      .post("/api/me/entitlement/sync")
      .set("Authorization", token)
      .expect(429)
      .expect({ error: { code: "RATE_LIMITED", message: "Too many entitlement sync requests" } });
  });

  it("rewrites a row cached under another entitlement id", async () => {
    const sql = await setupTestDatabase();
    const accountId = "11111111-1111-4111-8111-111111111111";
    await seedAccount(sql, accountId);
    const store = new EntitlementStore(sql);
    await store.upsert(accountId, activeSnapshot({ entitlementId: "legacy-entitlement" }));
    const fetchImpl = upstreamFetch(() => ({
      body: subscriberBody({ expiresAt: new Date(NOW_MS + 20 * DAY_MS), upstreamAt: new Date(NOW_MS) })
    }));

    await request(testApp({ sql, accountIds: [accountId], now: () => NOW_MS, fetchImpl }))
      .post("/api/me/entitlement/sync")
      .set("Authorization", `Bearer ${jwt(accountId)}`)
      .expect(200);

    expect(await store.get(accountId)).toMatchObject({ entitlementId: ENTITLEMENT_ID, isActive: true });
  });

  it("limits each account separately even when the requests share one IP", async () => {
    const sql = await setupTestDatabase();
    const accountA = "11111111-1111-4111-8111-111111111111";
    const accountB = "22222222-2222-4222-8222-222222222222";
    await seedAccount(sql, accountA);
    await seedAccount(sql, accountB);
    const fetchImpl = upstreamFetch(() => ({
      body: subscriberBody({ expiresAt: new Date(NOW_MS + 20 * DAY_MS), upstreamAt: new Date(NOW_MS) })
    }));
    const app = testApp({ sql, accountIds: [accountA, accountB], now: () => NOW_MS, fetchImpl });
    const tokenA = `Bearer ${jwt(accountA)}`;
    const tokenB = `Bearer ${jwt(accountB)}`;

    for (let attempt = 0; attempt < 10; attempt += 1) {
      await request(app).post("/api/me/entitlement/sync").set("Authorization", tokenA).expect(200);
    }

    // Same IP, other account: its own budget, so the limiter is keyed by account and not by IP.
    await request(app).post("/api/me/entitlement/sync").set("Authorization", tokenB).expect(200);
    await request(app).post("/api/me/entitlement/sync").set("Authorization", tokenA).expect(429);
  });

  it("requires a session", async () => {
    const sql = await setupTestDatabase();
    const app = testApp({ sql, accountIds: [], now: () => NOW_MS, fetchImpl: upstreamFetch(() => new Error("unused")) });

    await request(app).post("/api/me/entitlement/sync").expect(401);
  });
});
