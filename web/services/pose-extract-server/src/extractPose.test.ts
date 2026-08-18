import request from "supertest";
import { describe, expect, it, vi } from "vitest";

import { createApp } from "./app";
import { setupTestDatabase } from "./db/testDb";
import { ExtractionJobStore } from "./db/extractionJobStore";
import { KeyPoolManager } from "./services/keyPoolManager";
import { KeyStore } from "./services/keyStore";

function createTestImageBuffer(): Buffer {
  return Buffer.from("fake-image-content");
}

interface CreateExtractAppOptions {
  rateLimitWindowMs?: number;
  rateLimitMaxRequests?: number;
}

async function createExtractApp(options: CreateExtractAppOptions = {}) {
  const sql = await setupTestDatabase();
  const keyStore = new KeyStore(sql);
  const keyPoolManager = new KeyPoolManager(keyStore);
  const extractionJobStore = new ExtractionJobStore(sql);
  await keyStore.createKey({ name: "key1", apiKey: "AIza-key1" });

  const app = createApp({
    version: "1.0.0-test",
    keyStore,
    keyPoolManager,
    geminiService: {
      extractPoseImage: vi.fn()
    },
    extractionJobStore,
    extractRateLimitWindowMs: options.rateLimitWindowMs,
    extractRateLimitMaxRequests: options.rateLimitMaxRequests
  });

  return { app, extractionJobStore };
}

describe("POST /api/extract-pose", () => {
  it("returns INVALID_IMAGE when image field is missing", async () => {
    const { app } = await createExtractApp();

    const response = await request(app).post("/api/extract-pose");

    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe("INVALID_IMAGE");
  });

  it("returns INVALID_IMAGE for unsupported mime type", async () => {
    const { app } = await createExtractApp();

    const response = await request(app)
      .post("/api/extract-pose")
      .attach("image", createTestImageBuffer(), {
        filename: "pose.gif",
        contentType: "image/gif"
      });

    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe("INVALID_IMAGE");
  });

  it("returns IMAGE_TOO_LARGE when file exceeds 10MB", async () => {
    const { app } = await createExtractApp();
    const tooLarge = Buffer.alloc(10 * 1024 * 1024 + 1, 1);

    const response = await request(app)
      .post("/api/extract-pose")
      .attach("image", tooLarge, {
        filename: "large.png",
        contentType: "image/png"
      });

    expect(response.status).toBe(413);
    expect(response.body.error.code).toBe("IMAGE_TOO_LARGE");
  });

  it("returns RATE_LIMITED when endpoint rate limit is exceeded", async () => {
    const { app } = await createExtractApp({
      rateLimitWindowMs: 60_000,
      rateLimitMaxRequests: 1
    });

    const first = await request(app)
      .post("/api/extract-pose")
      .attach("image", createTestImageBuffer(), { filename: "pose.jpg", contentType: "image/jpeg" });
    const second = await request(app)
      .post("/api/extract-pose")
      .attach("image", createTestImageBuffer(), { filename: "pose.jpg", contentType: "image/jpeg" });

    expect(first.status).toBe(202);
    expect(second.status).toBe(429);
    expect(second.body.error.code).toBe("RATE_LIMITED");
  });

  it("uses forwarded-for IP for rate-limit key when trust proxy is enabled", async () => {
    const { app } = await createExtractApp({
      rateLimitWindowMs: 60_000,
      rateLimitMaxRequests: 1
    });

    const firstIp = await request(app)
      .post("/api/extract-pose")
      .set("X-Forwarded-For", "203.0.113.10")
      .attach("image", createTestImageBuffer(), { filename: "pose.jpg", contentType: "image/jpeg" });

    const secondIp = await request(app)
      .post("/api/extract-pose")
      .set("X-Forwarded-For", "198.51.100.8")
      .attach("image", createTestImageBuffer(), { filename: "pose.jpg", contentType: "image/jpeg" });

    expect(firstIp.status).toBe(202);
    expect(secondIp.status).toBe(202);
  });

  it("enqueues extraction job and returns 202 with poll URL", async () => {
    const { app, extractionJobStore } = await createExtractApp();

    const response = await request(app)
      .post("/api/extract-pose")
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
});

describe("GET /api/extract-jobs/:jobId", () => {
  it("returns public job status without admin-only fields", async () => {
    const { app, extractionJobStore } = await createExtractApp();
    const job = await extractionJobStore.enqueue({
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });

    const response = await request(app).get(`/api/extract-jobs/${job.id}`);

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
    const { app, extractionJobStore } = await createExtractApp();
    const job = await extractionJobStore.enqueue({
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });
    const lockToken = "test-lock-token";
    await extractionJobStore.claimNext(lockToken, 120);
    await extractionJobStore.markSucceeded(job.id, lockToken, "cG9zZQ==", "image/png");

    const response = await request(app).get(`/api/extract-jobs/${job.id}`);

    expect(response.status).toBe(200);
    expect(response.body.data.status).toBe("succeeded");
    expect(response.body.data.result).toEqual({
      imageBase64: "cG9zZQ==",
      mimeType: "image/png"
    });
  });

  it("returns provider error when job fails after max attempts", async () => {
    const { app, extractionJobStore } = await createExtractApp();
    const job = await extractionJobStore.enqueue({
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png",
      maxAttempts: 1
    });
    const lockToken = "test-lock-token";
    await extractionJobStore.claimNext(lockToken, 120);
    await extractionJobStore.markFailedOrRequeue(job.id, lockToken, "PROVIDER_AUTH_REQUIRED", "Provider authentication required");

    const response = await request(app).get(`/api/extract-jobs/${job.id}`);

    expect(response.status).toBe(200);
    expect(response.body.data.status).toBe("failed");
    expect(response.body.data.result).toBeNull();
    expect(response.body.data.error).toEqual({
      code: "PROVIDER_AUTH_REQUIRED",
      message: "Provider authentication required"
    });
  });
});
