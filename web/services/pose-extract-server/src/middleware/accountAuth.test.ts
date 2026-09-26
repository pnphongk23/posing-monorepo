import { generateKeyPairSync, createSign } from "node:crypto";
import request from "supertest";
import { describe, expect, it } from "vitest";

import { createAccountAuthMiddleware, verifyJwt } from "./accountAuth";
import type { AccountRecord, AccountStore } from "../db/accountStore";
import express from "express";

const SUPABASE_URL = "https://project-ref.supabase.co";
const KEY_ID = "test-key-id";
const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
const jwk = { ...publicKey.export({ format: "jwk" }), alg: "ES256", kid: KEY_ID.toLowerCase(), kty: "EC", crv: "P-256", use: "sig" };

function encode(value: unknown): string {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

function token(overrides: Record<string, unknown> = {}, signingKey = privateKey): string {
  const header = { alg: "ES256", typ: "JWT", kid: KEY_ID };
  const claims = { iss: `${SUPABASE_URL}/auth/v1`, aud: "authenticated", exp: 2_000_000_000, sub: "user-a", ...overrides };
  const input = `${encode(header)}.${encode(claims)}`;
  const signer = createSign("sha256");
  signer.update(input);
  signer.end();
  return `${input}.${signer.sign({ key: signingKey, dsaEncoding: "ieee-p1363" }).toString("base64url")}`;
}

function options(store: AccountStore): Parameters<typeof verifyJwt>[1] {
  return { supabaseUrl: SUPABASE_URL, keyId: KEY_ID, accountStore: store, now: () => 1_700_000_000, fetchJwks: async () => new Response(JSON.stringify({ keys: [jwk] }), { status: 200 }) };
}

const storedAccount: AccountRecord = { id: "user-a", displayName: "Stored User", createdAt: "2026-01-01T00:00:00.000Z" };
const store = { getById: async (id: string): Promise<AccountRecord | null> => id === storedAccount.id ? storedAccount : null } as AccountStore;

describe("Account JWT contract (mock JWKS; live runtime Pending-validation)", () => {
  it("accepts valid ES256 token and maps sub to one Account", async () => {
    await expect(verifyJwt(token({ name: "User A" }), options(store))).resolves.toMatchObject({ sub: "user-a" });
  });

  it.each([
    [{ exp: 1_600_000_000 }, "expired"],
    [{ iss: "https://wrong.example/auth/v1" }, "issuer"],
    [{ aud: "other" }, "audience"]
  ])("rejects %s", async (claims) => {
    await expect(verifyJwt(token(claims), options(store))).rejects.toThrow();
  });

  it("rejects a bad signature and unsupported algorithm", async () => {
    const badSignature = token({}, generateKeyPairSync("ec", { namedCurve: "P-256" }).privateKey);
    await expect(verifyJwt(badSignature, options(store))).rejects.toThrow();
    const unsupported = `${encode({ alg: "HS256", kid: KEY_ID })}.${encode({ iss: `${SUPABASE_URL}/auth/v1`, aud: "authenticated", exp: 2_000_000_000, sub: "user-a" })}.x`;
    await expect(verifyJwt(unsupported, options(store))).rejects.toThrow(/unsupported/);
    await expect(verifyJwt(token(), { ...options(store), keyId: "other" })).rejects.toThrow(/key id/);
  });

  it("returns the existing 401 envelope", async () => {
    const app = express();
    app.get("/api/account/me", createAccountAuthMiddleware(options(store)), (req, res) => res.json({ data: req.account }));
    const response = await request(app).get("/api/account/me");
    expect(response.status).toBe(401);
    expect(response.body).toEqual({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
  });

  it("returns 401 for a valid JWT when the account row is missing without upserting", async () => {
    const upsert = async (): Promise<AccountRecord> => { throw new Error("upsert must not be called"); };
    const missingStore = {
      getById: async (): Promise<AccountRecord | null> => null,
      upsert
    } as AccountStore;
    const app = express();
    app.get("/api/account/me", createAccountAuthMiddleware(options(missingStore)), (req, res) => res.json({ data: req.account }));
    const response = await request(app).get("/api/account/me").set("Authorization", `Bearer ${token()}`);
    expect(response.status).toBe(401);
    expect(response.body).toEqual({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
  });

  it("passes the stored account through for an existing row", async () => {
    const app = express();
    app.get("/api/account/me", createAccountAuthMiddleware(options(store)), (req, res) => res.json({ data: req.account }));
    const response = await request(app).get("/api/account/me").set("Authorization", `Bearer ${token()}`);
    expect(response.status).toBe(200);
    expect(response.body).toEqual({ data: storedAccount });
  });
});
