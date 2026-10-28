import { randomUUID } from "node:crypto";

import { describe, expect, it, vi } from "vitest";

import type { Sql } from "../db/connection";
import { ObjectDeletionOutbox } from "../db/objectDeletionOutbox";
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

  it("upload failure removes uploaded keys and requeues POSE_MATERIALIZE_FAILED", async () => {
    const { sql, jobStore, communityStore, providerSettingsStore } = await createStores();
    const { mediaStorage, removed } = createMediaStorageMock();
    const extractPoseImage = vi.fn().mockResolvedValue({
      imageBase64: Buffer.from("skeleton").toString("base64"),
      mimeType: "image/png"
    });

    mediaStorage.put = vi.fn(async (key: string) => {
      if (key.includes("thumbnail")) {
        throw new Error("R2 upload timed out");
      }
    });

    const ownerAccountId = await createOwnerAccount(sql);
    const job = await jobStore.enqueue({
      ownerAccountId,
      poseDraft: { name: "Failed Upload", tags: [], description: null },
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png",
      maxAttempts: 3
    });

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

    expect(removed.length).toBeGreaterThan(0);

    const updatedJob = await jobStore.getById(job.id);
    expect(updatedJob?.status).toBe("queued");
    expect(updatedJob?.attempts).toBe(1);
    expect(updatedJob?.errorCode).toBe("POSE_MATERIALIZE_FAILED");
    expect(updatedJob?.errorMessage).toContain("R2 upload timed out");

    const pose = await communityStore.getPoseByCurrentJobId(job.id);
    expect(pose).toBeNull();
  });

  it("admin jobs keep result_image_base64 without creating pose", async () => {
    const { sql, jobStore, communityStore, providerSettingsStore } = await createStores();
    const { mediaStorage } = createMediaStorageMock();
    const extractPoseImage = vi.fn().mockResolvedValue({
      imageBase64: "admin-result-b64",
      mimeType: "image/png"
    });

    const job = await jobStore.enqueue({
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });

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

    const updated = await jobStore.getById(job.id);
    expect(updated?.status).toBe("succeeded");
    expect(updated?.resultImageBase64).toBe("admin-result-b64");
    expect(updated?.poseId).toBeNull();
    expect(mediaStorage.put).not.toHaveBeenCalled();
  });

  it("stale lock at finalize -> transaction rolls back, no Pose row, keys removed, job row untouched", async () => {
    const { sql, jobStore, communityStore, providerSettingsStore } = await createStores();
    const { mediaStorage, removed } = createMediaStorageMock();

    const ownerAccountId = await createOwnerAccount(sql);
    const job = await jobStore.enqueue({
      ownerAccountId,
      poseDraft: { name: "Stale Lock Test", tags: [], description: null },
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png",
      maxAttempts: 3
    });

    // During extraction (before materializePose opens the transaction), steal the lock in DB
    const extractPoseImage = vi.fn().mockImplementation(async () => {
      await sql`UPDATE extraction_jobs SET lock_token = 'stolen-lock-token' WHERE id = ${job.id}`;
      return {
        imageBase64: Buffer.from("skeleton").toString("base64"),
        mimeType: "image/png" as const
      };
    });

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

    // Transaction must roll back: no pose in DB
    const pose = await communityStore.getPoseByCurrentJobId(job.id);
    expect(pose).toBeNull();

    // Uploaded keys must have been removed
    expect(removed).toHaveLength(3);

    // Job row was not touched by loser (not requeued, lock token remains 'stolen-lock-token')
    const updatedJob = await jobStore.getById(job.id);
    expect(updatedJob?.lockToken).toBe("stolen-lock-token");
    expect(updatedJob?.status).toBe("processing");
  });

  it("unique collision -> loser's keys removed, job finalized to the existing poseId", async () => {
    const { sql, jobStore, communityStore, providerSettingsStore } = await createStores();
    const { mediaStorage, removed } = createMediaStorageMock();
    const extractPoseImage = vi.fn().mockResolvedValue({
      imageBase64: Buffer.from("skeleton").toString("base64"),
      mimeType: "image/png"
    });

    const ownerAccountId = await createOwnerAccount(sql);
    const job = await jobStore.enqueue({
      ownerAccountId,
      poseDraft: { name: "Collision Winner", tags: [], description: null },
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });

    // Pre-insert winner pose for this job
    await communityStore.createPose({
      poseId: "winner-pose-id",
      ownerAccountId,
      name: "Winner Pose",
      originalUrl: "https://cdn.example.com/poses/winner/original.png",
      skeletonUrl: "https://cdn.example.com/poses/winner/skeleton.png",
      thumbnailUrl: "https://cdn.example.com/poses/winner/thumbnail.png",
      tags: [],
      difficulty: null,
      description: null,
      bodyParts: [],
      currentJobId: job.id
    });

    // Mock initial check to return null (simulating that the race occurred after check)
    vi.spyOn(communityStore, "getPoseByCurrentJobId").mockResolvedValueOnce(null);

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

    // Loser's uploaded keys cleaned up
    expect(removed).toHaveLength(3);

    // Job finalized to winner pose
    const updatedJob = await jobStore.getById(job.id);
    expect(updatedJob?.status).toBe("succeeded");
    expect(updatedJob?.poseId).toBe("winner-pose-id");
    expect(updatedJob?.sourceImageBase64).toBeNull();
  });

  it("existing Pose + stale/null lock token -> no markFailedOrRequeue call and job stays succeeded", async () => {
    const { sql, jobStore, communityStore, providerSettingsStore } = await createStores();
    const { mediaStorage } = createMediaStorageMock();
    const extractPoseImage = vi.fn().mockResolvedValue({
      imageBase64: Buffer.from("skeleton").toString("base64"),
      mimeType: "image/png"
    });

    const ownerAccountId = await createOwnerAccount(sql);
    const job = await jobStore.enqueue({
      ownerAccountId,
      poseDraft: { name: "Already Succeeded", tags: [], description: null },
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });

    // Pre-insert pose for this job
    await communityStore.createPose({
      poseId: "existing-pose-id",
      ownerAccountId,
      name: "Already Succeeded",
      originalUrl: "https://cdn.example.com/poses/existing/original.png",
      skeletonUrl: "https://cdn.example.com/poses/existing/skeleton.png",
      thumbnailUrl: "https://cdn.example.com/poses/existing/thumbnail.png",
      tags: [],
      difficulty: null,
      description: null,
      bodyParts: [],
      currentJobId: job.id
    });

    // Set job to succeeded with NULL lock token
    await sql`
      UPDATE extraction_jobs
      SET status = 'succeeded', pose_id = 'existing-pose-id', lock_token = NULL, source_image_base64 = ${Buffer.from("source").toString("base64")}
      WHERE id = ${job.id}
    `;

    const markFailedSpy = vi.spyOn(jobStore, "markFailedOrRequeue");

    // Call processNextJob: safeFinalize will encounter StaleLockError because lockToken is null/changed
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

    expect(markFailedSpy).not.toHaveBeenCalled();

    const updatedJob = await jobStore.getById(job.id);
    expect(updatedJob?.status).toBe("succeeded");
    expect(updatedJob?.errorCode).toBeNull();
  });

  it("cleanup failure (mediaStorage.remove rejects) -> job still requeued with POSE_MATERIALIZE_FAILED, rejection logged, not thrown", async () => {
    const { sql, jobStore, communityStore, providerSettingsStore } = await createStores();
    const extractPoseImage = vi.fn().mockResolvedValue({
      imageBase64: Buffer.from("skeleton").toString("base64"),
      mimeType: "image/png"
    });

    const mediaStorage: MediaStorage = {
      put: vi.fn(async (key: string) => {
        if (key.includes("thumbnail")) {
          throw new Error("R2 upload timeout");
        }
      }),
      remove: vi.fn(async () => {
        throw new Error("R2 delete failed: network down");
      }),
      publicUrl: (key: string) => `https://cdn.example.com/${key}`
    };

    const ownerAccountId = await createOwnerAccount(sql);
    const job = await jobStore.enqueue({
      ownerAccountId,
      poseDraft: { name: "Double Fail", tags: [], description: null },
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png",
      maxAttempts: 3
    });

    // processNextJob must not throw
    await expect(
      processNextJob({
        jobStore,
        providerSettingsStore,
        createProvider: () => mockProvider("gemini_native", extractPoseImage),
        staleLockSeconds: 120,
        db: sql,
        communityStore,
        mediaStorage,
        lineartBackgroundRemover: createBackgroundRemoverStub()
      })
    ).resolves.toBe(true);

    const updatedJob = await jobStore.getById(job.id);
    expect(updatedJob?.status).toBe("queued");
    expect(updatedJob?.errorCode).toBe("POSE_MATERIALIZE_FAILED");
  });

  it("queues the keys whose cleanup failed so a later sweep can delete them", async () => {
    const { sql, jobStore, communityStore, providerSettingsStore } = await createStores();
    const remove = vi.fn(async (key: string) => {
      if (key.includes("skeleton")) {
        throw new Error("R2 delete failed");
      }
    });
    const mediaStorage: MediaStorage = {
      put: vi.fn(async () => undefined),
      remove,
      publicUrl: (key: string) => `https://cdn.example.com/${key}`
    };

    const ownerAccountId = await createOwnerAccount(sql);
    const job = await jobStore.enqueue({
      ownerAccountId,
      poseDraft: { name: "Lost Finalize", tags: [], description: null },
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });

    const extractPoseImage = vi.fn().mockImplementation(async () => {
      await sql`UPDATE extraction_jobs SET lock_token = 'stolen-lock-token' WHERE id = ${job.id}`;
      return {
        imageBase64: Buffer.from("skeleton").toString("base64"),
        mimeType: "image/png" as const
      };
    });

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

    const rows = await new ObjectDeletionOutbox(sql).list();
    expect(rows.map((row) => row.key)).toEqual([expect.stringMatching(/^poses\/[0-9a-f-]{36}\/skeleton\.png$/)]);

    const pose = await communityStore.getPoseByCurrentJobId(job.id);
    expect(pose).toBeNull();
  });
});
