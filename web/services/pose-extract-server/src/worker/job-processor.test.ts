import { randomUUID } from "node:crypto";

import { describe, expect, it, vi } from "vitest";

import type { Sql } from "../db/connection";
import { MediaManifestStore, MEDIA_UPLOAD_HORIZON_SECONDS } from "../db/mediaManifestStore";
import { ObjectDeletionOutbox, drainPendingObjectDeletions } from "../db/objectDeletionOutbox";
import { logger } from "../utils/logger";
import { AccountStore } from "../db/accountStore";
import { applySchema, createDatabase } from "../db/connection";
import { setupTestDatabase } from "../db/testDb";
import { ExtractionJobStore } from "../db/extractionJobStore";
import { PoseStore } from "../db/communityStore";
import { ProviderSettingsStore } from "../db/providerSettingsStore";
import {
  ProviderAuthRequiredError,
  ProviderCliFailedError,
  ProviderError,
  ProviderQuotaExceededError,
  ProviderTimeoutError
} from "../services/errors";
import type { ExtractionProviderId, PoseExtractorProvider } from "../services/poseExtractorProvider";
import type { MediaStorage } from "../services/poseMaterializer";
import { processNextJob } from "./job-processor";

function createBackgroundRemoverStub() {
  return {
    enabled: true,
    removeBackground: vi.fn(async (image: { imageBase64: string; mimeType: "image/png" | "image/jpeg" | "image/webp" }) => ({
      imageBase64: image.imageBase64,
      mimeType: "image/png" as const
    }))
  };
}

async function createStores() {
  const sql = await setupTestDatabase();
  return {
    sql,
    jobStore: new ExtractionJobStore(sql),
    communityStore: new PoseStore(sql),
    providerSettingsStore: new ProviderSettingsStore(sql)
  };
}

async function createOwnerAccount(sql: Sql): Promise<string> {
  const ownerAccountId = randomUUID();
  await sql`INSERT INTO accounts (id, display_name) VALUES (${ownerAccountId}, ${"Owner"})`;
  return ownerAccountId;
}

function mockProvider(id: ExtractionProviderId, extractPoseImage: PoseExtractorProvider["extractPoseImage"]): PoseExtractorProvider {
  return { id, extractPoseImage };
}

function createMediaStorageMock() {
  const uploaded = new Map<string, { body: Buffer; mimeType: string }>();
  const removed: string[] = [];

  const mediaStorage: MediaStorage = {
    put: vi.fn(async (key: string, body: Buffer, mimeType: string) => {
      uploaded.set(key, { body, mimeType });
    }),
    remove: vi.fn(async (key: string) => {
      removed.push(key);
      uploaded.delete(key);
    }),
    publicUrl: (key: string) => `https://cdn.example.com/${key}`
  };

  return { mediaStorage, uploaded, removed };
}

