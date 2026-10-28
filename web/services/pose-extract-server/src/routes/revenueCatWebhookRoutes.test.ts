import express from "express";
import request from "supertest";
import { describe, expect, it, vi } from "vitest";

import { createApp } from "../app";
import type { AccountStore } from "../db/accountStore";
import type { EntitlementSnapshot } from "../db/entitlementStore";
import { EntitlementStore } from "../db/entitlementStore";
import { setupTestDatabase } from "../db/testDb";
import type { RevenueCatClient } from "../services/revenueCatClient";
import { accountCandidates, createRevenueCatWebhookRoutes } from "./revenueCatWebhookRoutes";

import billingIssue from "./__fixtures__/revenuecat/billing_issue.json";
import expiration from "./__fixtures__/revenuecat/expiration.json";
import initialPurchase from "./__fixtures__/revenuecat/initial_purchase.json";
import renewal from "./__fixtures__/revenuecat/renewal.json";
import testEvent from "./__fixtures__/revenuecat/test.json";
import transfer from "./__fixtures__/revenuecat/transfer.json";

const WEBHOOK_AUTH = "webhook-auth-token-for-tests-only-32";
const NOW_MS = Date.parse("2026-02-01T00:00:00.000Z");
const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

const ACCOUNT_A = "11111111-1111-4111-8111-111111111111";
const ACCOUNT_B = "22222222-2222-4222-8222-222222222222";
const ACCOUNT_C = "33333333-3333-4333-8333-333333333333";

function snapshotFor(accountId: string, overrides: Partial<EntitlementSnapshot> = {}): EntitlementSnapshot {
  return {
    entitlementId: "premium",
    isActive: true,
    expiresAt: new Date(NOW_MS + 30 * DAY_MS),
    productId: `com.example.${accountId.slice(0, 8)}.monthly`,
    store: "app_store",
    environment: "PRODUCTION",
    upstreamAt: new Date(NOW_MS),
    syncedAt: new Date(NOW_MS),
    ...overrides
  };
}

function clientFor(read: (accountId: string) => Promise<EntitlementSnapshot>): RevenueCatClient {
  return { readEntitlement: vi.fn(read) };
}

function accountStore(accountIds: readonly string[]): AccountStore {
  return {
    getById: async (id: string) =>
      accountIds.includes(id) ? { id, displayName: id, createdAt: new Date(NOW_MS).toISOString() } : null
  } as unknown as AccountStore;
}

type Sql = Awaited<ReturnType<typeof setupTestDatabase>>;

async function seedAccounts(sql: Sql, accountIds: readonly string[]): Promise<void> {
  for (const id of accountIds) {
    await sql`INSERT INTO accounts (id, display_name) VALUES (${id}, ${id})`;
  }
}

function webhookApp(options: {
  sql: Sql;
  accountIds: readonly string[];
  client: RevenueCatClient;
  store?: EntitlementStore;
}) {
  return express()
    .use(express.json())
    .use(
      "/api/webhooks/revenuecat",
      createRevenueCatWebhookRoutes({
        accountStore: accountStore(options.accountIds),
        entitlementStore: options.store ?? new EntitlementStore(options.sql),
        client: options.client,
        webhookAuth: WEBHOOK_AUTH
      })
    );
}

function post(app: express.Express, body: unknown, authorization: string | null = `Bearer ${WEBHOOK_AUTH}`) {
  const pending = request(app).post("/api/webhooks/revenuecat");
  if (authorization !== null) {
    pending.set("Authorization", authorization);
  }
  return pending.send(body as object);
}

/** The official payloads name a platform app user id; point them at a real Account. */
function forAccount(fixture: { event: Record<string, unknown> }, accountId: string): Record<string, unknown> {
  return { ...fixture.event, app_user_id: accountId, original_app_user_id: accountId };
}

function eventOf(fixture: { event: Record<string, unknown> }): Record<string, unknown> {
  return fixture.event;
}

async function countRows(sql: Sql, accountId: string): Promise<number> {
  const rows = (await sql`
    SELECT COUNT(*)::int AS count FROM account_entitlements WHERE account_id = ${accountId}
  `) as Array<{ count: number }>;
  return rows[0]?.count ?? 0;
}

