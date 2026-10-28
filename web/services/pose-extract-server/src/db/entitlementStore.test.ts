import { randomUUID } from "node:crypto";

import { describe, expect, it } from "vitest";

import { applySchema, createDatabase, type Sql } from "./connection";
import { EntitlementStore, isForeignKeyViolation, type EntitlementSnapshot } from "./entitlementStore";
import { setupTestDatabase } from "./testDb";

const TEST_DATABASE_URL = process.env.TEST_DATABASE_URL;
const HOUR_MS = 60 * 60 * 1000;
const BASE_MS = Date.parse("2026-02-01T00:00:00.000Z");

function snapshot(overrides: Partial<EntitlementSnapshot> = {}): EntitlementSnapshot {
  return {
    entitlementId: "premium",
    isActive: true,
    expiresAt: new Date(BASE_MS + 24 * HOUR_MS),
    productId: "com.example.premium.monthly",
    store: "app_store",
    environment: "PRODUCTION",
    upstreamAt: new Date(BASE_MS),
    syncedAt: new Date(BASE_MS),
    ...overrides
  };
}

async function createAccount(sql: Sql, accountId: string = randomUUID()): Promise<string> {
  await sql`INSERT INTO accounts (id, display_name) VALUES (${accountId}, ${accountId})`;
  return accountId;
}

async function countRows(sql: Sql, accountId: string): Promise<number> {
  const rows = (await sql`
    SELECT COUNT(*)::int AS count FROM account_entitlements WHERE account_id = ${accountId}
  `) as Array<{ count: number }>;
  return rows[0]?.count ?? 0;
}

describe("EntitlementStore", () => {
  it("keeps one unchanged row when the same snapshot is written twice", async () => {
    const sql = await setupTestDatabase();
    const store = new EntitlementStore(sql);
    const accountId = await createAccount(sql);
    const input = snapshot();

    const first = await store.upsert(accountId, input);
    const second = await store.upsert(accountId, input);

    expect(await countRows(sql, accountId)).toBe(1);
    expect(second).toEqual(first);
    expect(second).toMatchObject({
      accountId,
      entitlementId: "premium",
      isActive: true,
      expiresAt: new Date(BASE_MS + 24 * HOUR_MS).toISOString(),
      productId: "com.example.premium.monthly",
      store: "app_store",
      environment: "PRODUCTION",
      upstreamAt: new Date(BASE_MS).toISOString()
    });
  });

  it("replaces the row when a newer snapshot reports the subscription gone", async () => {
    const sql = await setupTestDatabase();
    const store = new EntitlementStore(sql);
    const accountId = await createAccount(sql);

    await store.upsert(accountId, snapshot());
    const updated = await store.upsert(
      accountId,
      snapshot({
        isActive: false,
        expiresAt: null,
        productId: null,
        store: null,
        environment: null,
        upstreamAt: new Date(BASE_MS + HOUR_MS),
        syncedAt: new Date(BASE_MS + HOUR_MS)
      })
    );

    expect(await countRows(sql, accountId)).toBe(1);
    expect(updated).toMatchObject({
      isActive: false,
      expiresAt: null,
      environment: null,
      upstreamAt: new Date(BASE_MS + HOUR_MS).toISOString()
    });
  });

  it("never lets an older snapshot overwrite a newer one that is already stored", async () => {
    const sql = await setupTestDatabase();
    const store = new EntitlementStore(sql);
    const accountId = await createAccount(sql);

    await store.upsert(
      accountId,
      snapshot({ upstreamAt: new Date(BASE_MS + 2 * HOUR_MS), syncedAt: new Date(BASE_MS + 2 * HOUR_MS) })
    );
    const afterStaleWrite = await store.upsert(
      accountId,
      snapshot({
        isActive: false,
        expiresAt: null,
        upstreamAt: new Date(BASE_MS + HOUR_MS),
        syncedAt: new Date(BASE_MS + 3 * HOUR_MS)
      })
    );

    expect(afterStaleWrite).toMatchObject({
      isActive: true,
      upstreamAt: new Date(BASE_MS + 2 * HOUR_MS).toISOString(),
      syncedAt: new Date(BASE_MS + 2 * HOUR_MS).toISOString()
    });
  });

  it("accepts a replay of the same snapshot time without changing the entitlement state", async () => {
    const sql = await setupTestDatabase();
    const store = new EntitlementStore(sql);
    const accountId = await createAccount(sql);

    await store.upsert(accountId, snapshot());
    const replayed = await store.upsert(accountId, snapshot({ syncedAt: new Date(BASE_MS + 4 * HOUR_MS) }));

    expect(await countRows(sql, accountId)).toBe(1);
    expect(replayed).toMatchObject({
      isActive: true,
      expiresAt: new Date(BASE_MS + 24 * HOUR_MS).toISOString(),
      upstreamAt: new Date(BASE_MS).toISOString()
    });
  });

  it("removes the row with the account", async () => {
    const sql = await setupTestDatabase();
    const store = new EntitlementStore(sql);
    const accountId = await createAccount(sql);

    await store.upsert(accountId, snapshot());
    await sql`DELETE FROM accounts WHERE id = ${accountId}`;

    expect(await store.get(accountId)).toBeNull();
    expect(await countRows(sql, accountId)).toBe(0);
  });

  it("rejects a row for an account that does not exist", async () => {
    const sql = await setupTestDatabase();
    const store = new EntitlementStore(sql);
    const accountId = randomUUID();

    await expect(store.upsert(accountId, snapshot())).rejects.toSatisfy(isForeignKeyViolation);
    expect(await store.get(accountId)).toBeNull();
  });
});

