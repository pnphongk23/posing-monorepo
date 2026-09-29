import { createSign, generateKeyPairSync } from "node:crypto";
import request from "supertest";
import { describe, expect, it, vi } from "vitest";

import { createApp } from "./app";
import { setupTestDatabase } from "./db/testDb";
import { ExtractionJobStore } from "./db/extractionJobStore";
import { PoseStore } from "./db/communityStore";
import type { AccountRecord, AccountStore } from "./db/accountStore";
import { KeyPoolManager } from "./services/keyPoolManager";
import { KeyStore } from "./services/keyStore";

function createTestImageBuffer(): Buffer {
  return Buffer.from("fake-image-content");
}

const ADMIN_SECRET = "test-admin-secret";
const SUPABASE_URL = "https://project-test.supabase.co";
const JWT_KEY_ID = "test-jwt-key-id";
const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
const testJwk = {
  ...publicKey.export({ format: "jwk" }),
  alg: "ES256",
  kid: JWT_KEY_ID.toLowerCase(),
  kty: "EC",
  crv: "P-256",
  use: "sig"
};

function makeAccountJwt(accountId: string): string {
  const header = { alg: "ES256", typ: "JWT", kid: JWT_KEY_ID };
  const claims = {
    iss: `${SUPABASE_URL}/auth/v1`,
    aud: "authenticated",
    exp: 2_500_000_000,
    sub: accountId
  };
  const encodePart = (v: unknown) => Buffer.from(JSON.stringify(v)).toString("base64url");
  const input = `${encodePart(header)}.${encodePart(claims)}`;
  const signer = createSign("sha256");
  signer.update(input);
  signer.end();
  return `${input}.${signer.sign({ key: privateKey, dsaEncoding: "ieee-p1363" }).toString("base64url")}`;
}

interface CreateExtractAppOptions {
  rateLimitWindowMs?: number;
  rateLimitMaxRequests?: number;
  includeAccounts?: boolean;
}

async function createExtractApp(options: CreateExtractAppOptions = {}) {
  const sql = await setupTestDatabase();
  const keyStore = new KeyStore(sql);
  const keyPoolManager = new KeyPoolManager(keyStore);
  const extractionJobStore = new ExtractionJobStore(sql);
  const communityStore = new PoseStore(sql);
  await keyStore.createKey({ name: "key1", apiKey: "AIza-key1" });

  const accounts = new Map<string, AccountRecord>();
  const accountStore: AccountStore = {
    async getById(id: string): Promise<AccountRecord | null> {
      return accounts.get(id) ?? null;
    },
    async upsert(record: AccountRecord): Promise<AccountRecord> {
      accounts.set(record.id, record);
      return record;
    }
  };

  if (options.includeAccounts) {
    await accountStore.upsert({ id: "account-a", displayName: "User A", createdAt: "2026-01-01T00:00:00.000Z" });
    await accountStore.upsert({ id: "account-b", displayName: "User B", createdAt: "2026-01-01T00:00:00.000Z" });
  }

  const app = createApp({
    version: "1.0.0-test",
    adminSecret: ADMIN_SECRET,
    keyStore,
    keyPoolManager,
    geminiService: {
      extractPoseImage: vi.fn()
    },
    extractionJobStore,
    communityStore,
    accountStore: options.includeAccounts ? accountStore : undefined,
    supabaseUrl: options.includeAccounts ? SUPABASE_URL : undefined,
    supabaseJwtKeyId: options.includeAccounts ? JWT_KEY_ID : undefined,
    fetchJwks: options.includeAccounts
      ? async () => new Response(JSON.stringify({ keys: [testJwk] }), { status: 200 })
      : undefined,
    extractRateLimitWindowMs: options.rateLimitWindowMs,
    extractRateLimitMaxRequests: options.rateLimitMaxRequests
  });

  return { app, extractionJobStore, communityStore, adminSecret: ADMIN_SECRET };
}