describe("accountCandidates", () => {
  it("drops every anonymous install id", () => {
    expect(
      accountCandidates({
        type: "INITIAL_PURCHASE",
        app_user_id: `$RCAnonymousID:${ACCOUNT_A}`,
        original_app_user_id: `$RCAnonymousID:${ACCOUNT_C}`,
        aliases: [`$RCAnonymousID:${ACCOUNT_B}`]
      })
    ).toEqual([]);

    expect(
      accountCandidates({
        type: "EXPIRATION",
        app_user_id: ACCOUNT_A,
        original_app_user_id: `$RCAnonymousID:${ACCOUNT_C}`,
        aliases: [`$RCAnonymousID:${ACCOUNT_B}`]
      })
    ).toEqual([ACCOUNT_A]);
  });

  it("collects and de-duplicates both sides of a transfer", () => {
    expect(
      accountCandidates({
        type: "TRANSFER",
        transferred_from: [ACCOUNT_A, `$RCAnonymousID:${ACCOUNT_C}`],
        transferred_to: [ACCOUNT_B, ACCOUNT_A]
      })
    ).toEqual([ACCOUNT_A, ACCOUNT_B]);
  });
});

describe("RevenueCat webhook auth", () => {
  it("rejects a missing, a wrong and a different-length token with 401", async () => {
    const sql = await setupTestDatabase();
    const client = clientFor(async (accountId) => snapshotFor(accountId));
    const app = webhookApp({ sql, accountIds: [ACCOUNT_A], client });
    const body = eventOf(initialPurchase);

    await post(app, body, null).expect(401).expect({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
    await post(app, body, `Bearer ${"x".repeat(WEBHOOK_AUTH.length + 12)}`).expect(401);
    await post(app, body, `Bearer wrong-token-for-tests-only-32-characters`).expect(401);
    expect(client.readEntitlement).not.toHaveBeenCalled();

    await post(app, body).expect(200);
  });

  it("rejects a malformed payload with 400", async () => {
    const sql = await setupTestDatabase();
    const app = webhookApp({ sql, accountIds: [ACCOUNT_A], client: clientFor(async (id) => snapshotFor(id)) });

    await post(app, { event: { type: "INITIAL_PURCHASE" } }).expect(400);
    await post(app, { event: { type: "TRANSFER", transferred_from: [], transferred_to: [ACCOUNT_A] } }).expect(400);
    await post(app, "not-an-event").expect(400);
  });
});

describe("RevenueCat webhook handling", () => {
  it("acknowledges an anonymous-only event without calling the platform or the store", async () => {
    const sql = await setupTestDatabase();
    const client = clientFor(async (id) => snapshotFor(id));
    const store = new EntitlementStore(sql);
    const upsert = vi.spyOn(store, "upsert");
    const app = webhookApp({ sql, accountIds: [ACCOUNT_A, ACCOUNT_B], client, store });

    const response = await post(app, {
      event: {
        id: "evt-anonymous",
        type: "INITIAL_PURCHASE",
        app_user_id: "$RCAnonymousID:0083752fcb657e45dcebd4f1",
        original_app_user_id: "$RCAnonymousID:0083752fcb657e45dcebd4f1",
        aliases: ["$RCAnonymousID:0083752fcb657e45dcebd4f1"]
      }
    }).expect(200);

    expect(response.body).toEqual({ ignored: true });
    expect(client.readEntitlement).not.toHaveBeenCalled();
    expect(upsert).not.toHaveBeenCalled();
  });

  it("acknowledges an event naming no known account", async () => {
    const sql = await setupTestDatabase();
    const client = clientFor(async (id) => snapshotFor(id));
    const store = new EntitlementStore(sql);
    const upsert = vi.spyOn(store, "upsert");
    const app = webhookApp({ sql, accountIds: [ACCOUNT_A], client, store });

    const response = await post(app, {
      event: { id: "evt-unknown", type: "RENEWAL", app_user_id: "no-such-account" }
    }).expect(200);

    expect(response.body).toEqual({ ignored: true });
    expect(client.readEntitlement).not.toHaveBeenCalled();
    expect(upsert).not.toHaveBeenCalled();
  });

  it("acknowledges the platform's TEST event without touching any row", async () => {
    const sql = await setupTestDatabase();
    await seedAccounts(sql, [ACCOUNT_A]);
    const client = clientFor(async (id) => snapshotFor(id));
    const app = webhookApp({ sql, accountIds: [ACCOUNT_A], client });

    const response = await post(app, eventOf(testEvent)).expect(200);

    expect(response.body).toEqual({ ignored: true });
    expect(client.readEntitlement).not.toHaveBeenCalled();
    expect(await countRows(sql, ACCOUNT_A)).toBe(0);
  });

  it("re-reads the truth, processes a production purchase and processes a sandbox purchase", async () => {
    const sql = await setupTestDatabase();
    await seedAccounts(sql, [ACCOUNT_A]);
    const store = new EntitlementStore(sql);
    const client = clientFor(async (accountId) => snapshotFor(accountId, { environment: "SANDBOX" }));
    const app = webhookApp({ sql, accountIds: [ACCOUNT_A], client, store });

    const first = await post(app, forAccount(initialPurchase, ACCOUNT_A)).expect(200);
    expect(first.body).toEqual({ processed: 1 });
    expect(await store.get(ACCOUNT_A)).toMatchObject({ isActive: true, environment: "SANDBOX" });

    const second = await post(app, { ...forAccount(initialPurchase, ACCOUNT_A), environment: "SANDBOX" }).expect(200);
    expect(second.body).toEqual({ processed: 1 });
    expect(client.readEntitlement).toHaveBeenCalledTimes(2);
    expect(await countRows(sql, ACCOUNT_A)).toBe(1);

    const billing = await post(app, forAccount(billingIssue, ACCOUNT_A)).expect(200);
    expect(billing.body).toEqual({ processed: 1 });
    const expired = await post(app, forAccount(expiration, ACCOUNT_A)).expect(200);
    expect(expired.body).toEqual({ processed: 1 });
  });

  it("keeps one row and the same entitlement state when an event is replayed", async () => {
    const sql = await setupTestDatabase();
    await seedAccounts(sql, [ACCOUNT_A]);
    const store = new EntitlementStore(sql);
    const client = clientFor(async (accountId) => snapshotFor(accountId, { upstreamAt: new Date(NOW_MS - HOUR_MS) }));
    const upsert = vi.spyOn(store, "upsert");
    const app = webhookApp({ sql, accountIds: [ACCOUNT_A], client, store });

    await post(app, forAccount(renewal, ACCOUNT_A)).expect(200);
    await post(app, forAccount(renewal, ACCOUNT_A)).expect(200);

    expect(upsert).toHaveBeenCalledTimes(2);
    expect(upsert.mock.calls[0]?.[1]).toEqual(upsert.mock.calls[1]?.[1]);
    expect(await countRows(sql, ACCOUNT_A)).toBe(1);
    expect(await store.get(ACCOUNT_A)).toMatchObject({
      isActive: true,
      upstreamAt: new Date(NOW_MS - HOUR_MS).toISOString()
    });
  });

  it("re-syncs both sides of a transfer and leaves other accounts alone", async () => {
    const sql = await setupTestDatabase();
    await seedAccounts(sql, [ACCOUNT_A, ACCOUNT_B, ACCOUNT_C]);
    const store = new EntitlementStore(sql);
    await store.upsert(ACCOUNT_A, snapshotFor(ACCOUNT_A, { environment: "SANDBOX" }));
    await store.upsert(ACCOUNT_B, snapshotFor(ACCOUNT_B, { isActive: false, expiresAt: null }));
    await store.upsert(ACCOUNT_C, snapshotFor(ACCOUNT_C, { expiresAt: new Date(NOW_MS + 7 * DAY_MS) }));
    const client = clientFor(async (accountId) =>
      accountId === ACCOUNT_B
        ? snapshotFor(ACCOUNT_B, { upstreamAt: new Date(NOW_MS + HOUR_MS) })
        : snapshotFor(accountId, { isActive: false, expiresAt: null, upstreamAt: new Date(NOW_MS + HOUR_MS) })
    );

    const app = webhookApp({ sql, accountIds: [ACCOUNT_A, ACCOUNT_B, ACCOUNT_C], client, store });
    const response = await post(app, { ...eventOf(transfer), transferred_from: [ACCOUNT_A], transferred_to: [ACCOUNT_B] }).expect(200);

    expect(response.body).toEqual({ processed: 2 });
    expect(client.readEntitlement).toHaveBeenCalledTimes(2);
    expect(await store.get(ACCOUNT_A)).toMatchObject({ isActive: false });
    expect(await store.get(ACCOUNT_B)).toMatchObject({ isActive: true });
    expect(await store.get(ACCOUNT_C)).toMatchObject({ expiresAt: new Date(NOW_MS + 7 * DAY_MS).toISOString() });
  });

  it("syncs only the account when a transfer comes from an anonymous install", async () => {
    const sql = await setupTestDatabase();
    await seedAccounts(sql, [ACCOUNT_A]);
    const client = clientFor(async (accountId) => snapshotFor(accountId));
    const app = webhookApp({ sql, accountIds: [ACCOUNT_A], client });

    const response = await post(app, {
      event: {
        id: "evt-transfer-anon",
        type: "TRANSFER",
        transferred_from: ["$RCAnonymousID:0083752fcb657e45dcebd4f1"],
        transferred_to: [ACCOUNT_A]
      }
    }).expect(200);

    expect(response.body).toEqual({ processed: 1 });
    expect(client.readEntitlement).toHaveBeenCalledWith(ACCOUNT_A);
  });

  it("syncs the account when only its original app user id is known", async () => {
    const sql = await setupTestDatabase();
    await seedAccounts(sql, [ACCOUNT_A]);
    const client = clientFor(async (accountId) => snapshotFor(accountId));
    const app = webhookApp({ sql, accountIds: [ACCOUNT_A], client });

    const response = await post(app, {
      event: {
        id: "evt-original-only",
        type: "CANCELLATION",
        app_user_id: "$RCAnonymousID:0083752fcb657e45dcebd4f1",
        original_app_user_id: ACCOUNT_A,
        aliases: ["$RCAnonymousID:0083752fcb657e45dcebd4f1"]
      }
    }).expect(200);

    expect(response.body).toEqual({ processed: 1 });
    expect(client.readEntitlement).toHaveBeenCalledWith(ACCOUNT_A);
  });

  it("answers 503 and changes no row when the platform read fails", async () => {
    const sql = await setupTestDatabase();
    await seedAccounts(sql, [ACCOUNT_A]);
    const store = new EntitlementStore(sql);
    await store.upsert(ACCOUNT_A, snapshotFor(ACCOUNT_A));
    const client = clientFor(async () => {
      throw new Error("upstream unavailable");
    });
    const app = webhookApp({ sql, accountIds: [ACCOUNT_A], client, store });

    await post(app, forAccount(renewal, ACCOUNT_A))
      .expect(503)
      .expect({ error: { code: "ENTITLEMENT_UNAVAILABLE", message: "Entitlement service is temporarily unavailable" } });

    expect(await store.get(ACCOUNT_A)).toMatchObject({ isActive: true, syncedAt: new Date(NOW_MS).toISOString() });
  });

  it("ends active when an older expiration event arrives after a newer renewal", async () => {
    const sql = await setupTestDatabase();
    await seedAccounts(sql, [ACCOUNT_A]);
    const store = new EntitlementStore(sql);
    const readings = [
      snapshotFor(ACCOUNT_A, { upstreamAt: new Date(NOW_MS + 2 * HOUR_MS) }),
      snapshotFor(ACCOUNT_A, { upstreamAt: new Date(NOW_MS + 2 * HOUR_MS) })
    ];
    let index = 0;
    const client = clientFor(async () => readings[index++]!);
    const app = webhookApp({ sql, accountIds: [ACCOUNT_A], client, store });

    await post(app, forAccount(renewal, ACCOUNT_A)).expect(200);
    await post(app, forAccount(expiration, ACCOUNT_A)).expect(200);

    // The event type never decides the state: the re-read does, and it says active.
    expect(await store.get(ACCOUNT_A)).toMatchObject({ isActive: true });
  });

  it("accepts the bare event object as well as the wrapped payload", async () => {
    const sql = await setupTestDatabase();
    await seedAccounts(sql, [ACCOUNT_B]);
    const client = clientFor(async (accountId) => snapshotFor(accountId));
    const app = webhookApp({ sql, accountIds: [ACCOUNT_B], client });

    await post(app, { type: "RENEWAL", app_user_id: ACCOUNT_B }).expect(200);

    expect(client.readEntitlement).toHaveBeenCalledWith(ACCOUNT_B);
  });
});

describe("webhook and read refresh share one ordered writer", () => {
  const ACCOUNT = ACCOUNT_A;

  async function seed(sql: Sql, store: EntitlementStore): Promise<void> {
    await seedAccounts(sql, [ACCOUNT]);
    await store.upsert(
      ACCOUNT,
      snapshotFor(ACCOUNT, { isActive: false, expiresAt: null, upstreamAt: new Date(NOW_MS), syncedAt: new Date(NOW_MS) })
    );
  }

  it("keeps the newer webhook snapshot when the read refresh resolves an older one last", async () => {
    const sql = await setupTestDatabase();
    const store = new EntitlementStore(sql);
    await seed(sql, store);
    const newerWebhook = snapshotFor(ACCOUNT, { upstreamAt: new Date(NOW_MS + 3 * HOUR_MS) });
    const olderRefresh = snapshotFor(ACCOUNT, { isActive: false, expiresAt: null, upstreamAt: new Date(NOW_MS + 2 * HOUR_MS) });

    const webhook = webhookApp({ sql, accountIds: [ACCOUNT], client: clientFor(async () => newerWebhook), store });
    await post(webhook, forAccount(renewal, ACCOUNT)).expect(200);

    // The delayed read refresh writes last, exactly as a slow GET refresh would.
    await store.upsert(ACCOUNT, olderRefresh);

    expect(await store.get(ACCOUNT)).toMatchObject({
      isActive: true,
      upstreamAt: new Date(NOW_MS + 3 * HOUR_MS).toISOString()
    });
  });

  it("keeps the newer read refresh when a delayed webhook snapshot lands last", async () => {
    const sql = await setupTestDatabase();
    const store = new EntitlementStore(sql);
    await seed(sql, store);
    const newerRefresh = snapshotFor(ACCOUNT, { upstreamAt: new Date(NOW_MS + 3 * HOUR_MS) });
    const olderWebhook = snapshotFor(ACCOUNT, { isActive: false, expiresAt: null, upstreamAt: new Date(NOW_MS + 2 * HOUR_MS) });

    await store.upsert(ACCOUNT, newerRefresh);

    const app = webhookApp({ sql, accountIds: [ACCOUNT], client: clientFor(async () => olderWebhook), store });
    await post(app, forAccount(expiration, ACCOUNT)).expect(200);

    expect(await store.get(ACCOUNT)).toMatchObject({
      isActive: true,
      upstreamAt: new Date(NOW_MS + 3 * HOUR_MS).toISOString()
    });
  });
});

describe("webhook mount", () => {
  it("is mounted through the real app only when its token and key are configured", async () => {
    const sql = await setupTestDatabase();
    const entitlementStore = new EntitlementStore(sql);
    const accountStoreStub = accountStore([ACCOUNT_A]);
    const base = {
      version: "test",
      accountStore: accountStoreStub,
      supabaseUrl: "https://project-ref.supabase.co",
      supabaseJwtKeyId: "test-key-id",
      entitlementStore
    };

    const unconfigured = createApp({ ...base, revenueCat: {} });
    await request(unconfigured).post("/api/webhooks/revenuecat").send(forAccount(renewal, ACCOUNT_A)).expect(404);

    const configured = createApp({
      ...base,
      revenueCat: {
        secretApiKey: "rc-secret-key-for-tests",
        entitlementId: "premium",
        webhookAuth: WEBHOOK_AUTH,
        fetchImpl: vi.fn(async () => {
          throw new Error("upstream down");
        })
      }
    });
    await request(configured).post("/api/webhooks/revenuecat").send(forAccount(renewal, ACCOUNT_A)).expect(401);
  });
});
