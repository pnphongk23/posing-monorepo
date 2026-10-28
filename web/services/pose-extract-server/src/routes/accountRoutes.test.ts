import { createSign, generateKeyPairSync } from "node:crypto";
import express from "express";
import request from "supertest";
import { describe, expect, it, vi } from "vitest";

import { createApp } from "../app";
import { AccountStore, objectKeyFromLocator, type AccountRecord } from "../db/accountStore";
import { ObjectDeletionOutbox } from "../db/objectDeletionOutbox";
import { setupTestDatabase } from "../db/testDb";

const SUPABASE_URL = "https://project-ref.supabase.co";
const KEY_ID = "test-key-id";
const ACCOUNT_ID = "user-a";
const SERVICE_ROLE_KEY = "server-role-secret";
const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
const jwk = { ...publicKey.export({ format: "jwk" }), alg: "ES256", kid: KEY_ID, kty: "EC", crv: "P-256", use: "sig" };

function encode(value: unknown): string {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

function jwt(sub = ACCOUNT_ID): string {
  const input = `${encode({ alg: "ES256", typ: "JWT", kid: KEY_ID })}.${encode({ iss: `${SUPABASE_URL}/auth/v1`, aud: "authenticated", exp: 2_000_000_000, sub })}`;
  const signer = createSign("sha256");
  signer.update(input);
  signer.end();
  return `${input}.${signer.sign({ key: privateKey, dsaEncoding: "ieee-p1363" }).toString("base64url")}`;
}

interface ClockedEvent {
  label: string;
  at: number;
}

function createEventClock(): { events: ClockedEvent[]; stamp: (label: string) => void } {
  const events: ClockedEvent[] = [];
  let tick = 0;
  return {
    events,
    stamp: (label: string) => {
      tick += 1;
      events.push({ label, at: tick });
    }
  };
}

function stampOf(events: ClockedEvent[], label: string): number {
  const event = events.find((entry) => entry.label === label);
  if (!event) throw new Error(`Missing event ${label}`);
  return event.at;
}

function createMockStore(
  options: {
    locators?: string[];
    onPurge?: () => Promise<void>;
    events?: ClockedEvent[];
    stamp?: (label: string) => void;
  } = {}
): {
  store: AccountStore;
  account: AccountRecord;
  getById: ReturnType<typeof vi.fn>;
  purgeAccountData: ReturnType<typeof vi.fn>;
  getOwnedMediaLocators: ReturnType<typeof vi.fn>;
  recordPurgeIntent: ReturnType<typeof vi.fn>;
  drainObjectDeletions: ReturnType<typeof vi.fn>;
} {
  const account: AccountRecord = { id: ACCOUNT_ID, displayName: "User A", createdAt: "2026-01-01T00:00:00.000Z" };
  let present = true;
  const getById = vi.fn(async (id: string) => present && id === ACCOUNT_ID ? account : null);
  const getOwnedMediaLocators = vi.fn(async () => options.locators ?? ["account/image.png"]);
  const recordPurgeIntent = vi.fn(async () => {
    options.stamp?.("intent");
  });
  const purgeAccountData = vi.fn(async () => {
    options.stamp?.("purge");
    if (options.onPurge) await options.onPurge();
    present = false;
    return [];
  });
  const drainObjectDeletions = vi.fn(async () => {
    options.stamp?.("drain");
    return { deleted: 0, failed: 0 };
  });
  const store = {
    getById,
    getOwnedMediaLocators,
    purgeAccountData,
    recordPurgeIntent,
    drainObjectDeletions,
    upsert: vi.fn()
  } as unknown as AccountStore;
  return { store, account, getById, purgeAccountData, getOwnedMediaLocators, recordPurgeIntent, drainObjectDeletions };
}

function createDeleteApp(options: {
  serviceRoleKey?: string;
  store?: AccountStore;
  fetchImpl?: typeof fetch;
  deleteObject?: (fileKey: string) => Promise<void>;
  r2PublicUrl?: string;
} = {}): express.Express {
  const store = options.store ?? createMockStore().store;
  return createApp({
    version: "test",
    accountStore: store,
    supabaseUrl: SUPABASE_URL,
    supabaseServiceRoleKey: options.serviceRoleKey ?? SERVICE_ROLE_KEY,
    supabaseJwtKeyId: KEY_ID,
    r2PublicUrl: options.r2PublicUrl,
    fetchImpl: options.fetchImpl ?? vi.fn(async () => new Response(null, { status: 204 })),
    fetchJwks: vi.fn(async () => new Response(JSON.stringify({ keys: [jwk] }), { status: 200 })),
    deleteObject: options.deleteObject ?? (async () => undefined)
  });
}

async function seedAccountWithMedia(sql: Awaited<ReturnType<typeof setupTestDatabase>>, accountId: string, prefix: string) {
  await sql`INSERT INTO accounts (id, display_name) VALUES (${accountId}, ${accountId})`;
  const poseId = `${prefix}-pose`;
  await sql`INSERT INTO poses (pose_id, owner_account_id, name) VALUES (${poseId}, ${accountId}, ${poseId})`;
  for (const role of ["original", "skeleton", "thumbnail"] as const) {
    await sql`INSERT INTO media_assets (media_id, pose_id, role, locator)
      VALUES (${`${poseId}-${role}`}, ${poseId}, ${role}, ${`${"https://cdn.example.com"}/poses/${poseId}/${role}.png`})`;
  }
  await sql`INSERT INTO saved_entries (account_id, pose_id) VALUES (${accountId}, ${poseId})`;
  await sql`INSERT INTO extraction_jobs (id, status, source_image_base64, source_mime_type, owner_account_id)
    VALUES (${`${prefix}-job`}, 'queued', ${"c291cmNl"}, 'image/png', ${accountId})`;
}

describe("DELETE /api/account", () => {
  it("returns the exact pending-validation envelope without a service-role key", async () => {
    const fetchImpl = vi.fn();
    const mock = createMockStore();
    const response = await request(createDeleteApp({ serviceRoleKey: "", store: mock.store, fetchImpl }))
      .delete("/api/account")
      .set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(503);
    expect(response.body).toEqual({ error: { code: "AUTH_PENDING_VALIDATION", message: "Account deletion is pending runtime validation" } });
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("sends the admin REST contract and never echoes the service-role key", async () => {
    const fetchImpl = vi.fn(async () => new Response(null, { status: 204 }));
    const mock = createMockStore();
    const response = await request(createDeleteApp({ store: mock.store, fetchImpl }))
      .delete("/api/account")
      .set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(204);
    const [url, init] = fetchImpl.mock.calls[0] as [string, RequestInit];
    expect(url).toBe(`${SUPABASE_URL}/auth/v1/admin/users/${encodeURIComponent(ACCOUNT_ID)}`);
    expect(init.method).toBe("DELETE");
    expect(init.headers).toEqual({ apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` });
    expect(response.text).not.toContain(SERVICE_ROLE_KEY);
  });

  it("treats an admin 404 as success and continues the purge", async () => {
    const mock = createMockStore();
    const response = await request(createDeleteApp({
      store: mock.store,
      fetchImpl: vi.fn(async () => new Response(null, { status: 404 }))
    })).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(204);
    expect(mock.purgeAccountData).toHaveBeenCalledWith(ACCOUNT_ID, expect.objectContaining({ resolveObjectKey: expect.any(Function) }));
  });

  it("returns 503 on an admin failure without purging the account row", async () => {
    const mock = createMockStore();
    const response = await request(createDeleteApp({
      store: mock.store,
      fetchImpl: vi.fn(async () => new Response("upstream secret", { status: 500 }))
    })).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(503);
    expect(mock.purgeAccountData).not.toHaveBeenCalled();
    await expect(mock.getById(ACCOUNT_ID)).resolves.toEqual(mock.account);
    expect(response.text).not.toContain("upstream secret");
  });

  it("ignores a different account id in the body and query", async () => {
    const mock = createMockStore();
    const fetchImpl = vi.fn(async () => new Response(null, { status: 204 }));
    const response = await request(createDeleteApp({ store: mock.store, fetchImpl }))
      .delete("/api/account?id=other-account")
      .set("Authorization", `Bearer ${jwt()}`)
      .send({ id: "other-account" });

    expect(response.status).toBe(204);
    expect(fetchImpl.mock.calls[0]?.[0]).toContain(`/admin/users/${ACCOUNT_ID}`);
    expect(mock.purgeAccountData).toHaveBeenCalledWith(ACCOUNT_ID, expect.objectContaining({ resolveObjectKey: expect.any(Function) }));
  });

  it("returns an empty 204 body and makes a repeated delete fail closed at the middleware", async () => {
    const mock = createMockStore();
    const fetchImpl = vi.fn(async () => new Response(null, { status: 204 }));
    const app = createDeleteApp({ store: mock.store, fetchImpl });
    const first = await request(app).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);
    const second = await request(app).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);

    expect(first.status).toBe(204);
    expect(first.text).toBe("");
    expect(second.status).toBe(401);
    expect(second.body).toEqual({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });
});

describe("DELETE /api/account ordering", () => {
  it("confirms the identity deletion before recording the intent, purging rows, and draining objects", async () => {
    const { events, stamp } = createEventClock();
    const mock = createMockStore({ events, stamp });
    const deleteObject = vi.fn(async () => undefined);
    const fetchImpl = vi.fn(async () => {
      stamp("supabase");
      return new Response(null, { status: 204 });
    });

    const response = await request(createDeleteApp({
      store: mock.store,
      fetchImpl: fetchImpl as unknown as typeof fetch,
      deleteObject,
      r2PublicUrl: "https://cdn.example.com"
    })).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(204);
    expect(stampOf(events, "supabase")).toBeLessThan(stampOf(events, "intent"));
    expect(stampOf(events, "intent")).toBeLessThan(stampOf(events, "purge"));
    expect(stampOf(events, "purge")).toBeLessThan(stampOf(events, "drain"));
    expect(mock.recordPurgeIntent).toHaveBeenCalledWith(ACCOUNT_ID);
  });

  it("records no intent when the identity deletion fails", async () => {
    const { events, stamp } = createEventClock();
    const mock = createMockStore({ events, stamp });
    const deleteObject = vi.fn(async () => undefined);

    const response = await request(createDeleteApp({
      store: mock.store,
      fetchImpl: vi.fn(async () => new Response("upstream secret", { status: 500 })) as unknown as typeof fetch,
      deleteObject
    })).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(503);
    expect(mock.recordPurgeIntent).not.toHaveBeenCalled();
    expect(mock.purgeAccountData).not.toHaveBeenCalled();
    expect(mock.drainObjectDeletions).not.toHaveBeenCalled();
    expect(deleteObject).not.toHaveBeenCalled();
    expect(events).toEqual([]);
  });

  it("records no intent when the identity deletion throws", async () => {
    const mock = createMockStore();

    const response = await request(createDeleteApp({
      store: mock.store,
      fetchImpl: vi.fn(async () => {
        throw new Error("network down");
      }) as unknown as typeof fetch
    })).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(503);
    expect(mock.recordPurgeIntent).not.toHaveBeenCalled();
    expect(mock.purgeAccountData).not.toHaveBeenCalled();
  });

  it("fails closed with 503 and touches no object storage when the row purge throws", async () => {
    const mock = createMockStore({
      onPurge: async () => {
        throw new Error("database unavailable");
      }
    });
    const deleteObject = vi.fn(async () => undefined);

    const response = await request(createDeleteApp({
      store: mock.store,
      deleteObject,
      fetchImpl: vi.fn(async () => new Response(null, { status: 204 })) as unknown as typeof fetch
    })).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(503);
    expect(deleteObject).not.toHaveBeenCalled();
    expect(mock.recordPurgeIntent).toHaveBeenCalledTimes(1);
  });

  it("completes on a retry after the first purge failure, when the identity is already gone", async () => {
    let failFirst = true;
    const mock = createMockStore({
      onPurge: async () => {
        if (failFirst) {
          failFirst = false;
          throw new Error("database unavailable");
        }
      }
    });
    const statuses = [204, 404];
    const fetchImpl = vi.fn(async () => new Response(null, { status: statuses.shift() ?? 404 }));
    const app = createDeleteApp({ store: mock.store, fetchImpl: fetchImpl as unknown as typeof fetch });

    const first = await request(app).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);
    expect(first.status).toBe(503);

    const second = await request(app).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);
    expect(second.status).toBe(204);
    expect(mock.purgeAccountData).toHaveBeenCalledTimes(2);
  });
});

describe("DELETE /api/account storage cleanup", () => {
  it("keeps 204 when one R2 delete fails and leaves exactly that key for the outbox", async () => {
    const sql = await setupTestDatabase();
    const accountStore = new AccountStore(sql);
    await seedAccountWithMedia(sql, ACCOUNT_ID, "a");
    await seedAccountWithMedia(sql, "user-b", "b");

    const deleteObject = vi.fn(async (key: string) => {
      if (key === "poses/a-pose/skeleton.png") throw new Error("R2 unavailable");
    });

    const response = await request(createDeleteApp({
      store: accountStore,
      r2PublicUrl: "https://cdn.example.com",
      deleteObject,
      fetchImpl: vi.fn(async () => new Response(null, { status: 204 })) as unknown as typeof fetch
    })).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(204);
    expect(deleteObject).toHaveBeenCalledTimes(3);

    const outbox = new ObjectDeletionOutbox(sql);
    const rows = await outbox.list();
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ key: "poses/a-pose/skeleton.png", attempts: 1 });
    expect(rows[0]?.lastError).toContain("R2 unavailable");

    const bKeys = await sql`
      SELECT locator FROM media_assets m JOIN poses p ON p.pose_id = m.pose_id WHERE p.owner_account_id = ${"user-b"}
    `;
    expect(bKeys).toHaveLength(3);
  });

  it("removes rows and objects for the account only", async () => {
    const sql = await setupTestDatabase();
    const accountStore = new AccountStore(sql);
    await seedAccountWithMedia(sql, ACCOUNT_ID, "a");
    await seedAccountWithMedia(sql, "user-b", "b");

    const response = await request(createDeleteApp({
      store: accountStore,
      r2PublicUrl: "https://cdn.example.com",
      deleteObject: vi.fn(async () => undefined),
      fetchImpl: vi.fn(async () => new Response(null, { status: 204 })) as unknown as typeof fetch
    })).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(204);
    const remaining = await sql`
      SELECT
        (SELECT COUNT(*)::int FROM accounts WHERE id = ${ACCOUNT_ID}) AS accounts,
        (SELECT COUNT(*)::int FROM extraction_jobs WHERE owner_account_id = ${ACCOUNT_ID}) AS jobs,
        (SELECT COUNT(*)::int FROM poses WHERE owner_account_id = ${"user-b"}) AS other_poses,
        (SELECT COUNT(*)::int FROM pending_account_purges WHERE account_id = ${ACCOUNT_ID}) AS intents
    `;
    expect(remaining[0]).toEqual({ accounts: 0, jobs: 0, other_poses: 1, intents: 0 });
    expect(await new ObjectDeletionOutbox(sql).count()).toBe(0);
  });

  it("maps a stored public URL back to its object key", () => {
    expect(objectKeyFromLocator("https://cdn.example.com/poses/x/original.png", "https://cdn.example.com")).toBe(
      "poses/x/original.png"
    );
    expect(objectKeyFromLocator("poses/x/original.png", "https://cdn.example.com")).toBe("poses/x/original.png");
    expect(objectKeyFromLocator("https://other.example.com/poses/x/original.png", "https://cdn.example.com")).toBe(
      "https://other.example.com/poses/x/original.png"
    );
  });
});