describe("POST /api/extract-pose", () => {
  it("returns UNAUTHORIZED when no auth header is provided", async () => {
    const { app } = await createExtractApp();

    const response = await request(app)
      .post("/api/extract-pose")
      .attach("image", createTestImageBuffer(), { filename: "pose.jpg", contentType: "image/jpeg" });

    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("UNAUTHORIZED");
  });

  it("returns INVALID_IMAGE when image field is missing", async () => {
    const { app, adminSecret } = await createExtractApp();

    const response = await request(app)
      .post("/api/extract-pose")
      .set("Authorization", `Bearer ${adminSecret}`);

    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe("INVALID_IMAGE");
  });

  it("returns INVALID_IMAGE for unsupported mime type", async () => {
    const { app, adminSecret } = await createExtractApp();

    const response = await request(app)
      .post("/api/extract-pose")
      .set("Authorization", `Bearer ${adminSecret}`)
      .attach("image", createTestImageBuffer(), {
        filename: "pose.gif",
        contentType: "image/gif"
      });

    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe("INVALID_IMAGE");
  });

  it("returns IMAGE_TOO_LARGE when file exceeds 10MB", async () => {
    const { app, adminSecret } = await createExtractApp();
    const tooLarge = Buffer.alloc(10 * 1024 * 1024 + 1, 1);

    const response = await request(app)
      .post("/api/extract-pose")
      .set("Authorization", `Bearer ${adminSecret}`)
      .attach("image", tooLarge, {
        filename: "large.png",
        contentType: "image/png"
      });

    expect(response.status).toBe(413);
    expect(response.body.error.code).toBe("IMAGE_TOO_LARGE");
  });

  it("returns RATE_LIMITED when endpoint rate limit is exceeded", async () => {
    const { app, adminSecret } = await createExtractApp({
      rateLimitWindowMs: 60_000,
      rateLimitMaxRequests: 1
    });

    const first = await request(app)
      .post("/api/extract-pose")
      .set("Authorization", `Bearer ${adminSecret}`)
      .attach("image", createTestImageBuffer(), { filename: "pose.jpg", contentType: "image/jpeg" });
    const second = await request(app)
      .post("/api/extract-pose")
      .set("Authorization", `Bearer ${adminSecret}`)
      .attach("image", createTestImageBuffer(), { filename: "pose.jpg", contentType: "image/jpeg" });

    expect(first.status).toBe(202);
    expect(second.status).toBe(429);
    expect(second.body.error.code).toBe("RATE_LIMITED");
  });

  it("uses forwarded-for IP for rate-limit key when trust proxy is enabled", async () => {
    const { app, adminSecret } = await createExtractApp({
      rateLimitWindowMs: 60_000,
      rateLimitMaxRequests: 1
    });

    const firstIp = await request(app)
      .post("/api/extract-pose")
      .set("Authorization", `Bearer ${adminSecret}`)
      .set("X-Forwarded-For", "203.0.113.10")
      .attach("image", createTestImageBuffer(), { filename: "pose.jpg", contentType: "image/jpeg" });

    const secondIp = await request(app)
      .post("/api/extract-pose")
      .set("Authorization", `Bearer ${adminSecret}`)
      .set("X-Forwarded-For", "198.51.100.8")
      .attach("image", createTestImageBuffer(), { filename: "pose.jpg", contentType: "image/jpeg" });

    expect(firstIp.status).toBe(202);
    expect(secondIp.status).toBe(202);
  });

  it("enqueues extraction job and returns 202 with poll URL", async () => {
    const { app, extractionJobStore, adminSecret } = await createExtractApp();

    const response = await request(app)
      .post("/api/extract-pose")
      .set("Authorization", `Bearer ${adminSecret}`)
      .attach("image", createTestImageBuffer(), { filename: "pose.jpg", contentType: "image/jpeg" });

    expect(response.status).toBe(202);
    expect(response.body.success).toBe(true);
    expect(response.body.data.status).toBe("queued");
    expect(response.body.data.jobId).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    );
    expect(response.body.meta.pollUrl).toBe(`/api/extract-jobs/${response.body.data.jobId}`);

    const job = await extractionJobStore.getById(response.body.data.jobId);
    expect(job?.status).toBe("queued");
    expect(job?.sourceMimeType).toBe("image/jpeg");
  });

  it("validates account metadata requirements on submit", async () => {
    const { app } = await createExtractApp({ includeAccounts: true });
    const tokenA = makeAccountJwt("account-a");

    // Missing name
    const missingName = await request(app)
      .post("/api/extract-pose")
      .set("Authorization", `Bearer ${tokenA}`)
      .field("tags", "standing")
      .attach("image", createTestImageBuffer(), { filename: "pose.jpg", contentType: "image/jpeg" });
    expect(missingName.status).toBe(400);
    expect(missingName.body.error.code).toBe("INVALID_METADATA");

    // Missing tags
    const missingTags = await request(app)
      .post("/api/extract-pose")
      .set("Authorization", `Bearer ${tokenA}`)
      .field("name", "Valid Name")
      .attach("image", createTestImageBuffer(), { filename: "pose.jpg", contentType: "image/jpeg" });
    expect(missingTags.status).toBe(400);
    expect(missingTags.body.error.code).toBe("INVALID_METADATA");

    // Name too long (> 80)
    const longName = await request(app)
      .post("/api/extract-pose")
      .set("Authorization", `Bearer ${tokenA}`)
      .field("name", "A".repeat(81))
      .field("tags", "yoga")
      .attach("image", createTestImageBuffer(), { filename: "pose.jpg", contentType: "image/jpeg" });
    expect(longName.status).toBe(400);
    expect(longName.body.error.code).toBe("INVALID_METADATA");

    // Description too long (> 500)
    const longDesc = await request(app)
      .post("/api/extract-pose")
      .set("Authorization", `Bearer ${tokenA}`)
      .field("name", "Valid Name")
      .field("tags", "yoga")
      .field("description", "D".repeat(501))
      .attach("image", createTestImageBuffer(), { filename: "pose.jpg", contentType: "image/jpeg" });
    expect(longDesc.status).toBe(400);
    expect(longDesc.body.error.code).toBe("INVALID_METADATA");

    // Successful submit with JSON array tags
    const okJsonTags = await request(app)
      .post("/api/extract-pose")
      .set("Authorization", `Bearer ${tokenA}`)
      .field("name", "Account Pose")
      .field("tags", JSON.stringify(["yoga", "beginner"]))
      .field("description", "Simple description")
      .attach("image", createTestImageBuffer(), { filename: "pose.jpg", contentType: "image/jpeg" });
    expect(okJsonTags.status).toBe(202);
    expect(okJsonTags.body.success).toBe(true);

    // Successful submit with repeated tags fields
    const okRepeatedTags = await request(app)
      .post("/api/extract-pose")
      .set("Authorization", `Bearer ${tokenA}`)
      .field("name", "Account Pose 2")
      .field("tags", "tag-one")
      .field("tags", "tag-two")
      .attach("image", createTestImageBuffer(), { filename: "pose.jpg", contentType: "image/jpeg" });
    expect(okRepeatedTags.status).toBe(202);
  });
});

