import { createSign, generateKeyPairSync } from "node:crypto";

import request from "supertest";
import { describe, expect, it, vi } from "vitest";

import { createApp } from "../app";
import type { AccountRecord, AccountStore } from "../db/accountStore";
import type { ExtractionJob, ExtractionJobStore } from "../db/extractionJobStore";

const SUPABASE_URL = "https://project-ref.supabase.co";
const KEY_ID = "test-key-id";
const ADMIN_SECRET = "admin-secret";
const ACCOUNT_A = { id: "account-aaa", displayName: "User A", createdAt: "2026-01-01T00:00:00.000Z" };
const ACCOUNT_B = { id: "account-bbb", displayName: "User B", createdAt: "2026-01-01T00:00:00.000Z" };

const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
const jwk = { ...publicKey.export({ format: "jwk" }), alg: "ES256", kid: KEY_ID, kty: "EC", crv: "P-256", use: "sig" };

function encode(value: unknown): string {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

function accountToken(accountId: string): string {
  const input = `${encode({ alg: "ES256", typ: "JWT", kid: KEY_ID })}.${encode({
    iss: `${SUPABASE_URL}/auth/v1`,
    aud: "authenticated",
    exp: 2_000_000_000,
    sub: accountId
  })}`;
  const signer = createSign("sha256");
  signer.update(input);
  signer.end();
  return `${input}.${signer.sign({ key: privateKey, dsaEncoding: "ieee-p1363" }).toString("base64url")}`;
}

const fetchJwks = vi.fn(async () => ({ ok: true, json: async () => ({ keys: [jwk] }) })) as unknown as typeof fetch;

function createAccountStore(): AccountStore {
  const accounts = new Map<string, AccountRecord>([
    [ACCOUNT_A.id, ACCOUNT_A],
    [ACCOUNT_B.id, ACCOUNT_B]
  ]);
  return {
    getById: vi.fn(async (id: string) => accounts.get(id) ?? null)
  } as unknown as AccountStore;
}

function makeJob(overrides: Partial<ExtractionJob> & Pick<ExtractionJob, "id">): ExtractionJob {
  return {
    status: "queued",
    sourceImageBase64: null,
    sourceMimeType: "image/png",
    resultImageBase64: null,
    resultMimeType: null,
    errorCode: null,
    errorMessage: null,
    attempts: 0,
    maxAttempts: 3,
    lockedAt: null,
    lockToken: null,
    createdAt: "2026-01-01T00:00:00.000Z",
    updatedAt: "2026-01-01T00:01:00.000Z",
    ownerAccountId: ACCOUNT_A.id,
    poseDraft: null,
    poseId: null,
    hiddenAt: null,
    ...overrides
  };
}

function createJobStore(jobs: ExtractionJob[]) {
  const byId = new Map(jobs.map((job) => [job.id, job]));
  const getById = vi.fn(async (id: string) => byId.get(id) ?? null);
  const getByIdForOwner = vi.fn(async (id: string, ownerAccountId: string) => {
    const found = byId.get(id);
    if (!found || found.ownerAccountId !== ownerAccountId) return null;
    return found;
  });

  return {
    store: { getById, getByIdForOwner } as unknown as ExtractionJobStore,
    getById,
    getByIdForOwner
  };
}

function buildApp(options: {
  jobStore: ExtractionJobStore;
  rateLimitMaxRequests?: number;
  rateLimitWindowMs?: number;
}) {
  return createApp({
    version: "test",
    adminSecret: ADMIN_SECRET,
    extractionJobStore: options.jobStore,
    accountStore: createAccountStore(),
    supabaseUrl: SUPABASE_URL,
    supabaseJwtKeyId: KEY_ID,
    fetchJwks,
    extractRateLimitMaxRequests: options.rateLimitMaxRequests,
    extractRateLimitWindowMs: options.rateLimitWindowMs
  });
}

describe("extractJobsRoutes", () => {
  it("returns 401 without touching the store when unauthenticated", async () => {
    const { store, getById, getByIdForOwner } = createJobStore([makeJob({ id: "job-a" })]);
    const app = buildApp({ jobStore: store });

    const res = await request(app).get("/api/extract-jobs/job-a");

    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
    expect(getById).not.toHaveBeenCalled();
    expect(getByIdForOwner).not.toHaveBeenCalled();
  });

  it("reads any job through getById for admins and returns the full payload", async () => {
    const adminJob = makeJob({
      id: "job-admin",
      status: "succeeded",
      ownerAccountId: null,
      poseId: null,
      resultImageBase64: "cmVzdWx0",
      resultMimeType: "image/png"
    });
    const { store, getById, getByIdForOwner } = createJobStore([adminJob]);
    const app = buildApp({ jobStore: store });

    const res = await request(app)
      .get("/api/extract-jobs/job-admin")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`);

    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      data: {
        jobId: "job-admin",
        status: "succeeded",
        poseId: null,
        result: { imageBase64: "cmVzdWx0", mimeType: "image/png" },
        error: null,
        updatedAt: adminJob.updatedAt
      }
    });
    expect(getById).toHaveBeenCalledWith("job-admin");
    expect(getByIdForOwner).not.toHaveBeenCalled();
  });

  it("scopes account reads to the session account id", async () => {
    const ownedJob = makeJob({ id: "job-owned", status: "processing" });
    const { store, getById, getByIdForOwner } = createJobStore([ownedJob]);
    const app = buildApp({ jobStore: store });

    const res = await request(app)
      .get("/api/extract-jobs/job-owned")
      .set("Authorization", `Bearer ${accountToken(ACCOUNT_A.id)}`);

    expect(res.status).toBe(200);
    expect(res.body.data).toMatchObject({ jobId: "job-owned", status: "processing", poseId: null, result: null, error: null });
    expect(getByIdForOwner).toHaveBeenCalledWith("job-owned", ACCOUNT_A.id);
    expect(getById).not.toHaveBeenCalled();
  });

  it("returns 404 when an account requests another account's job", async () => {
    const otherJob = makeJob({ id: "job-other", ownerAccountId: ACCOUNT_B.id });
    const { store, getById, getByIdForOwner } = createJobStore([otherJob]);
    const app = buildApp({ jobStore: store });

    const res = await request(app)
      .get("/api/extract-jobs/job-other")
      .set("Authorization", `Bearer ${accountToken(ACCOUNT_A.id)}`);

    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: { code: "JOB_NOT_FOUND", message: "Job not found" } });
    expect(getByIdForOwner).toHaveBeenCalledWith("job-other", ACCOUNT_A.id);
    expect(getById).not.toHaveBeenCalled();
  });

  it("ignores a spoofed ownerAccountId in query and body", async () => {
    const ownedJob = makeJob({ id: "job-owned" });
    const otherJob = makeJob({ id: "job-other", ownerAccountId: ACCOUNT_B.id });
    const { store, getByIdForOwner } = createJobStore([ownedJob, otherJob]);
    const app = buildApp({ jobStore: store });
    const auth = `Bearer ${accountToken(ACCOUNT_A.id)}`;

    const querySpoof = await request(app)
      .get(`/api/extract-jobs/job-other?ownerAccountId=${ACCOUNT_B.id}`)
      .set("Authorization", auth);
    expect(querySpoof.status).toBe(404);

    const bodySpoof = await request(app)
      .get("/api/extract-jobs/job-owned")
      .set("Authorization", auth)
      .send({ ownerAccountId: ACCOUNT_B.id });
    expect(bodySpoof.status).toBe(200);

    expect(getByIdForOwner).toHaveBeenNthCalledWith(1, "job-other", ACCOUNT_A.id);
    expect(getByIdForOwner).toHaveBeenNthCalledWith(2, "job-owned", ACCOUNT_A.id);
    expect(getByIdForOwner).not.toHaveBeenCalledWith(expect.anything(), ACCOUNT_B.id);
  });

  it("returns 404 for a missing job", async () => {
    const { store, getById } = createJobStore([makeJob({ id: "job-a" })]);
    const app = buildApp({ jobStore: store });

    const res = await request(app)
      .get("/api/extract-jobs/job-missing")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`);

    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: { code: "JOB_NOT_FOUND", message: "Job not found" } });
    expect(getById).toHaveBeenCalledWith("job-missing");
  });

  it("maps a store failure to the 500 error envelope", async () => {
    const getById = vi.fn(async () => {
      throw new Error("store unavailable");
    });
    const app = buildApp({ jobStore: { getById } as unknown as ExtractionJobStore });

    const res = await request(app)
      .get("/api/extract-jobs/job-a")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`);

    expect(res.status).toBe(500);
    expect(res.body).toEqual({ error: { code: "INTERNAL_SERVER_ERROR", message: "Internal server error" } });
    expect(getById).toHaveBeenCalledWith("job-a");
  });

  it("returns result null with poseId set for a materialized job", async () => {
    const materialized = makeJob({ id: "job-materialized", status: "succeeded", poseId: "pose-789" });
    const { store } = createJobStore([materialized]);
    const app = buildApp({ jobStore: store });

    const res = await request(app)
      .get("/api/extract-jobs/job-materialized")
      .set("Authorization", `Bearer ${accountToken(ACCOUNT_A.id)}`);

    expect(res.status).toBe(200);
    expect(res.body.data).toEqual({
      jobId: "job-materialized",
      status: "succeeded",
      poseId: "pose-789",
      result: null,
      error: null,
      updatedAt: materialized.updatedAt
    });
  });

  it("keeps the inline result for an owner-less legacy admin job", async () => {
    const legacyJob = makeJob({
      id: "job-legacy",
      status: "succeeded",
      ownerAccountId: null,
      resultImageBase64: "bGVnYWN5",
      resultMimeType: "image/png"
    });
    const { store } = createJobStore([legacyJob]);
    const app = buildApp({ jobStore: store });

    const res = await request(app)
      .get("/api/extract-jobs/job-legacy")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`);

    expect(res.status).toBe(200);
    expect(res.body.data.poseId).toBeNull();
    expect(res.body.data.result).toEqual({ imageBase64: "bGVnYWN5", mimeType: "image/png" });
  });

  it("returns failure details for an owner's failed job", async () => {
    const failedJob = makeJob({
      id: "job-failed",
      status: "failed",
      errorCode: "PROVIDER_ERROR",
      errorMessage: "Provider request failed"
    });
    const { store } = createJobStore([failedJob]);
    const app = buildApp({ jobStore: store });

    const res = await request(app)
      .get("/api/extract-jobs/job-failed")
      .set("Authorization", `Bearer ${accountToken(ACCOUNT_A.id)}`);

    expect(res.status).toBe(200);
    expect(res.body.data.result).toBeNull();
    expect(res.body.data.error).toEqual({ code: "PROVIDER_ERROR", message: "Provider request failed" });
  });

  it("rate limits requests beyond the configured maximum", async () => {
    const { store } = createJobStore([makeJob({ id: "job-a" })]);
    const app = buildApp({ jobStore: store, rateLimitMaxRequests: 2, rateLimitWindowMs: 60_000 });
    const auth = `Bearer ${ADMIN_SECRET}`;

    const first = await request(app).get("/api/extract-jobs/job-a").set("Authorization", auth);
    const second = await request(app).get("/api/extract-jobs/job-a").set("Authorization", auth);
    const third = await request(app).get("/api/extract-jobs/job-a").set("Authorization", auth);

    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    expect(third.status).toBe(429);
    expect(third.body).toEqual({ error: { code: "RATE_LIMITED", message: "Too many extract requests" } });
  });
});
