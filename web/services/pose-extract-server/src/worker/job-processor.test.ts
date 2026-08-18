import { describe, expect, it, vi } from "vitest";

import { setupTestDatabase } from "../db/testDb";
import { ExtractionJobStore } from "../db/extractionJobStore";
import { ProviderSettingsStore } from "../db/providerSettingsStore";
import {
  ProviderAuthRequiredError,
  ProviderCliFailedError,
  ProviderError,
  ProviderQuotaExceededError,
  ProviderTimeoutError
} from "../services/errors";
import type { ExtractionProviderId, PoseExtractorProvider } from "../services/poseExtractorProvider";
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

async function createStores(): Promise<{ jobStore: ExtractionJobStore; providerSettingsStore: ProviderSettingsStore }> {
  const sql = await setupTestDatabase();
  return {
    jobStore: new ExtractionJobStore(sql),
    providerSettingsStore: new ProviderSettingsStore(sql)
  };
}

function mockProvider(id: ExtractionProviderId, extractPoseImage: PoseExtractorProvider["extractPoseImage"]): PoseExtractorProvider {
  return { id, extractPoseImage };
}

describe("processNextJob", () => {
  it("processes enqueue → mock provider → succeeded", async () => {
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
});