describe("processNextJob", () => {
  it("processes enqueue → mock provider → succeeded (legacy admin path)", async () => {
    const { jobStore, providerSettingsStore } = await createStores();
    const extractPoseImage = vi.fn().mockResolvedValue({
      imageBase64: "cG9zZS1pbWFnZQ==",
      mimeType: "image/png"
    });

    const job = await jobStore.enqueue({
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });

    const processed = await processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider: () => mockProvider("gemini_native", extractPoseImage),
      staleLockSeconds: 120,
      lineartBackgroundRemover: createBackgroundRemoverStub()
    });

    expect(processed).toBe(true);
    expect(extractPoseImage).toHaveBeenCalledOnce();

    const updated = await jobStore.getById(job.id);
    expect(updated?.status).toBe("succeeded");
    expect(updated?.resultImageBase64).toBe("cG9zZS1pbWFnZQ==");
    expect(updated?.resultMimeType).toBe("image/png");
    expect(updated?.poseId).toBeNull();
  });

  it("applies line-art background removal before marking job succeeded", async () => {
    const { jobStore, providerSettingsStore } = await createStores();
    const backgroundRemover = createBackgroundRemoverStub();
    const extractPoseImage = vi.fn().mockResolvedValue({
      imageBase64: "cG9zZS1pbWFnZQ==",
      mimeType: "image/jpeg"
    });

    await jobStore.enqueue({
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });

    await processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider: () => mockProvider("gemini_native", extractPoseImage),
      staleLockSeconds: 120,
      lineartBackgroundRemover: backgroundRemover
    });

    expect(backgroundRemover.removeBackground).toHaveBeenCalledOnce();
  });

  it("requeues job with error_code when attempts remain", async () => {
    const { jobStore, providerSettingsStore } = await createStores();
    const mockProviderInstance = mockProvider("higgsfield_cli", vi.fn().mockRejectedValue(new ProviderError("provider failed")));

    const job = await jobStore.enqueue({
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png",
      maxAttempts: 3
    });

    await processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider: () => mockProviderInstance,
      staleLockSeconds: 120
    });

    const updated = await jobStore.getById(job.id);
    expect(updated?.status).toBe("queued");
    expect(updated?.attempts).toBe(1);
    expect(updated?.errorCode).toBe("PROVIDER_ERROR");
    expect(updated?.errorMessage).toBe("provider failed");
  });

  it("stores the fixed auth message on the job, never the CLI output", async () => {
    const { jobStore, providerSettingsStore } = await createStores();
    const marker = "LEAK-CANARY-1234";
    const mockProviderInstance = mockProvider(
      "higgsfield_cli",
      vi.fn().mockRejectedValue(new ProviderAuthRequiredError("Higgsfield authentication required"))
    );

    const job = await jobStore.enqueue({
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png",
      maxAttempts: 3
    });

    await processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider: () => mockProviderInstance,
      staleLockSeconds: 120
    });

    const updated = await jobStore.getById(job.id);
    expect(updated?.errorCode).toBe("PROVIDER_AUTH_REQUIRED");
    expect(updated?.errorMessage).toBe("Higgsfield authentication required");
    expect(JSON.stringify(updated)).not.toContain(marker);
  });

  it("fails the job immediately on a provider auth error instead of requeueing", async () => {
    const { jobStore, providerSettingsStore } = await createStores();
    const mockProviderInstance = mockProvider(
      "higgsfield_cli",
      vi.fn().mockRejectedValue(new ProviderAuthRequiredError("Error: Session expired."))
    );

    const job = await jobStore.enqueue({
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png",
      maxAttempts: 3
    });

    await processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider: () => mockProviderInstance,
      staleLockSeconds: 120
    });

    const updated = await jobStore.getById(job.id);
    expect(updated?.status).toBe("failed");
    expect(updated?.attempts).toBe(1);
    expect(updated?.errorCode).toBe("PROVIDER_AUTH_REQUIRED");
    expect(updated?.errorMessage).toBe("Error: Session expired.");
  });

  it("marks job failed when max attempts exhausted", async () => {
    const { jobStore, providerSettingsStore } = await createStores();
    const mockProviderInstance = mockProvider(
      "higgsfield_cli",
      vi.fn().mockRejectedValue(new ProviderCliFailedError("cli parse failed"))
    );

    const job = await jobStore.enqueue({
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png",
      maxAttempts: 1
    });

    await processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider: () => mockProviderInstance,
      staleLockSeconds: 120
    });

    const updated = await jobStore.getById(job.id);
    expect(updated?.status).toBe("failed");
    expect(updated?.attempts).toBe(1);
    expect(updated?.errorCode).toBe("PROVIDER_CLI_FAILED");
  });

  it("invokes higgsfield_cli provider when settings store is higgsfield_cli", async () => {
    const { jobStore, providerSettingsStore } = await createStores();
    await providerSettingsStore.setProvider("higgsfield_cli");

    const higgsfieldExtract = vi.fn().mockResolvedValue({
      imageBase64: "aGlnZ3M=",
      mimeType: "image/png"
    });
    const geminiExtract = vi.fn();
    const createProvider = vi.fn((providerId: ExtractionProviderId) => {
      if (providerId === "higgsfield_cli") {
        return mockProvider("higgsfield_cli", higgsfieldExtract);
      }
      return mockProvider("gemini_native", geminiExtract);
    });

    await jobStore.enqueue({
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });

    await processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider,
      staleLockSeconds: 120,
      lineartBackgroundRemover: createBackgroundRemoverStub()
    });
    expect(higgsfieldExtract).toHaveBeenCalledOnce();
    expect(geminiExtract).not.toHaveBeenCalled();
  });

  it("invokes gemini_native provider when settings store is gemini_native", async () => {
    const { jobStore, providerSettingsStore } = await createStores();
    await providerSettingsStore.setProvider("gemini_native");

    const higgsfieldExtract = vi.fn();
    const geminiExtract = vi.fn().mockResolvedValue({
      imageBase64: "Z2VtaW5p",
      mimeType: "image/jpeg"
    });
    const createProvider = vi.fn((providerId: ExtractionProviderId) => {
      if (providerId === "gemini_native") {
        return mockProvider("gemini_native", geminiExtract);
      }
      return mockProvider("higgsfield_cli", higgsfieldExtract);
    });

    await jobStore.enqueue({
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/jpeg"
    });

    await processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider,
      staleLockSeconds: 120,
      lineartBackgroundRemover: createBackgroundRemoverStub()
    });

    expect(createProvider).toHaveBeenCalledWith("gemini_native");
    expect(geminiExtract).toHaveBeenCalledOnce();
    expect(higgsfieldExtract).not.toHaveBeenCalled();
  });

  it.each([
    ["PROVIDER_QUOTA_EXCEEDED", new ProviderQuotaExceededError("quota hit")],
    ["PROVIDER_ERROR", new ProviderError("generic provider failure")],
    ["PROVIDER_AUTH_REQUIRED", new ProviderAuthRequiredError("auth expired")],
    ["PROVIDER_TIMEOUT", new ProviderTimeoutError("timed out")],
    ["PROVIDER_CLI_FAILED", new ProviderCliFailedError("spawn failed")]
  ] as const)("maps %s to job error_code", async (expectedCode, error) => {
    const { jobStore, providerSettingsStore } = await createStores();
    const mockProviderInstance = mockProvider("higgsfield_cli", vi.fn().mockRejectedValue(error));

    const job = await jobStore.enqueue({
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png",
      maxAttempts: 1
    });

    await processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider: () => mockProviderInstance,
      staleLockSeconds: 120
    });

    const updated = await jobStore.getById(job.id);
    expect(updated?.status).toBe("failed");
    expect(updated?.errorCode).toBe(expectedCode);
    expect(updated?.errorMessage).toBe(error.message);
  });

  // --- Phase 2 Owner Materialization Tests ---

  it("owner success creates 1 pose + 3 assets and nulls base64", async () => {
    const { sql, jobStore, communityStore, providerSettingsStore } = await createStores();
    const { mediaStorage, uploaded } = createMediaStorageMock();
    const extractPoseImage = vi.fn().mockResolvedValue({
      imageBase64: Buffer.from("extracted-skeleton").toString("base64"),
      mimeType: "image/png"
    });

    const ownerAccountId = await createOwnerAccount(sql);
    const job = await jobStore.enqueue({
      ownerAccountId,
      poseDraft: {
        name: "Tree Pose",
        tags: ["standing", "balance"],
        description: "Classic balancing pose"
      },
      sourceImageBase64: Buffer.from("source-image-raw").toString("base64"),
      sourceMimeType: "image/jpeg"
    });

    const processed = await processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider: () => mockProvider("gemini_native", extractPoseImage),
      staleLockSeconds: 120,
      db: sql,
      communityStore,
      mediaStorage,
      lineartBackgroundRemover: createBackgroundRemoverStub()
    });

    expect(processed).toBe(true);
    expect(uploaded.size).toBe(3);

    const updatedJob = await jobStore.getById(job.id);
    expect(updatedJob?.status).toBe("succeeded");
    expect(updatedJob?.poseId).toBeTruthy();
    expect(updatedJob?.sourceImageBase64).toBeNull();
    expect(updatedJob?.resultImageBase64).toBeNull();

    const pose = await communityStore.getPoseById(updatedJob!.poseId!);
    expect(pose).not.toBeNull();
    expect(pose).toMatchObject({
      ownerAccountId,
      name: "Tree Pose",
      tags: ["standing", "balance"],
      description: "Classic balancing pose",
      status: "local",
      currentJobId: job.id,
      originalUrl: expect.stringContaining(`poses/${pose?.poseId}/original.jpeg`),
      skeletonUrl: expect.stringContaining(`poses/${pose?.poseId}/skeleton.png`),
      thumbnailUrl: expect.stringContaining(`poses/${pose?.poseId}/thumbnail.png`)
    });
  });

  it("re-claim/second-run creates no second pose (idempotency)", async () => {
    const { sql, jobStore, communityStore, providerSettingsStore } = await createStores();
    const { mediaStorage } = createMediaStorageMock();
    const extractPoseImage = vi.fn().mockResolvedValue({
      imageBase64: Buffer.from("skeleton").toString("base64"),
      mimeType: "image/png"
    });

    const ownerAccountId = await createOwnerAccount(sql);
    const job = await jobStore.enqueue({
      ownerAccountId,
      poseDraft: { name: "Warrior I", tags: ["standing"], description: null },
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });

    // First run creates pose
    await processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider: () => mockProvider("gemini_native", extractPoseImage),
      staleLockSeconds: 120,
      db: sql,
      communityStore,
      mediaStorage,
      lineartBackgroundRemover: createBackgroundRemoverStub()
    });

    const jobAfterRun1 = await jobStore.getById(job.id);
    const poseId = jobAfterRun1!.poseId!;

    // Re-queue job with source intact to simulate re-claim
    await sql`
      UPDATE extraction_jobs
      SET status = 'queued', source_image_base64 = ${Buffer.from("source").toString("base64")}, lock_token = NULL, locked_at = NULL
      WHERE id = ${job.id}
    `;

    vi.clearAllMocks();

    // Second run: getPoseByCurrentJobId finds existing pose, safeFinalize called, no new upload
    const processedSecond = await processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider: () => mockProvider("gemini_native", extractPoseImage),
      staleLockSeconds: 120,
      db: sql,
      communityStore,
      mediaStorage,
      lineartBackgroundRemover: createBackgroundRemoverStub()
    });

    expect(processedSecond).toBe(true);
    expect(mediaStorage.put).not.toHaveBeenCalled();

    const jobAfterRun2 = await jobStore.getById(job.id);
    expect(jobAfterRun2?.status).toBe("succeeded");
    expect(jobAfterRun2?.poseId).toBe(poseId);

    const poseCount = await sql`SELECT count(*) FROM poses WHERE current_job_id = ${job.id}`;
    expect(Number(poseCount[0].count)).toBe(1);
  });

  async function manifestsFor(sql: Awaited<ReturnType<typeof setupTestDatabase>>) {
    return new MediaManifestStore(sql);
  }

  async function ticketsFor(sql: Awaited<ReturnType<typeof setupTestDatabase>>, keys: readonly string[]) {
    const rows = (await sql`
      SELECT key, not_before FROM pending_object_deletions ORDER BY key
    `) as Array<{ key: string; not_before: Date | string }>;
    return rows.filter((row) => keys.includes(row.key));
  }

  function notFound(key: string): Error {
    return Object.assign(new Error(`NoSuchKey: ${"missing"}`), {
      name: "NoSuchKey",
      $metadata: { httpStatusCode: 404 }
    });
  }

  function storage(behaviour: { failPutFor?: string; objects?: Set<string> } = {}) {
    const objects = behaviour.objects ?? new Set<string>();
    const signals: Array<AbortSignal | undefined> = [];
    const put = vi.fn(async (key: string, _body?: Buffer, _mime?: string, options?: { abortSignal?: AbortSignal }) => {
      signals.push(options?.abortSignal);
      if (behaviour.failPutFor && key.includes(behaviour.failPutFor)) throw new Error("R2 upload failed");
      objects.add(key);
    });
    const remove = vi.fn(async (key: string) => {
      objects.delete(key);
    });
    return {
      objects,
      put,
      remove,
      signals,
      mediaStorage: { put, remove, publicUrl: (key: string) => `https://cdn.example.com/${key}` } as MediaStorage
    };
  }

  async function drainInto(sql: Awaited<ReturnType<typeof setupTestDatabase>>, objects: Set<string>) {
    const deleted: string[] = [];
    await drainPendingObjectDeletions({
      outbox: new ObjectDeletionOutbox(sql),
      deleteObject: async (key: string) => {
        if (!objects.has(key)) throw notFound(key);
        objects.delete(key);
        deleted.push(key);
      }
    });
    return deleted;
  }

  it("creates the pose from the attempt's manifest and leaves nothing queued", async () => {
    const { sql, jobStore, communityStore, providerSettingsStore } = await createStores();
    const { mediaStorage, objects, remove, signals } = storage();
    const ownerAccountId = await createOwnerAccount(sql);
    const job = await jobStore.enqueue({
      ownerAccountId,
      poseDraft: { name: "Manifest Happy", tags: [], description: null },
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });

    await processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider: () =>
        mockProvider("gemini_native", async () => ({
          imageBase64: Buffer.from("skeleton").toString("base64"),
          mimeType: "image/png" as const
        })),
      staleLockSeconds: 120,
      db: sql,
      communityStore,
      mediaStorage,
      manifests: await manifestsFor(sql),
      lineartBackgroundRemover: createBackgroundRemoverStub()
    });

    const pose = await communityStore.getPoseByCurrentJobId(job.id);
    expect(pose).not.toBeNull();
    expect((await jobStore.getById(job.id))?.status).toBe("succeeded");
    const assets = (await sql`SELECT role FROM media_assets WHERE pose_id = ${pose!.poseId}`) as Array<{ role: string }>;
    expect(assets).toHaveLength(3);
    const manifests = (await sql`SELECT pose_id FROM pose_media_manifests`) as Array<{ pose_id: string }>;
    expect(manifests).toHaveLength(0);
    expect(await new ObjectDeletionOutbox(sql).count()).toBe(0);
    expect(objects.size).toBe(3);
    expect(remove).not.toHaveBeenCalled();
    expect(signals).toHaveLength(3);
    expect(signals.every((signal) => signal instanceof AbortSignal)).toBe(true);
  });

  it("keeps the manifest when abandon fails, so the sweep can still find the keys", async () => {
    const { sql, jobStore, communityStore, providerSettingsStore } = await createStores();
    const { mediaStorage, objects, remove, put } = storage();
    const ownerAccountId = await createOwnerAccount(sql);
    const job = await jobStore.enqueue({
      ownerAccountId,
      poseDraft: { name: "Abandon Fails", tags: [], description: null },
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });
    remove.mockImplementation(async () => {
      throw new Error("R2 delete failed");
    });

    const realManifests = await manifestsFor(sql);
    const failingAbandon = new Proxy(realManifests, {
      get(target, property) {
        if (property === "abandon") {
          return async () => {
            throw new Error("manifest store unavailable");
          };
        }
        const value = Reflect.get(target, property);
        return typeof value === "function" ? value.bind(target) : value;
      }
    }) as MediaManifestStore;

    // Finalize throws after the uploads landed: the job lock is stolen during extraction.
    const extractPoseImage = vi.fn().mockImplementation(async () => {
      await sql`UPDATE extraction_jobs SET lock_token = 'stolen-lock-token' WHERE id = ${job.id}`;
      return { imageBase64: Buffer.from("skeleton").toString("base64"), mimeType: "image/png" as const };
    });

    await processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider: () => mockProvider("gemini_native", extractPoseImage),
      staleLockSeconds: 120,
      db: sql,
      communityStore,
      mediaStorage,
      manifests: failingAbandon,
      lineartBackgroundRemover: createBackgroundRemoverStub()
    });

    expect(put).toHaveBeenCalledTimes(3);
    expect(remove).not.toHaveBeenCalled();
    expect(await communityStore.getPoseByCurrentJobId(job.id)).toBeNull();
    const manifests = (await sql`SELECT pose_id, object_keys FROM pose_media_manifests`) as Array<{
      pose_id: string;
      object_keys: string[];
    }>;
    expect(manifests).toHaveLength(1);
    expect(manifests[0]!.object_keys).toHaveLength(3);
    expect(await new ObjectDeletionOutbox(sql).count()).toBe(0);

    // The sweep finds the leftover manifest once its horizon passed, and the drain cleans up.
    await sql`UPDATE pose_media_manifests SET created_at = NOW() - interval '2 hours'`;
    expect(await realManifests.abandonStale()).toBe(1);
    const deleted = await drainInto(sql, objects);
    expect(deleted).toHaveLength(3);
    expect(objects.size).toBe(0);
  });

  it("refuses to finalize when the sweep took the attempt while its uploads were in flight", async () => {
    const { sql, jobStore, communityStore, providerSettingsStore } = await createStores();
    const { mediaStorage, objects } = storage();
    const ownerAccountId = await createOwnerAccount(sql);
    const job = await jobStore.enqueue({
      ownerAccountId,
      poseDraft: { name: "Swept Attempt", tags: [], description: null },
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });
    const manifests = await manifestsFor(sql);

    let release!: () => void;
    const uploadGate = new Promise<void>((resolve) => {
      release = resolve;
    });
    let slowLanded!: () => void;
    const slowSeen = new Promise<void>((resolve) => {
      slowLanded = resolve;
    });
    const realPut = mediaStorage.put;
    mediaStorage.put = vi.fn(async (key: string, body: Buffer, mimeType: string) => {
      if (key.includes("thumbnail")) {
        slowLanded();
        await uploadGate;
      }
      await realPut(key, body, mimeType);
    });

    const running = processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider: () =>
        mockProvider("gemini_native", async () => ({
          imageBase64: Buffer.from("skeleton").toString("base64"),
          mimeType: "image/png" as const
        })),
      staleLockSeconds: 120,
      db: sql,
      communityStore,
      mediaStorage,
      manifests,
      lineartBackgroundRemover: createBackgroundRemoverStub()
    });

    await slowSeen;
    const recorded = (await sql`SELECT pose_id, created_at FROM pose_media_manifests`) as Array<{
      pose_id: string;
      created_at: Date | string;
    }>;
    expect(recorded).toHaveLength(1);
    expect(Date.parse(String(recorded[0]!.created_at))).toBeGreaterThan(0);
    const agedAt = Date.now();
    await sql`UPDATE pose_media_manifests SET created_at = NOW() - interval '2 hours'`;
    expect(await manifests.abandonStale()).toBe(1);

    const keys = (await sql`SELECT key, not_before FROM pending_object_deletions`) as Array<{
      key: string;
      not_before: Date | string;
    }>;
    expect(keys).toHaveLength(3);
    for (const ticket of keys) {
      // The horizon of an already-aged attempt has passed, so its ticket is due immediately.
      const notBefore = Date.parse(String(ticket.not_before));
      expect(notBefore).toBeGreaterThanOrEqual(agedAt - 2000);
      expect(notBefore).toBeLessThanOrEqual(agedAt + MEDIA_UPLOAD_HORIZON_SECONDS * 1000);
    }

    release();
    await expect(running).resolves.toBe(true);

    expect(await communityStore.getPoseByCurrentJobId(job.id)).toBeNull();
    expect((await jobStore.getById(job.id))?.status).toBe("queued");

    // The attempt's objects are queued, so the drain can remove exactly what landed.
    expect(await drainInto(sql, objects)).toHaveLength(3);
    expect(objects.size).toBe(0);
    expect(await new ObjectDeletionOutbox(sql).count()).toBe(0);
  });

  it("refuses to start a put after the upload window closed", async () => {
    const { sql, jobStore, communityStore, providerSettingsStore } = await createStores();
    const { mediaStorage, objects, put } = storage();
    const ownerAccountId = await createOwnerAccount(sql);
    const job = await jobStore.enqueue({
      ownerAccountId,
      poseDraft: { name: "Window Closed", tags: [], description: null },
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });
    const manifests = await manifestsFor(sql);

    let clockOffsetMs = 0;
    await processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider: () =>
        mockProvider("gemini_native", async () => ({
          imageBase64: Buffer.from("skeleton").toString("base64"),
          mimeType: "image/png" as const
        })),
      staleLockSeconds: 120,
      db: sql,
      communityStore,
      mediaStorage,
      manifests,
      now: () => Date.now() + clockOffsetMs,
      putStartLimitMs: 300_000,
      lineartBackgroundRemover: {
        enabled: true,
        removeBackground: async (image: { imageBase64: string; mimeType: "image/png" | "image/jpeg" | "image/webp" }) => {
          clockOffsetMs = 301_000;
          return { imageBase64: image.imageBase64, mimeType: "image/png" as const };
        }
      }
    });

    expect(put).not.toHaveBeenCalled();
    expect(objects.size).toBe(0);
    expect((await jobStore.getById(job.id))?.status).toBe("queued");
    expect(await communityStore.getPoseByCurrentJobId(job.id)).toBeNull();
    const manifestsLeft = (await sql`SELECT pose_id FROM pose_media_manifests`) as Array<{ pose_id: string }>;
    expect(manifestsLeft).toHaveLength(0);
    expect(await new ObjectDeletionOutbox(sql).count()).toBe(3);
  });

  it("keeps the pose and its objects when the commit acknowledgement is lost", async () => {
    const { sql, jobStore, communityStore, providerSettingsStore } = await createStores();
    const { mediaStorage, objects, remove } = storage();
    const ownerAccountId = await createOwnerAccount(sql);
    const job = await jobStore.enqueue({
      ownerAccountId,
      poseDraft: { name: "Lost Commit", tags: [], description: null },
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });
    const manifests = await manifestsFor(sql);
    const flakyDb = new Proxy(sql, {
      get(target, property) {
        if (property === "begin") {
          return async (...args: unknown[]) => {
            const run = target.begin as (...a: unknown[]) => Promise<unknown>;
            await run(...args);
            throw new Error("connection lost after commit");
          };
        }
        const value = Reflect.get(target, property);
        return typeof value === "function" ? value.bind(target) : value;
      }
    }) as typeof sql;

    await processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider: () =>
        mockProvider("gemini_native", async () => ({
          imageBase64: Buffer.from("skeleton").toString("base64"),
          mimeType: "image/png" as const
        })),
      staleLockSeconds: 120,
      db: flakyDb,
      communityStore,
      mediaStorage,
      manifests,
      lineartBackgroundRemover: createBackgroundRemoverStub()
    });

    const pose = await communityStore.getPoseByCurrentJobId(job.id);
    expect(pose).not.toBeNull();
    expect((await jobStore.getById(job.id))?.status).toBe("succeeded");
    expect(await new ObjectDeletionOutbox(sql).count()).toBe(0);
    expect(objects.size).toBe(3);
    expect(remove).not.toHaveBeenCalled();
  });

  it("abandons the attempt when another worker re-claimed the job", async () => {
    const { sql, jobStore, communityStore, providerSettingsStore } = await createStores();
    const { mediaStorage, objects } = storage();
    const ownerAccountId = await createOwnerAccount(sql);
    const job = await jobStore.enqueue({
      ownerAccountId,
      poseDraft: { name: "Stale Lock", tags: [], description: null },
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });
    const manifests = await manifestsFor(sql);
    const extractPoseImage = vi.fn().mockImplementation(async () => {
      await sql`UPDATE extraction_jobs SET lock_token = 'stolen-lock-token' WHERE id = ${job.id}`;
      return { imageBase64: Buffer.from("skeleton").toString("base64"), mimeType: "image/png" as const };
    });

    await processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider: () => mockProvider("gemini_native", extractPoseImage),
      staleLockSeconds: 120,
      db: sql,
      communityStore,
      mediaStorage,
      manifests,
      lineartBackgroundRemover: createBackgroundRemoverStub()
    });

    expect(await communityStore.getPoseByCurrentJobId(job.id)).toBeNull();
    const updated = await jobStore.getById(job.id);
    expect(updated?.status).toBe("processing");
    expect(updated?.lockToken).toBe("stolen-lock-token");
    expect(await ticketsFor(sql, [...objects, ...Array.from({ length: 3 - objects.size }, () => "x")])).toHaveLength(3);
  });

  it("finalizes to the winning pose and queues the loser's attempt", async () => {
    const { sql, jobStore, communityStore, providerSettingsStore } = await createStores();
    const { mediaStorage, objects } = storage();
    const ownerAccountId = await createOwnerAccount(sql);
    const job = await jobStore.enqueue({
      ownerAccountId,
      poseDraft: { name: "Collision", tags: [], description: null },
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });
    const manifests = await manifestsFor(sql);
    await communityStore.createPose({
      poseId: "winner-pose-id",
      ownerAccountId,
      name: "Winner",
      originalUrl: "https://cdn.example.com/poses/winner/original.png",
      skeletonUrl: "https://cdn.example.com/poses/winner/skeleton.png",
      thumbnailUrl: "https://cdn.example.com/poses/winner/thumbnail.png",
      tags: [],
      difficulty: null,
      description: null,
      bodyParts: [],
      currentJobId: job.id
    });
    vi.spyOn(communityStore, "getPoseByCurrentJobId").mockResolvedValueOnce(null);

    await processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider: () =>
        mockProvider("gemini_native", async () => ({
          imageBase64: Buffer.from("skeleton").toString("base64"),
          mimeType: "image/png" as const
        })),
      staleLockSeconds: 120,
      db: sql,
      communityStore,
      mediaStorage,
      manifests,
      lineartBackgroundRemover: createBackgroundRemoverStub()
    });

    const updated = await jobStore.getById(job.id);
    expect(updated?.status).toBe("succeeded");
    expect(updated?.poseId).toBe("winner-pose-id");
    const manifestsLeft = (await sql`SELECT pose_id FROM pose_media_manifests`) as Array<{ pose_id: string }>;
    expect(manifestsLeft).toHaveLength(0);
    expect(await ticketsFor(sql, [...objects, ...Array.from({ length: 3 - objects.size }, () => "x")])).toHaveLength(3);
  });

  it("stops when an account purge deletes the job between uploads and finalize", async () => {
    const { sql, jobStore, communityStore, providerSettingsStore } = await createStores();
    const { mediaStorage, objects } = storage();
    const ownerAccountId = await createOwnerAccount(sql);
    const job = await jobStore.enqueue({
      ownerAccountId,
      poseDraft: { name: "Purged Mid Flight", tags: [], description: null },
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });
    const manifests = await manifestsFor(sql);
    const accountStore = new AccountStore(sql);
    let purgePromise: Promise<unknown> | null = null;
    const realPut = mediaStorage.put;
    mediaStorage.put = vi.fn(async (key: string, body: Buffer, mimeType: string) => {
      if (!purgePromise) {
        purgePromise = accountStore.purgeAccountData(ownerAccountId, {
          resolveObjectKey: (locator) => locator
        });
      }
      await purgePromise;
      await realPut(key, body, mimeType);
    });

    await processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider: () =>
        mockProvider("gemini_native", async () => ({
          imageBase64: Buffer.from("skeleton").toString("base64"),
          mimeType: "image/png" as const
        })),
      staleLockSeconds: 120,
      db: sql,
      communityStore,
      mediaStorage,
      manifests,
      lineartBackgroundRemover: createBackgroundRemoverStub()
    });

    expect(await communityStore.getPoseByCurrentJobId(job.id)).toBeNull();
    expect(await accountStore.getById(ownerAccountId)).toBeNull();
    expect(await accountStore.hasAccountTombstone(ownerAccountId)).toBe(true);
    expect(await jobStore.getById(job.id)).toBeNull();

    const tickets = (await sql`
      SELECT key, not_before FROM pending_object_deletions WHERE not_before > NOW()
    `) as Array<{ key: string; not_before: Date | string }>;
    expect(tickets).toHaveLength(3);

    await sql`UPDATE pending_object_deletions SET not_before = NOW() - interval '1 second'`;
    const deleted = await drainInto(sql, objects);
    expect(deleted.length).toBe(objects.size === 0 ? 3 : deleted.length);
    expect(objects.size).toBe(0);
    expect(await new ObjectDeletionOutbox(sql).count()).toBe(0);
  });

  it("never writes a put when the manifest cannot be recorded", async () => {
    const { sql, jobStore, communityStore, providerSettingsStore } = await createStores();
    const { mediaStorage, put } = storage();
    const ownerAccountId = await createOwnerAccount(sql);
    const job = await jobStore.enqueue({
      ownerAccountId,
      poseDraft: { name: "No Manifest", tags: [], description: null },
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });
    const brokenManifests = new Proxy(await manifestsFor(sql), {
      get(target, property) {
        if (property === "record") {
          return async () => {
            throw new Error("insert failed for poses/secret/original.png user@example.com");
          };
        }
        const value = Reflect.get(target, property);
        return typeof value === "function" ? value.bind(target) : value;
      }
    }) as MediaManifestStore;
    const logged: unknown[][] = [];
    const errorSpy = vi.spyOn(logger, "error").mockImplementation((...args: unknown[]) => {
      logged.push(args);
      return undefined as never;
    });

    try {
      await processNextJob({
        jobStore,
        providerSettingsStore,
        createProvider: () =>
          mockProvider("gemini_native", async () => ({
            imageBase64: Buffer.from("skeleton").toString("base64"),
            mimeType: "image/png" as const
          })),
        staleLockSeconds: 120,
        db: sql,
        communityStore,
        mediaStorage,
        manifests: brokenManifests,
        lineartBackgroundRemover: createBackgroundRemoverStub()
      });
    } finally {
      errorSpy.mockRestore();
    }

    expect(put).not.toHaveBeenCalled();
    expect((await jobStore.getById(job.id))?.status).toBe("queued");
    expect(await new ObjectDeletionOutbox(sql).count()).toBe(0);
    const serialized = JSON.stringify(logged, (_key, value: unknown) =>
      value instanceof Error ? `${value.name}: ${value.message}` : value
    );
    expect(serialized).not.toContain("poses/secret");
    expect(serialized).not.toContain("user@example.com");
    expect(serialized).toContain(job.id);
  });

  it("queues only the objects that exist when one upload fails", async () => {
    const { sql, jobStore, communityStore, providerSettingsStore } = await createStores();
    const ownerAccountId = await createOwnerAccount(sql);
    const job = await jobStore.enqueue({
      ownerAccountId,
      poseDraft: { name: "Partial Upload", tags: [], description: null },
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });
    const objects = new Set<string>();
    const mediaStorage: MediaStorage = {
      put: vi.fn(async (key: string) => {
        if (key.includes("thumbnail")) throw new Error("R2 upload failed");
        objects.add(key);
      }),
      remove: vi.fn(async () => {
        throw new Error("R2 delete failed");
      }),
      publicUrl: (key: string) => `https://cdn.example.com/${key}`
    };

    await processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider: () =>
        mockProvider("gemini_native", async () => ({
          imageBase64: Buffer.from("skeleton").toString("base64"),
          mimeType: "image/png" as const
        })),
      staleLockSeconds: 120,
      db: sql,
      communityStore,
      mediaStorage,
      manifests: await manifestsFor(sql),
      lineartBackgroundRemover: createBackgroundRemoverStub()
    });

    expect(objects.size).toBe(2);
    expect((await jobStore.getById(job.id))?.status).toBe("queued");
    // A freshly written ticket waits for the horizon, so an in-flight put cannot land after a delete.
    expect(await drainInto(sql, objects)).toHaveLength(0);
    expect(objects.size).toBe(2);
    await sql`UPDATE pending_object_deletions SET not_before = NOW() - interval '1 second'`;
    await drainInto(sql, objects);
    expect(objects.size).toBe(0);
    expect(await new ObjectDeletionOutbox(sql).count()).toBe(0);
  });

  it("never logs an object key while abandoning an attempt", async () => {
    const { sql, jobStore, communityStore, providerSettingsStore } = await createStores();
    const { mediaStorage } = storage();
    const ownerAccountId = await createOwnerAccount(sql);
    const job = await jobStore.enqueue({
      ownerAccountId,
      poseDraft: { name: "Quiet Abandon", tags: [], description: null },
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });
    const logged: unknown[][] = [];
    const errorSpy = vi.spyOn(logger, "error").mockImplementation((...args: unknown[]) => {
      logged.push(args);
      return undefined as never;
    });
    const warnSpy = vi.spyOn(logger, "warn").mockImplementation((...args: unknown[]) => {
      logged.push(args);
      return undefined as never;
    });
    const failingAbandon = new Proxy(await manifestsFor(sql), {
      get(target, property) {
        if (property === "abandon") {
          return async () => {
            throw new Error("abandon failed for poses/leak/original.png");
          };
        }
        const value = Reflect.get(target, property);
        return typeof value === "function" ? value.bind(target) : value;
      }
    }) as MediaManifestStore;
    const extractPoseImage = vi.fn().mockImplementation(async () => {
      await sql`UPDATE extraction_jobs SET lock_token = 'stolen-lock-token' WHERE id = ${job.id}`;
      return { imageBase64: Buffer.from("skeleton").toString("base64"), mimeType: "image/png" as const };
    });

    try {
      await processNextJob({
        jobStore,
        providerSettingsStore,
        createProvider: () => mockProvider("gemini_native", extractPoseImage),
        staleLockSeconds: 120,
        db: sql,
        communityStore,
        mediaStorage,
        manifests: failingAbandon,
        lineartBackgroundRemover: createBackgroundRemoverStub()
      });
    } finally {
      errorSpy.mockRestore();
      warnSpy.mockRestore();
    }

    const serialized = JSON.stringify(logged, (_key, value: unknown) =>
      value instanceof Error ? `${value.name}: ${value.message}` : value
    );
    expect(serialized).not.toMatch(/poses\//);
    expect(serialized).not.toMatch(/\.png/);
    expect(serialized).toContain(job.id);
  });
});

