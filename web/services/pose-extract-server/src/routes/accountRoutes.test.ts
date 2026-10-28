import { createSign, generateKeyPairSync } from "node:crypto";
import express from "express";
import request from "supertest";
import { describe, expect, it, vi } from "vitest";

import { createApp } from "../app";
import { AccountStore, objectKeyFromLocator, sweepStaleAccountPurges, type AccountRecord } from "../db/accountStore";
import { ObjectDeletionOutbox } from "../db/objectDeletionOutbox";
import { setupTestDatabase } from "../db/testDb";
import { APPLE_REVOKE_URL, APPLE_TOKEN_EXCHANGE_URL, type AppleSignInConfig } from "../services/appleRevocation";

const SUPABASE_URL = "https://project-ref.supabase.co";
const KEY_ID = "test-key-id";
const ACCOUNT_ID = "user-a";
const SERVICE_ROLE_KEY = "server-role-secret";
const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
const jwk = { ...publicKey.export({ format: "jwk" }), alg: "ES256", kid: KEY_ID, kty: "EC", crv: "P-256", use: "sig" };

const APPLE_CLIENT_ID = "com.example.aipose";
const APPLE_SUB = "001234.apple-subject";
const APPLE_CODE = "apple-authorization-code";
const { privateKey: applePrivateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
const APPLE_CONFIG: AppleSignInConfig = {
  teamId: "TEAMID1234",
  clientId: APPLE_CLIENT_ID,
  keyId: "APPLEKEYID",
  privateKey: applePrivateKey.export({ format: "pem", type: "pkcs8" }).toString()
};

const EMAIL_IDENTITY = { provider: "email", provider_id: ACCOUNT_ID };
const APPLE_IDENTITY = { provider: "apple", provider_id: APPLE_SUB, identity_data: { sub: APPLE_SUB } };

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

function appleIdToken(overrides: { sub?: string; aud?: string; iss?: string } = {}): string {
  return `${encode({ alg: "ES256", typ: "JWT" })}.${encode({
    iss: overrides.iss ?? "https://appleid.apple.com",
    aud: overrides.aud ?? APPLE_CLIENT_ID,
    sub: overrides.sub ?? APPLE_SUB
  })}.signature`;
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

interface FetchCall {
  method: string;
  url: string;
  headers: Record<string, string>;
}

interface SupabaseStubOptions {
  /** What the admin GET reports. `null` omits the field, as an unexpected body would. */
  identities?: unknown[] | null;
  /** Sequential admin-GET outcomes; the last one repeats. */
  getStatus?: number[];
  /** Sequential admin-DELETE outcomes; the last one repeats. */
  deleteStatus?: number[];
  /** Throw instead of answering the admin GET. */
  throwOnGet?: boolean;
  events?: ClockedEvent[];
  stamp?: (label: string) => void;
}

/** Stubs Supabase's auth admin API and records every call, so ordering is observable. */
function stubSupabase(options: SupabaseStubOptions = {}): { fetchImpl: typeof fetch; calls: FetchCall[] } {
  const getStatuses = [...(options.getStatus ?? [200])];
  const deleteStatuses = [...(options.deleteStatus ?? [204])];
  const calls: FetchCall[] = [];
  const fetchImpl = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
    const method = init?.method ?? "GET";
    calls.push({
      method,
      url: String(url),
      headers: (init?.headers ?? {}) as Record<string, string>
    });
    if (method === "GET") {
      if (options.throwOnGet) throw new Error("network down");
      const status = getStatuses.length > 1 ? getStatuses.shift()! : getStatuses[0]!;
      if (status !== 200) return new Response("upstream body", { status });
      const body = options.identities === null ? {} : { identities: options.identities ?? [EMAIL_IDENTITY] };
      return new Response(JSON.stringify(body), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    options.stamp?.("supabase-delete");
    const status = deleteStatuses.length > 1 ? deleteStatuses.shift()! : deleteStatuses[0]!;
    return new Response(status === 204 ? null : "upstream body", { status });
  }) as unknown as typeof fetch;
  return { fetchImpl, calls };
}

interface AppleStubOptions {
  exchangeStatus?: number;
  exchangeBody?: Record<string, unknown>;
  revokeStatus?: number;
  events?: ClockedEvent[];
  stamp?: (label: string) => void;
}

function stubApple(options: AppleStubOptions = {}): { fetchImpl: typeof fetch; calls: FetchCall[] } {
  const calls: FetchCall[] = [];
  const fetchImpl = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
    const target = String(url);
    calls.push({ method: init?.method ?? "POST", url: target, headers: (init?.headers ?? {}) as Record<string, string> });
    if (target === APPLE_TOKEN_EXCHANGE_URL) {
      options.stamp?.("apple-exchange");
      const status = options.exchangeStatus ?? 200;
      const body = options.exchangeBody ?? { refresh_token: "refresh-token", id_token: appleIdToken() };
      return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
    }
    if (target === APPLE_REVOKE_URL) {
      options.stamp?.("apple-revoke");
      return new Response(null, { status: options.revokeStatus ?? 200 });
    }
    throw new Error(`Unexpected Apple URL ${target}`);
  }) as unknown as typeof fetch;
  return { fetchImpl, calls };
}