describe("GET /api/extract-jobs/:jobId", () => {
  it("returns public job status without admin-only fields", async () => {
    const { app, extractionJobStore, adminSecret } = await createExtractApp();
    const job = await extractionJobStore.enqueue({
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });

    const response = await request(app)
      .get(`/api/extract-jobs/${job.id}`)
      .set("Authorization", `Bearer ${adminSecret}`);

    expect(response.status).toBe(200);
    expect(response.body.data).toMatchObject({
      jobId: job.id,
      status: "queued",
      result: null,
      error: null
    });
    expect(response.body.data.attempts).toBeUndefined();
    expect(response.body.data.maxAttempts).toBeUndefined();
  });

  it("returns succeeded result when job completes", async () => {
    const { app, extractionJobStore, adminSecret } = await createExtractApp();
    const job = await extractionJobStore.enqueue({
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });
    const lockToken = "test-lock-token";
    await extractionJobStore.claimNext(lockToken, 120);
    await extractionJobStore.markSucceeded(job.id, lockToken, "cG9zZQ==", "image/png");

    const response = await request(app)
      .get(`/api/extract-jobs/${job.id}`)
      .set("Authorization", `Bearer ${adminSecret}`);

    expect(response.status).toBe(200);
    expect(response.body.data.status).toBe("succeeded");
    expect(response.body.data.result).toEqual({
      imageBase64: "cG9zZQ==",
      mimeType: "image/png"
    });
  });

  it("returns provider error when job fails after max attempts", async () => {
    const { app, extractionJobStore, adminSecret } = await createExtractApp();
    const job = await extractionJobStore.enqueue({
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png",
      maxAttempts: 1
    });
    const lockToken = "test-lock-token";
    await extractionJobStore.claimNext(lockToken, 120);
    await extractionJobStore.markFailedOrRequeue(job.id, lockToken, "PROVIDER_AUTH_REQUIRED", "Provider authentication required");

    const response = await request(app)
      .get(`/api/extract-jobs/${job.id}`)
      .set("Authorization", `Bearer ${adminSecret}`);

    expect(response.status).toBe(200);
    expect(response.body.data.status).toBe("failed");
    expect(response.body.data.result).toBeNull();
    expect(response.body.data.error).toEqual({
      code: "PROVIDER_AUTH_REQUIRED",
      message: "Provider authentication required"
    });
  });
});

