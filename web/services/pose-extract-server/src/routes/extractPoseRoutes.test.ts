import { createSign, generateKeyPairSync } from "node:crypto";

import request from "supertest";
import { describe, expect, it, vi } from "vitest";

import { createApp } from "../app";
import type { AccountRecord, AccountStore } from "../db/accountStore";
import { ExtractionJobStore } from "../db/extractionJobStore";
import { setupTestDatabase } from "../db/testDb";

const SUPABASE_URL = "https://project-test.supabase.co";
const JWT_KEY_ID = "test-jwt-key-id";
const ADMIN_SECRET = "test-admin-secret";
const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
const testJwk = {
  ...publicKey.export({ format: "jwk" }),
  alg: "ES256",
  kid: JWT_KEY_ID,
  kty: "EC",
  crv: "P-256",
  use: "sig"
};

function accountJwt(accountId: string): string {
  const encodePart = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const input = `${encodePart({ alg: "ES256", typ: "JWT", kid: JWT_KEY_ID })}.${encodePart({
    iss: `${SUPABASE_URL}/auth/v1`,
    aud: "authenticated",
    exp: 2_500_000_000,
    sub: accountId
  })}`;
  const signer = createSign("sha256");
  signer.update(input);
  signer.end();
  return `${input}.${signer.sign({ key: privateKey, dsaEncoding: "ieee-p1363" }).toString("base64url")}`;
}

async function createHarness() {
  const sql = await setupTestDatabase();
  const jobStore = new ExtractionJobStore(sql);

  const signedIn = new Map<string, AccountRecord>();
  const accountStore = {
    async getById(id: string) {
      return signedIn.get(id) ?? null;
    },
    async upsert(input: { id: string; displayName: string }) {
      const record: AccountRecord = { id: input.id, displayName: input.displayName, createdAt: "2026-01-01T00:00:00.000Z" };
      signedIn.set(input.id, record);
      return record;
    }
  } as unknown as AccountStore;

  const app = createApp({
    version: "test",
    adminSecret: ADMIN_SECRET,
    extractionJobStore: jobStore,
    accountStore,
    supabaseUrl: SUPABASE_URL,
    supabaseJwtKeyId: JWT_KEY_ID,
    fetchJwks: vi.fn(async () => new Response(JSON.stringify({ keys: [testJwk] }), { status: 200 })) as unknown as typeof fetch
  });

  return { sql, jobStore, accountStore, app };
}

function submit(app: ReturnType<typeof createApp>, token: string) {
  return request(app)
    .post("/api/extract-pose")
    .set("Authorization", `Bearer ${token}`)
    .field("name", "Account Pose")
    .field("tags", "balance")
    .attach("image", Buffer.from("fake-image-content"), { filename: "pose.jpg", contentType: "image/jpeg" });
}

describe("POST /api/extract-pose account admission", () => {
  it("accepts an upload from a live account", async () => {
    const { sql, accountStore, app } = await createHarness();
    await accountStore.upsert({ id: "account-a", displayName: "User A" });
    await sql`INSERT INTO accounts (id, display_name) VALUES (${"account-a"}, ${"User A"})`;

    const response = await submit(app, accountJwt("account-a"));

    expect(response.status).toBe(202);
    const rows = (await sql`SELECT owner_account_id FROM extraction_jobs`) as Array<{ owner_account_id: string }>;
    expect(rows).toEqual([{ owner_account_id: "account-a" }]);
  });

  it("answers 410 ACCOUNT_DELETED and stores nothing for a signed-in account that no longer exists", async () => {
    const { sql, accountStore, app } = await createHarness();
    await accountStore.upsert({ id: "account-a", displayName: "User A" });

    const response = await submit(app, accountJwt("account-a"));

    expect(response.status).toBe(410);
    expect(response.body).toEqual({ error: { code: "ACCOUNT_DELETED", message: "Account has been deleted" } });
    const rows = (await sql`SELECT COUNT(*)::int AS count FROM extraction_jobs`) as Array<{ count: number }>;
    expect(rows[0]?.count).toBe(0);
  });

  it("still accepts anonymous admin uploads while no account row exists", async () => {
    const { sql, app } = await createHarness();

    const response = await request(app)
      .post("/api/extract-pose")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .attach("image", Buffer.from("fake-image-content"), { filename: "pose.jpg", contentType: "image/jpeg" });

    expect(response.status).toBe(202);
    const rows = (await sql`SELECT owner_account_id FROM extraction_jobs`) as Array<{ owner_account_id: string | null }>;
    expect(rows).toEqual([{ owner_account_id: null }]);
  });
});
