import { createSign, generateKeyPairSync } from "node:crypto";
import express from "express";
import request from "supertest";
import { describe, expect, it, vi } from "vitest";

import { createApp } from "../app";
import type { AccountRecord, AccountStore } from "../db/accountStore";
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

function createMockStore(locators: string[] = ["account/image.png"]): {
  store: AccountStore;
  account: AccountRecord;
  getById: ReturnType<typeof vi.fn>;
  purgeAccountData: ReturnType<typeof vi.fn>;
  getOwnedMediaLocators: ReturnType<typeof vi.fn>;
} {
  const account: AccountRecord = { id: ACCOUNT_ID, displayName: "User A", createdAt: "2026-01-01T00:00:00.000Z" };
  let present = true;
  const getById = vi.fn(async (id: string) => present && id === ACCOUNT_ID ? account : null);
  const getOwnedMediaLocators = vi.fn(async () => locators);
  const purgeAccountData = vi.fn(async () => { present = false; });
  const store = {
    getById,
    getOwnedMediaLocators,
    purgeAccountData,
    upsert: vi.fn()
  } as unknown as AccountStore;
  return { store, account, getById, purgeAccountData, getOwnedMediaLocators };
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
    expect(mock.purgeAccountData).toHaveBeenCalledWith(ACCOUNT_ID);
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

  it("keeps 204 when one R2 delete fails and still purges the account", async () => {
    const mock = createMockStore(["https://cdn.example.com/account/image.png", "account/other.png"]);
    const deleteObject = vi.fn(async (key: string) => {
      if (key === "account/other.png") throw new Error("R2 unavailable");
    });
    const response = await request(createDeleteApp({
      store: mock.store,
      r2PublicUrl: "https://cdn.example.com",
      deleteObject,
      fetchImpl: vi.fn(async () => new Response(null, { status: 204 }))
    })).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(204);
    expect(deleteObject).toHaveBeenNthCalledWith(1, "account/image.png");
    expect(deleteObject).toHaveBeenNthCalledWith(2, "account/other.png");
    expect(mock.purgeAccountData).toHaveBeenCalledWith(ACCOUNT_ID);
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
    expect(mock.purgeAccountData).toHaveBeenCalledWith(ACCOUNT_ID);
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

  it("purges saved entries, owned poses, cascaded media, and the account in one database transaction", async () => {
    const sql = await setupTestDatabase();
    const accountStore = new (await import("../db/accountStore")).AccountStore(sql);
    await sql`INSERT INTO accounts (id, display_name) VALUES (${ACCOUNT_ID}, ${"User A"}), (${"user-b"}, ${"User B"})`;
    await sql`INSERT INTO poses (pose_id, owner_account_id, name) VALUES (${"pose-a"}, ${ACCOUNT_ID}, ${"Pose A"}), (${"pose-b"}, ${"user-b"}, ${"Pose B"})`;
    await sql`INSERT INTO media_assets (media_id, pose_id, role, locator) VALUES
      (${"media-a-original"}, ${"pose-a"}, ${"original"}, ${"account/image.png"}),
      (${"media-a-skeleton"}, ${"pose-a"}, ${"skeleton"}, ${"account/skeleton.png"}),
      (${"media-a-thumbnail"}, ${"pose-a"}, ${"thumbnail"}, ${"account/thumb.png"})`;
    await sql`INSERT INTO saved_entries (account_id, pose_id) VALUES (${ACCOUNT_ID}, ${"pose-a"}), (${"user-b"}, ${"pose-b"})`;

    const deleteObject = vi.fn(async () => undefined);
    const response = await request(createDeleteApp({
      store: accountStore,
      deleteObject,
      fetchImpl: vi.fn(async () => new Response(null, { status: 204 }))
    })).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(204);
    expect(deleteObject).toHaveBeenCalledTimes(3);
    await expect(sql`SELECT COUNT(*)::int AS count FROM saved_entries WHERE account_id = ${ACCOUNT_ID}`).resolves.toEqual([{ count: 0 }]);
    await expect(sql`SELECT COUNT(*)::int AS count FROM poses WHERE owner_account_id = ${ACCOUNT_ID}`).resolves.toEqual([{ count: 0 }]);
    await expect(sql`SELECT COUNT(*)::int AS count FROM media_assets WHERE pose_id = ${"pose-a"}`).resolves.toEqual([{ count: 0 }]);
    await expect(sql`SELECT COUNT(*)::int AS count FROM accounts WHERE id = ${ACCOUNT_ID}`).resolves.toEqual([{ count: 0 }]);
    await expect(sql`SELECT COUNT(*)::int AS count FROM accounts WHERE id = ${"user-b"}`).resolves.toEqual([{ count: 1 }]);
  });
});