describe("Two-account owner isolation (A/B) integration suite", () => {
  it("enforces strict owner isolation across jobs, listings, retries, hides, and guide reads", async () => {
    const { app, extractionJobStore, communityStore, adminSecret } = await createExtractApp({ includeAccounts: true });
    const tokenA = makeAccountJwt("account-a");
    const tokenB = makeAccountJwt("account-b");

    // 1. Account A submits a job
    const submitRes = await request(app)
      .post("/api/extract-pose")
      .set("Authorization", `Bearer ${tokenA}`)
      .field("name", "Yoga Tree")
      .field("tags", JSON.stringify(["yoga", "standing"]))
      .field("description", "Tree pose draft")
      .attach("image", createTestImageBuffer(), { filename: "pose.jpg", contentType: "image/jpeg" });

    expect(submitRes.status).toBe(202);
    const jobAId = submitRes.body.data.jobId;

    // 2. GET /api/extract-jobs/:jobId owner isolation
    // Account A can see it
    const getResA = await request(app)
      .get(`/api/extract-jobs/${jobAId}`)
      .set("Authorization", `Bearer ${tokenA}`);
    expect(getResA.status).toBe(200);
    expect(getResA.body.data.jobId).toBe(jobAId);

    // Account B gets 404
    const getResB = await request(app)
      .get(`/api/extract-jobs/${jobAId}`)
      .set("Authorization", `Bearer ${tokenB}`);
    expect(getResB.status).toBe(404);
    expect(getResB.body.error.code).toBe("JOB_NOT_FOUND");

    // Admin sees it
    const getResAdmin = await request(app)
      .get(`/api/extract-jobs/${jobAId}`)
      .set("Authorization", `Bearer ${adminSecret}`);
    expect(getResAdmin.status).toBe(200);

    // 3. GET /api/me/extract-jobs isolation & query validation
    // Account A sees 1 job
    const listA = await request(app)
      .get("/api/me/extract-jobs")
      .set("Authorization", `Bearer ${tokenA}`);
    expect(listA.status).toBe(200);
    expect(listA.body.data).toHaveLength(1);
    expect(listA.body.data[0].jobId).toBe(jobAId);
    expect(listA.body.data[0].poseDraft).toEqual({
      name: "Yoga Tree",
      tags: ["yoga", "standing"],
      description: "Tree pose draft"
    });

    // Account B sees 0 jobs
    const listB = await request(app)
      .get("/api/me/extract-jobs")
      .set("Authorization", `Bearer ${tokenB}`);
    expect(listB.status).toBe(200);
    expect(listB.body.data).toHaveLength(0);

    // Query validation (limit / cursor / state)
    const badLimit = await request(app)
      .get("/api/me/extract-jobs?limit=101")
      .set("Authorization", `Bearer ${tokenA}`);
    expect(badLimit.status).toBe(400);

    const badCursor = await request(app)
      .get("/api/me/extract-jobs?cursor=invalid-cursor")
      .set("Authorization", `Bearer ${tokenA}`);
    expect(badCursor.status).toBe(400);

    // 4. Retry behavior:
    // When active, retry returns 409
    const retryActive = await request(app)
      .post(`/api/me/extract-jobs/${jobAId}/retry`)
      .set("Authorization", `Bearer ${tokenA}`);
    expect(retryActive.status).toBe(409);
    expect(retryActive.body.error.code).toBe("JOB_NOT_RETRYABLE");

    // Fail the job intentionally (3 attempts to reach max_attempts)
    const lockToken1 = "lock-tok-1";
    await extractionJobStore.claimNext(lockToken1, 120);
    await extractionJobStore.markFailedOrRequeue(jobAId, lockToken1, "PROVIDER_ERROR", "Failed");

    const lockToken2 = "lock-tok-2";
    await extractionJobStore.claimNext(lockToken2, 120);
    await extractionJobStore.markFailedOrRequeue(jobAId, lockToken2, "PROVIDER_ERROR", "Failed");

    const lockToken3 = "lock-tok-3";
    await extractionJobStore.claimNext(lockToken3, 120);
    await extractionJobStore.markFailedOrRequeue(jobAId, lockToken3, "PROVIDER_ERROR", "Failed");

    // Account B trying to retry Account A's failed job -> 404
    const retryB = await request(app)
      .post(`/api/me/extract-jobs/${jobAId}/retry`)
      .set("Authorization", `Bearer ${tokenB}`);
    expect(retryB.status).toBe(404);

    // Account A retrying its failed job -> 202
    const retryA = await request(app)
      .post(`/api/me/extract-jobs/${jobAId}/retry`)
      .set("Authorization", `Bearer ${tokenA}`);
    expect(retryA.status).toBe(202);
    expect(retryA.body.data.status).toBe("queued");

    // 5. DELETE /api/me/extract-jobs/:id (hide)
    // Account B hiding Account A's job -> 404
    const hideB = await request(app)
      .delete(`/api/me/extract-jobs/${jobAId}`)
      .set("Authorization", `Bearer ${tokenB}`);
    expect(hideB.status).toBe(404);

    // Account A hides its job -> 204
    const hideA = await request(app)
      .delete(`/api/me/extract-jobs/${jobAId}`)
      .set("Authorization", `Bearer ${tokenA}`);
    expect(hideA.status).toBe(204);

    // Subsequent listing excludes the hidden job
    const listAAfterHide = await request(app)
      .get("/api/me/extract-jobs")
      .set("Authorization", `Bearer ${tokenA}`);
    expect(listAAfterHide.status).toBe(200);
    expect(listAAfterHide.body.data).toHaveLength(0);

    // 6. GET /api/guides/:id owner isolation
    const createdPoseA = await communityStore.createPose({
      ownerAccountId: "account-a",
      name: "Warrior Pose",
      originalUrl: "https://r2.example.com/orig.jpg",
      skeletonUrl: "https://r2.example.com/skel.png",
      thumbnailUrl: "https://r2.example.com/thumb.jpg",
      tags: ["standing", "yoga"],
      difficulty: "intermediate",
      description: "A great warrior pose",
      bodyParts: ["legs", "arms"]
    });

    // Anonymous -> 401
    const guideAnon = await request(app).get(`/api/guides/${createdPoseA.poseId}`);
    expect(guideAnon.status).toBe(401);

    // Account B -> 404
    const guideB = await request(app)
      .get(`/api/guides/${createdPoseA.poseId}`)
      .set("Authorization", `Bearer ${tokenB}`);
    expect(guideB.status).toBe(404);
    expect(guideB.body.error.code).toBe("NOT_FOUND");

    // Account A -> 200 with Pose schema & media URLs
    const guideA = await request(app)
      .get(`/api/guides/${createdPoseA.poseId}`)
      .set("Authorization", `Bearer ${tokenA}`);
    expect(guideA.status).toBe(200);
    expect(guideA.body.data).toEqual({
      poseId: createdPoseA.poseId,
      ownerAccountId: "account-a",
      name: "Warrior Pose",
      description: "A great warrior pose",
      tags: ["standing", "yoga"],
      difficulty: "intermediate",
      bodyParts: ["legs", "arms"],
      status: "local",
      originalUrl: "https://r2.example.com/orig.jpg",
      skeletonUrl: "https://r2.example.com/skel.png",
      thumbnailUrl: "https://r2.example.com/thumb.jpg",
      currentJobId: null,
      createdAt: createdPoseA.createdAt,
      updatedAt: createdPoseA.updatedAt
    });
  });
});