describe.runIf(TEST_DATABASE_URL)("ordered entitlement writes against real Postgres", () => {
  it("keeps the newer snapshot when an older one commits last on a second connection", async () => {
    const admin = createDatabase(TEST_DATABASE_URL as string);
    await applySchema(admin);
    const accountId = await createAccount(admin);
    const newerConnection = createDatabase(TEST_DATABASE_URL as string);
    const olderConnection = createDatabase(TEST_DATABASE_URL as string);
    const store = new EntitlementStore(admin);

    try {
      await store.upsert(
        accountId,
        snapshot({ upstreamAt: new Date(BASE_MS + HOUR_MS), syncedAt: new Date(BASE_MS + HOUR_MS) })
      );

      const newerUpstreamAt = new Date(BASE_MS + 3 * HOUR_MS);
      let newerWritten!: () => void;
      const newerWrittenP = new Promise<void>((resolve) => {
        newerWritten = resolve;
      });
      let releaseNewer!: () => void;
      const releaseNewerP = new Promise<void>((resolve) => {
        releaseNewer = resolve;
      });

      // The newer snapshot holds the row lock while the delayed older read is in flight.
      const newerTx = newerConnection.begin(async (tx) => {
        await new EntitlementStore(newerConnection).upsert(
          accountId,
          snapshot({
            isActive: false,
            expiresAt: null,
            upstreamAt: newerUpstreamAt,
            syncedAt: newerUpstreamAt
          }),
          tx
        );
        newerWritten();
        await releaseNewerP;
      });
      await newerWrittenP;

      const olderStore = new EntitlementStore(olderConnection);
      let olderSettled = false;
      const olderP = olderStore
        .upsert(
          accountId,
          snapshot({
            isActive: true,
            upstreamAt: new Date(BASE_MS + 2 * HOUR_MS),
            syncedAt: new Date(BASE_MS + 4 * HOUR_MS)
          })
        )
        .then((row) => {
          olderSettled = true;
          return row;
        });

      await new Promise((resolve) => setTimeout(resolve, 250));
      expect(olderSettled).toBe(false);

      releaseNewer();
      await newerTx;
      await olderP;

      const finalRow = await olderStore.get(accountId);
      expect(finalRow).toMatchObject({
        isActive: false,
        expiresAt: null,
        upstreamAt: newerUpstreamAt.toISOString(),
        syncedAt: newerUpstreamAt.toISOString()
      });
    } finally {
      await admin`DELETE FROM accounts WHERE id = ${accountId}`;
      await newerConnection.end();
      await olderConnection.end();
      await admin.end();
    }
  });
});