describe.runIf(process.env.TEST_DATABASE_URL)("finalize gate against real Postgres", () => {
  const PREFIX = `a01-gate-${randomUUID()}`;

  async function harness() {
    const url = process.env.TEST_DATABASE_URL as string;
    const worker = createDatabase(url);
    const sweep = createDatabase(url);
    await applySchema(worker);
    const accountId = randomUUID();
    await worker`INSERT INTO accounts (id, display_name) VALUES (${accountId}, ${PREFIX})`;
    const jobStore = new ExtractionJobStore(worker);
    const communityStore = new PoseStore(worker);
    // An older queued job of another account: claimNext picks the oldest queued row, so the
    // regression only proves anything if this attempt is chosen and the decoy is left alone.
    const decoyAccountId = randomUUID();
    await worker`INSERT INTO accounts (id, display_name) VALUES (${decoyAccountId}, ${`${PREFIX}-decoy`})`;
    const decoyJob = await jobStore.enqueue({
      ownerAccountId: decoyAccountId,
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });
    const job = await jobStore.enqueue({
      ownerAccountId: accountId,
      poseDraft: { name: "Gate", tags: [], description: null },
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });
    // claimNext takes the oldest queued job of the whole database, so this attempt is placed
    // ahead of every other queued job. Assertions below also prove this job was the one claimed.
    await worker`
      UPDATE extraction_jobs
      SET created_at = (
        SELECT COALESCE(MIN(created_at), NOW()) - interval '1 minute'
        FROM extraction_jobs
        WHERE id <> ${job.id}
      )
      WHERE id = ${job.id}
    `;
    const objects = new Set<string>();
    const mediaStorage: MediaStorage = {
      put: vi.fn(async (key: string) => {
        objects.add(key);
      }),
      remove: vi.fn(async () => undefined),
      publicUrl: (key: string) => `https://cdn.example.com/${key}`
    };
    return { worker, sweep, accountId, decoyAccountId, decoyJob, jobStore, communityStore, job, objects, mediaStorage };
  }

  async function ownTickets(h: Awaited<ReturnType<typeof harness>>) {
    const rows = (await h.worker`
      SELECT key FROM pending_object_deletions WHERE key = ANY(${h.worker.array([...h.objects])})
    `) as Array<{ key: string }>;
    return rows;
  }

  async function cleanup(h: Awaited<ReturnType<typeof harness>>) {
    for (const key of h.objects) {
      await h.worker`DELETE FROM pending_object_deletions WHERE key = ${key}`;
    }
    await h.worker`DELETE FROM pending_object_deletions WHERE key LIKE ${`poses/%`} AND key IN (
      SELECT locator FROM media_assets WHERE pose_id IN (SELECT pose_id FROM poses WHERE owner_account_id = ${h.accountId})
    )`;
    await h.worker`DELETE FROM pose_media_manifests WHERE owner_account_id = ${h.accountId}`;
    await h.worker`DELETE FROM media_assets WHERE pose_id IN (SELECT pose_id FROM poses WHERE owner_account_id = ${h.accountId})`;
    await h.worker`DELETE FROM poses WHERE owner_account_id = ${h.accountId}`;
    await h.worker`DELETE FROM extraction_jobs WHERE owner_account_id = ${h.accountId}`;
    await h.worker`DELETE FROM pending_object_deletions WHERE key IN (
      SELECT unnest(object_keys) FROM pose_media_manifests WHERE owner_account_id = ${h.decoyAccountId}
    )`;
    await h.worker`DELETE FROM pose_media_manifests WHERE owner_account_id = ${h.decoyAccountId}`;
    await h.worker`DELETE FROM extraction_jobs WHERE owner_account_id = ${h.decoyAccountId}`;
    await h.worker`DELETE FROM deleted_accounts WHERE account_id = ${h.decoyAccountId}`;
    await h.worker`DELETE FROM accounts WHERE id = ${h.decoyAccountId}`;
    await h.worker`DELETE FROM deleted_accounts WHERE account_id = ${h.accountId}`;
    await h.worker`DELETE FROM accounts WHERE id = ${h.accountId}`;
    await h.worker.end();
    await h.sweep.end();
  }

  it("requeues when the sweep takes the attempt before consume", async () => {
    const h = await harness();
    // A zero horizon makes every attempt immediately stale, so no row has to be aged while
    // the finalize transaction is open.
    const manifests = new MediaManifestStore(h.worker, 0);
    let release!: () => void;
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });
    let reached!: () => void;
    const seen = new Promise<void>((resolve) => {
      reached = resolve;
    });
    const gated = new Proxy(manifests, {
      get(target, property) {
        if (property === "consume") {
          return async (tx: unknown, poseId: string, jobId: string) => {
            reached();
            await gate;
            return (target.consume as (tx: unknown, p: string, j: string) => Promise<boolean>)(tx, poseId, jobId);
          };
        }
        const value = Reflect.get(target, property);
        return typeof value === "function" ? value.bind(target) : value;
      }
    }) as MediaManifestStore;

    let running: Promise<boolean> | null = null;
    try {
      running = processNextJob({
        jobStore: h.jobStore,
        providerSettingsStore: new ProviderSettingsStore(h.worker),
        createProvider: () =>
          mockProvider("gemini_native", async () => ({
            imageBase64: Buffer.from("skeleton").toString("base64"),
            mimeType: "image/png" as const
          })),
        staleLockSeconds: 120,
        db: h.worker,
        communityStore: h.communityStore,
        mediaStorage: h.mediaStorage,
        manifests: gated,
        lineartBackgroundRemover: createBackgroundRemoverStub()
      });

      await seen;
      expect(await new MediaManifestStore(h.sweep, 0).abandonStale()).toBeGreaterThanOrEqual(1);
      release();
      await expect(running).resolves.toBe(true);

      const processed = await h.jobStore.getById(h.job.id);
      expect(processed?.attempts).toBe(1);
      expect(processed?.status).toBe("queued");
      expect((await h.jobStore.getById(h.decoyJob.id))?.status).toBe("queued");
      expect(await h.communityStore.getPoseByCurrentJobId(h.job.id)).toBeNull();
      expect(h.objects.size).toBe(3);
      expect(await ownTickets(h)).toHaveLength(3);
    } finally {
      release();
      await running?.catch(() => undefined);
      await cleanup(h);
    }
  });

  it("keeps the attempt when the sweep arrives after consume", async () => {
    const h = await harness();
    const manifests = new MediaManifestStore(h.worker, 0);
    let release!: () => void;
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });
    let reached!: () => void;
    const seen = new Promise<void>((resolve) => {
      reached = resolve;
    });
    const gatedStore = new Proxy(h.communityStore, {
      get(target, property) {
        if (property === "createPose") {
          return async (...args: unknown[]) => {
            reached();
            await gate;
            return (target.createPose as (...a: unknown[]) => Promise<unknown>)(...args);
          };
        }
        const value = Reflect.get(target, property);
        return typeof value === "function" ? value.bind(target) : value;
      }
    }) as PoseStore;

    let running: Promise<boolean> | null = null;
    try {
      running = processNextJob({
        jobStore: h.jobStore,
        providerSettingsStore: new ProviderSettingsStore(h.worker),
        createProvider: () =>
          mockProvider("gemini_native", async () => ({
            imageBase64: Buffer.from("skeleton").toString("base64"),
            mimeType: "image/png" as const
          })),
        staleLockSeconds: 120,
        db: h.worker,
        communityStore: gatedStore,
        mediaStorage: h.mediaStorage,
        manifests,
        lineartBackgroundRemover: createBackgroundRemoverStub()
      });

      await seen;
      // The manifest is already deleted by consume, so the sweep cannot queue this attempt.
      await new MediaManifestStore(h.sweep, 0).abandonStale();
      expect(await ownTickets(h)).toHaveLength(0);
      release();
      await expect(running).resolves.toBe(true);

      const processed = await h.jobStore.getById(h.job.id);
      expect(processed?.attempts).toBe(1);
      expect(processed?.status).toBe("succeeded");
      expect((await h.jobStore.getById(h.decoyJob.id))?.status).toBe("queued");
      expect(h.objects.size).toBe(3);
      expect(await ownTickets(h)).toHaveLength(0);
    } finally {
      release();
      await running?.catch(() => undefined);
      await cleanup(h);
    }
  });
});
