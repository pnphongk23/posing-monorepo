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

const store = { upsert: async ({ id, displayName }: { id: string; displayName: string }): Promise<AccountRecord> => ({ id, displayName, createdAt: "2026-01-01T00:00:00.000Z" }) } as AccountStore;

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

  it("keeps account correlation keyed by sub (cross-account isolation contract)", async () => {
    const accounts = new Map<string, AccountRecord>();
    const isolatedStore = { upsert: async (input: { id: string; displayName: string }) => { const account = { ...input, createdAt: "2026-01-01T00:00:00.000Z" }; accounts.set(input.id, account); return account; } } as AccountStore;
    const app = express();
    app.get("/api/account/me", createAccountAuthMiddleware(options(isolatedStore)), (req, res) => res.json({ data: req.account }));
    const first = await request(app).get("/api/account/me").set("Authorization", `Bearer ${token({ sub: "user-a" })}`);
    const second = await request(app).get("/api/account/me").set("Authorization", `Bearer ${token({ sub: "user-b" })}`);
    expect(first.body.data.id).not.toBe(second.body.data.id);
    expect(accounts.size).toBe(2);
    expect(accounts.get("user-a")?.id).toBe("user-a");
    expect(accounts.get("user-b")?.id).toBe("user-b");
  });
});