function createMockStore(
  options: {
    locators?: string[];
    onPurge?: () => Promise<void>;
    onIntent?: () => Promise<void>;
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
    if (options.onIntent) await options.onIntent();
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

/** A real store whose next purge fails, so the resume path exercises the real intent row. */
class FlakyPurgeAccountStore extends AccountStore {
  failNextPurge = false;

  override async purgeAccountData(accountId: string, purgeOptions?: Parameters<AccountStore["purgeAccountData"]>[1]) {
    if (this.failNextPurge) {
      this.failNextPurge = false;
      throw new Error("database unavailable");
    }
    return super.purgeAccountData(accountId, purgeOptions);
  }
}

function createDeleteApp(options: {
  serviceRoleKey?: string;
  store?: AccountStore;
  fetchImpl?: typeof fetch;
  deleteObject?: (fileKey: string) => Promise<void>;
  r2PublicUrl?: string;
  apple?: AppleSignInConfig;
  appleFetchImpl?: typeof fetch;
} = {}): express.Express {
  const store = options.store ?? createMockStore().store;
  const supabase = options.fetchImpl ? { fetchImpl: options.fetchImpl } : stubSupabase();
  return createApp({
    version: "test",
    accountStore: store,
    supabaseUrl: SUPABASE_URL,
    supabaseServiceRoleKey: options.serviceRoleKey ?? SERVICE_ROLE_KEY,
    supabaseJwtKeyId: KEY_ID,
    r2PublicUrl: options.r2PublicUrl,
    fetchImpl: supabase.fetchImpl,
    fetchJwks: vi.fn(async () => new Response(JSON.stringify({ keys: [jwk] }), { status: 200 })),
    deleteObject: options.deleteObject ?? (async () => undefined),
    apple: options.apple,
    appleFetchImpl: options.appleFetchImpl
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

async function countAccountRows(sql: Awaited<ReturnType<typeof setupTestDatabase>>, accountId: string) {
  const rows = (await sql`
    SELECT
      (SELECT COUNT(*)::int FROM accounts WHERE id = ${accountId}) AS accounts,
      (SELECT COUNT(*)::int FROM poses WHERE owner_account_id = ${accountId}) AS poses,
      (SELECT COUNT(*)::int FROM saved_entries WHERE account_id = ${accountId}) AS saved,
      (SELECT COUNT(*)::int FROM extraction_jobs WHERE owner_account_id = ${accountId}) AS jobs,
      (SELECT COUNT(*)::int FROM pending_account_purges WHERE account_id = ${accountId}) AS intents
  `) as Array<{ accounts: number; poses: number; saved: number; jobs: number; intents: number }>;
  return rows[0]!;
}

describe("DELETE /api/account", () => {
  it("returns the exact pending-validation envelope without a service-role key", async () => {
    const mock = createMockStore();
    const supabase = stubSupabase();
    const response = await request(createDeleteApp({ serviceRoleKey: "", store: mock.store, fetchImpl: supabase.fetchImpl }))
      .delete("/api/account")
      .set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(503);
    expect(response.body).toEqual({ error: { code: "AUTH_PENDING_VALIDATION", message: "Account deletion is pending runtime validation" } });
    expect(supabase.calls).toEqual([]);
  });

  it("sends the admin REST contract and never echoes the service-role key", async () => {
    const mock = createMockStore();
    const supabase = stubSupabase();
    const response = await request(createDeleteApp({ store: mock.store, fetchImpl: supabase.fetchImpl }))
      .delete("/api/account")
      .set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(204);
    const deletes = supabase.calls.filter((call) => call.method === "DELETE");
    expect(deletes).toHaveLength(1);
    expect(deletes[0]!.url).toBe(`${SUPABASE_URL}/auth/v1/admin/users/${encodeURIComponent(ACCOUNT_ID)}`);
    expect(deletes[0]!.headers).toEqual({ apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` });
    expect(response.text).not.toContain(SERVICE_ROLE_KEY);
  });

  it("treats an admin 404 on the identity delete as success and continues the purge", async () => {
    const mock = createMockStore();
    const response = await request(createDeleteApp({ store: mock.store, fetchImpl: stubSupabase({ deleteStatus: [404] }).fetchImpl }))
      .delete("/api/account")
      .set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(204);
    expect(mock.purgeAccountData).toHaveBeenCalledWith(ACCOUNT_ID, expect.objectContaining({ resolveObjectKey: expect.any(Function) }));
  });

  it("returns 503 on an identity delete failure without purging the account row", async () => {
    const mock = createMockStore();
    const response = await request(createDeleteApp({ store: mock.store, fetchImpl: stubSupabase({ deleteStatus: [500] }).fetchImpl }))
      .delete("/api/account")
      .set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(503);
    expect(mock.purgeAccountData).not.toHaveBeenCalled();
    await expect(mock.getById(ACCOUNT_ID)).resolves.toEqual(mock.account);
    expect(response.text).not.toContain("upstream body");
  });

  it("ignores a different account id in the body and query", async () => {
    const mock = createMockStore();
    const supabase = stubSupabase();
    const response = await request(createDeleteApp({ store: mock.store, fetchImpl: supabase.fetchImpl }))
      .delete("/api/account?id=other-account")
      .set("Authorization", `Bearer ${jwt()}`)
      .send({ id: "other-account" });

    expect(response.status).toBe(204);
    expect(supabase.calls.every((call) => call.url.endsWith(`/admin/users/${ACCOUNT_ID}`))).toBe(true);
    expect(mock.purgeAccountData).toHaveBeenCalledWith(ACCOUNT_ID, expect.objectContaining({ resolveObjectKey: expect.any(Function) }));
  });

  it("returns an empty 204 body and makes a repeated delete fail closed at the middleware", async () => {
    const mock = createMockStore();
    const supabase = stubSupabase();
    const app = createDeleteApp({ store: mock.store, fetchImpl: supabase.fetchImpl });
    const first = await request(app).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);
    const second = await request(app).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);

    expect(first.status).toBe(204);
    expect(first.text).toBe("");
    expect(second.status).toBe(401);
    expect(second.body).toEqual({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
    expect(supabase.calls.filter((call) => call.method === "DELETE")).toHaveLength(1);
  });
});

describe("DELETE /api/account ordering", () => {
  it("confirms the identity deletion before recording the intent, purging rows, and draining objects", async () => {
    const { events, stamp } = createEventClock();
    const mock = createMockStore({ events, stamp });
    const deleteObject = vi.fn(async () => undefined);
    const response = await request(createDeleteApp({
      store: mock.store,
      fetchImpl: stubSupabase({ events, stamp }).fetchImpl,
      deleteObject,
      r2PublicUrl: "https://cdn.example.com"
    })).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(204);
    expect(stampOf(events, "supabase-delete")).toBeLessThan(stampOf(events, "intent"));
    expect(stampOf(events, "intent")).toBeLessThan(stampOf(events, "purge"));
    expect(stampOf(events, "purge")).toBeLessThan(stampOf(events, "drain"));
    expect(mock.recordPurgeIntent).toHaveBeenCalledWith(ACCOUNT_ID);
  });

  it("records no intent when the identity deletion fails", async () => {
    const mock = createMockStore();
    const deleteObject = vi.fn(async () => undefined);

    const response = await request(createDeleteApp({
      store: mock.store,
      fetchImpl: stubSupabase({ deleteStatus: [500] }).fetchImpl,
      deleteObject
    })).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(503);
    expect(mock.recordPurgeIntent).not.toHaveBeenCalled();
    expect(mock.purgeAccountData).not.toHaveBeenCalled();
    expect(mock.drainObjectDeletions).not.toHaveBeenCalled();
    expect(deleteObject).not.toHaveBeenCalled();
  });

  it("records no intent when the identity deletion throws", async () => {
    const mock = createMockStore();
    const fetchImpl = vi.fn(async (_url: string | URL | Request, init?: RequestInit) => {
      if ((init?.method ?? "GET") === "GET") {
        return new Response(JSON.stringify({ identities: [EMAIL_IDENTITY] }), { status: 200 });
      }
      throw new Error("network down");
    }) as unknown as typeof fetch;

    const response = await request(createDeleteApp({ store: mock.store, fetchImpl }))
      .delete("/api/account")
      .set("Authorization", `Bearer ${jwt()}`);

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
      fetchImpl: stubSupabase().fetchImpl
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
    const app = createDeleteApp({ store: mock.store, fetchImpl: stubSupabase({ getStatus: [200, 404] }).fetchImpl });

    const first = await request(app).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);
    expect(first.status).toBe(503);

    const second = await request(app).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);
    expect(second.status).toBe(204);
    expect(mock.purgeAccountData).toHaveBeenCalledTimes(2);
  });
});

describe("DELETE /api/account Apple revocation handshake", () => {
  it("demands an Apple confirmation for an Apple account before any destructive step", async () => {
    const mock = createMockStore();
    const supabase = stubSupabase({ identities: [EMAIL_IDENTITY, APPLE_IDENTITY] });
    const apple = stubApple();
    const deleteObject = vi.fn(async () => undefined);

    const response = await request(createDeleteApp({
      store: mock.store,
      fetchImpl: supabase.fetchImpl,
      apple: APPLE_CONFIG,
      appleFetchImpl: apple.fetchImpl,
      deleteObject
    })).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(409);
    expect(response.body).toEqual({
      error: { code: "APPLE_REAUTH_REQUIRED", message: "Confirm with Apple before deleting this account" }
    });
    expect(supabase.calls.filter((call) => call.method === "DELETE")).toEqual([]);
    expect(apple.calls).toEqual([]);
    expect(mock.recordPurgeIntent).not.toHaveBeenCalled();
    expect(mock.purgeAccountData).not.toHaveBeenCalled();
    expect(deleteObject).not.toHaveBeenCalled();
  });

  it("does not let the last-used provider decide: a linked Google+Apple account still needs Apple", async () => {
    const mock = createMockStore();
    const google = { provider: "google", provider_id: "google-oauth-2" };
    const supabase = stubSupabase({ identities: [APPLE_IDENTITY, google] });

    const response = await request(createDeleteApp({
      store: mock.store,
      fetchImpl: supabase.fetchImpl,
      apple: APPLE_CONFIG,
      appleFetchImpl: stubApple().fetchImpl
    })).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(409);
    expect(response.body.error.code).toBe("APPLE_REAUTH_REQUIRED");
    expect(supabase.calls.filter((call) => call.method === "DELETE")).toEqual([]);
    expect(mock.purgeAccountData).not.toHaveBeenCalled();
  });

  it("makes no Apple call at all for an account without an Apple identity", async () => {
    const mock = createMockStore();
    const apple = stubApple();
    const fetchImpl = stubSupabase({ identities: [{ provider: "google", provider_id: "google-oauth-2" }] });

    const response = await request(createDeleteApp({
      store: mock.store,
      fetchImpl: fetchImpl.fetchImpl,
      apple: APPLE_CONFIG,
      appleFetchImpl: apple.fetchImpl
    })).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(204);
    expect(apple.calls).toEqual([]);
    expect(mock.purgeAccountData).toHaveBeenCalledTimes(1);
  });

  it("revokes the Apple grant before deleting the identity, then purges", async () => {
    const { events, stamp } = createEventClock();
    const mock = createMockStore({ events, stamp });
    const supabase = stubSupabase({ identities: [APPLE_IDENTITY], events, stamp });
    const apple = stubApple({ events, stamp });

    const response = await request(createDeleteApp({
      store: mock.store,
      fetchImpl: supabase.fetchImpl,
      apple: APPLE_CONFIG,
      appleFetchImpl: apple.fetchImpl,
      r2PublicUrl: "https://cdn.example.com"
    })).delete("/api/account")
      .set("Authorization", `Bearer ${jwt()}`)
      .send({ appleAuthorizationCode: APPLE_CODE });

    expect(response.status).toBe(204);
    expect(stampOf(events, "apple-exchange")).toBeLessThan(stampOf(events, "apple-revoke"));
    expect(stampOf(events, "apple-revoke")).toBeLessThan(stampOf(events, "supabase-delete"));
    expect(stampOf(events, "supabase-delete")).toBeLessThan(stampOf(events, "intent"));
    expect(stampOf(events, "intent")).toBeLessThan(stampOf(events, "purge"));
    expect(String((apple.calls[0]!.headers as Record<string, string>)["Content-Type"])).toContain(
      "application/x-www-form-urlencoded"
    );
  });

  it("refuses a code minted for a different Apple account and deletes nothing", async () => {
    const mock = createMockStore();
    const supabase = stubSupabase({ identities: [APPLE_IDENTITY] });
    const apple = stubApple({ exchangeBody: { refresh_token: "r", id_token: appleIdToken({ sub: "another-sub" }) } });

    const response = await request(createDeleteApp({
      store: mock.store,
      fetchImpl: supabase.fetchImpl,
      apple: APPLE_CONFIG,
      appleFetchImpl: apple.fetchImpl
    })).delete("/api/account")
      .set("Authorization", `Bearer ${jwt()}`)
      .send({ appleAuthorizationCode: APPLE_CODE });

    expect(response.status).toBe(409);
    expect(response.body.error.code).toBe("APPLE_IDENTITY_MISMATCH");
    expect(apple.calls.map((call) => call.url)).toEqual([APPLE_TOKEN_EXCHANGE_URL]);
    expect(supabase.calls.filter((call) => call.method === "DELETE")).toEqual([]);
    expect(mock.purgeAccountData).not.toHaveBeenCalled();
  });

  it("reports a rejected code as needing Apple confirmation again, with nothing deleted", async () => {
    const mock = createMockStore();
    const supabase = stubSupabase({ identities: [APPLE_IDENTITY] });
    const apple = stubApple({ exchangeStatus: 400, exchangeBody: { error: "invalid_grant" } });

    const response = await request(createDeleteApp({
      store: mock.store,
      fetchImpl: supabase.fetchImpl,
      apple: APPLE_CONFIG,
      appleFetchImpl: apple.fetchImpl
    })).delete("/api/account")
      .set("Authorization", `Bearer ${jwt()}`)
      .send({ appleAuthorizationCode: APPLE_CODE });

    expect(response.status).toBe(409);
    expect(response.body.error.code).toBe("APPLE_REAUTH_REQUIRED");
    expect(mock.purgeAccountData).not.toHaveBeenCalled();
    expect(mock.recordPurgeIntent).not.toHaveBeenCalled();
  });

  it("returns 503 without deleting anything when Apple's revoke fails", async () => {
    const mock = createMockStore();
    const supabase = stubSupabase({ identities: [APPLE_IDENTITY] });

    const response = await request(createDeleteApp({
      store: mock.store,
      fetchImpl: supabase.fetchImpl,
      apple: APPLE_CONFIG,
      appleFetchImpl: stubApple({ revokeStatus: 500 }).fetchImpl
    })).delete("/api/account")
      .set("Authorization", `Bearer ${jwt()}`)
      .send({ appleAuthorizationCode: APPLE_CODE });

    expect(response.status).toBe(503);
    expect(response.body.error.code).toBe("AUTH_PENDING_VALIDATION");
    expect(supabase.calls.filter((call) => call.method === "DELETE")).toEqual([]);
    expect(mock.purgeAccountData).not.toHaveBeenCalled();
  });

  it("fails closed when the Apple env block is unset, rather than deleting without revoking", async () => {
    const mock = createMockStore();
    const supabase = stubSupabase({ identities: [APPLE_IDENTITY] });
    const apple = stubApple();

    const response = await request(createDeleteApp({
      store: mock.store,
      fetchImpl: supabase.fetchImpl,
      appleFetchImpl: apple.fetchImpl
    })).delete("/api/account")
      .set("Authorization", `Bearer ${jwt()}`)
      .send({ appleAuthorizationCode: APPLE_CODE });

    expect(response.status).toBe(503);
    expect(response.body.error.code).toBe("AUTH_PENDING_VALIDATION");
    expect(apple.calls).toEqual([]);
    expect(mock.purgeAccountData).not.toHaveBeenCalled();
  });

  it("returns 503 and touches nothing when the identity read fails upstream", async () => {
    const mock = createMockStore();
    const deleteObject = vi.fn(async () => undefined);

    for (const stub of [stubSupabase({ getStatus: [500] }), stubSupabase({ throwOnGet: true })]) {
      const response = await request(createDeleteApp({
        store: mock.store,
        fetchImpl: stub.fetchImpl,
        deleteObject
      })).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);

      expect(response.status).toBe(503);
      expect(stub.calls.filter((call) => call.method === "DELETE")).toEqual([]);
    }
    expect(mock.recordPurgeIntent).not.toHaveBeenCalled();
    expect(mock.purgeAccountData).not.toHaveBeenCalled();
    expect(deleteObject).not.toHaveBeenCalled();
  });
});

describe("DELETE /api/account Apple resume paths", () => {
  it("revokes once, then purges on a retry that finds the identity already gone", async () => {
    const sql = await setupTestDatabase();
    const accountStore = new FlakyPurgeAccountStore(sql);
    await seedAccountWithMedia(sql, ACCOUNT_ID, "a");
    accountStore.failNextPurge = true;

    const supabase = stubSupabase({ identities: [APPLE_IDENTITY], getStatus: [200, 404] });
    const apple = stubApple({ exchangeBody: { refresh_token: "r", id_token: appleIdToken() } });
    const app = createDeleteApp({
      store: accountStore,
      fetchImpl: supabase.fetchImpl,
      apple: APPLE_CONFIG,
      appleFetchImpl: apple.fetchImpl,
      r2PublicUrl: "https://cdn.example.com"
    });

    const first = await request(app).delete("/api/account")
      .set("Authorization", `Bearer ${jwt()}`)
      .send({ appleAuthorizationCode: APPLE_CODE });
    expect(first.status).toBe(503);
    // The identity delete succeeded, so the intent row is what a client-less deletion resumes from.
    expect((await countAccountRows(sql, ACCOUNT_ID)).intents).toBe(1);

    const second = await request(app).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);
    expect(second.status).toBe(204);
    expect(apple.calls).toHaveLength(2); // one exchange + one revoke, no second revoke
    expect(supabase.calls.filter((call) => call.method === "DELETE")).toHaveLength(1);

    expect(await countAccountRows(sql, ACCOUNT_ID)).toEqual({ accounts: 0, poses: 0, saved: 0, jobs: 0, intents: 0 });
  });

  it("finishes the purge from the sweeper when the client never retries", async () => {
    const sql = await setupTestDatabase();
    const accountStore = new FlakyPurgeAccountStore(sql);
    await seedAccountWithMedia(sql, ACCOUNT_ID, "a");
    accountStore.failNextPurge = true;
    const deleteObject = vi.fn(async () => undefined);

    const response = await request(createDeleteApp({
      store: accountStore,
      fetchImpl: stubSupabase({ identities: [APPLE_IDENTITY] }).fetchImpl,
      apple: APPLE_CONFIG,
      appleFetchImpl: stubApple().fetchImpl,
      deleteObject,
      r2PublicUrl: "https://cdn.example.com"
    })).delete("/api/account")
      .set("Authorization", `Bearer ${jwt()}`)
      .send({ appleAuthorizationCode: APPLE_CODE });

    expect(response.status).toBe(503);
    expect((await countAccountRows(sql, ACCOUNT_ID)).intents).toBe(1);

    const sweep = await sweepStaleAccountPurges({
      accountStore,
      outbox: accountStore.objectDeletions,
      deleteObject,
      resolveObjectKey: objectKeyFromLocator,
      olderThanSeconds: -1
    });

    expect(sweep.purgedAccounts).toEqual([ACCOUNT_ID]);
    expect(await countAccountRows(sql, ACCOUNT_ID)).toEqual({ accounts: 0, poses: 0, saved: 0, jobs: 0, intents: 0 });
    expect(deleteObject).toHaveBeenCalledTimes(3);
  });

  it("finishes the purge on a retry when only the intent insert failed", async () => {
    let failIntent = true;
    const mock = createMockStore({
      onIntent: async () => {
        if (failIntent) {
          failIntent = false;
          throw new Error("database unavailable");
        }
      }
    });
    const supabase = stubSupabase({ identities: [APPLE_IDENTITY], getStatus: [200, 404] });
    const apple = stubApple();
    const app = createDeleteApp({
      store: mock.store,
      fetchImpl: supabase.fetchImpl,
      apple: APPLE_CONFIG,
      appleFetchImpl: apple.fetchImpl
    });

    const first = await request(app).delete("/api/account")
      .set("Authorization", `Bearer ${jwt()}`)
      .send({ appleAuthorizationCode: APPLE_CODE });
    expect(first.status).toBe(503);

    const second = await request(app).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);
    expect(second.status).toBe(204);
    expect(apple.calls).toHaveLength(2);
    expect(mock.purgeAccountData).toHaveBeenCalledTimes(1);
  });
});

describe("DELETE /api/account never makes a failed attempt purge-eligible", () => {
  async function expectNothingPurged(
    sql: Awaited<ReturnType<typeof setupTestDatabase>>,
    accountStore: AccountStore,
    deleteObject: (key: string) => Promise<void>
  ) {
    expect(await countAccountRows(sql, ACCOUNT_ID)).toEqual({ accounts: 1, poses: 1, saved: 1, jobs: 1, intents: 0 });

    const sweep = await sweepStaleAccountPurges({
      accountStore,
      outbox: accountStore.objectDeletions,
      deleteObject,
      resolveObjectKey: objectKeyFromLocator,
      olderThanSeconds: -1
    });

    expect(sweep.purgedAccounts).toEqual([]);
    expect(await countAccountRows(sql, ACCOUNT_ID)).toEqual({ accounts: 1, poses: 1, saved: 1, jobs: 1, intents: 0 });
    expect(deleteObject).not.toHaveBeenCalled();
  }

  it("(a) leaves a cancelled re-auth alone", async () => {
    const sql = await setupTestDatabase();
    const accountStore = new AccountStore(sql);
    await seedAccountWithMedia(sql, ACCOUNT_ID, "a");
    const deleteObject = vi.fn(async () => undefined);

    const response = await request(createDeleteApp({
      store: accountStore,
      fetchImpl: stubSupabase({ identities: [APPLE_IDENTITY] }).fetchImpl,
      apple: APPLE_CONFIG,
      appleFetchImpl: stubApple().fetchImpl,
      deleteObject
    })).delete("/api/account").set("Authorization", `Bearer ${jwt()}`);

    expect(response.status).toBe(409);
    await expectNothingPurged(sql, accountStore, deleteObject);
  });

  it("(b) leaves a rejected authorization code alone", async () => {
    const sql = await setupTestDatabase();
    const accountStore = new AccountStore(sql);
    await seedAccountWithMedia(sql, ACCOUNT_ID, "a");
    const deleteObject = vi.fn(async () => undefined);

    const response = await request(createDeleteApp({
      store: accountStore,
      fetchImpl: stubSupabase({ identities: [APPLE_IDENTITY] }).fetchImpl,
      apple: APPLE_CONFIG,
      appleFetchImpl: stubApple({ exchangeStatus: 400, exchangeBody: { error: "invalid_grant" } }).fetchImpl,
      deleteObject
    })).delete("/api/account")
      .set("Authorization", `Bearer ${jwt()}`)
      .send({ appleAuthorizationCode: APPLE_CODE });

    expect(response.status).toBe(409);
    await expectNothingPurged(sql, accountStore, deleteObject);
  });

  it("(c) leaves an identity mismatch alone", async () => {
    const sql = await setupTestDatabase();
    const accountStore = new AccountStore(sql);
    await seedAccountWithMedia(sql, ACCOUNT_ID, "a");
    const deleteObject = vi.fn(async () => undefined);

    const response = await request(createDeleteApp({
      store: accountStore,
      fetchImpl: stubSupabase({ identities: [APPLE_IDENTITY] }).fetchImpl,
      apple: APPLE_CONFIG,
      appleFetchImpl: stubApple({ exchangeBody: { refresh_token: "r", id_token: appleIdToken({ aud: "com.example.other" }) } }).fetchImpl,
      deleteObject
    })).delete("/api/account")
      .set("Authorization", `Bearer ${jwt()}`)
      .send({ appleAuthorizationCode: APPLE_CODE });

    expect(response.status).toBe(409);
    await expectNothingPurged(sql, accountStore, deleteObject);
  });

  it("(d) leaves an Apple outage alone", async () => {
    const sql = await setupTestDatabase();
    const accountStore = new AccountStore(sql);
    await seedAccountWithMedia(sql, ACCOUNT_ID, "a");
    const deleteObject = vi.fn(async () => undefined);

    const response = await request(createDeleteApp({
      store: accountStore,
      fetchImpl: stubSupabase({ identities: [APPLE_IDENTITY] }).fetchImpl,
      apple: APPLE_CONFIG,
      appleFetchImpl: stubApple({ exchangeStatus: 503 }).fetchImpl,
      deleteObject
    })).delete("/api/account")
      .set("Authorization", `Bearer ${jwt()}`)
      .send({ appleAuthorizationCode: APPLE_CODE });

    expect(response.status).toBe(503);
    await expectNothingPurged(sql, accountStore, deleteObject);
  });

  it("(e) leaves a revoked-but-not-deleted account alone", async () => {
    const sql = await setupTestDatabase();
    const accountStore = new AccountStore(sql);
    await seedAccountWithMedia(sql, ACCOUNT_ID, "a");
    const deleteObject = vi.fn(async () => undefined);

    const response = await request(createDeleteApp({
      store: accountStore,
      fetchImpl: stubSupabase({ identities: [APPLE_IDENTITY], deleteStatus: [500] }).fetchImpl,
      apple: APPLE_CONFIG,
      appleFetchImpl: stubApple().fetchImpl,
      deleteObject
    })).delete("/api/account")
      .set("Authorization", `Bearer ${jwt()}`)
      .send({ appleAuthorizationCode: APPLE_CODE });

    expect(response.status).toBe(503);
    await expectNothingPurged(sql, accountStore, deleteObject);
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
      fetchImpl: stubSupabase().fetchImpl
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
      fetchImpl: stubSupabase().fetchImpl
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
