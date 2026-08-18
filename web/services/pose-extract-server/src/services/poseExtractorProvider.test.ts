import { describe, expect, it, vi } from "vitest";

import { GeminiService } from "./geminiService";
import { KeyPoolManager } from "./keyPoolManager";
import { GeminiNativeProvider } from "./geminiNativeProvider";
import {
  AllKeysExhaustedError,
  GeminiError,
  GeminiQuotaExceededError,
  ProviderCredentialsExhaustedError,
  ProviderError,
  ProviderQuotaExceededError
} from "./errors";
import { createPoseExtractorProvider } from "./poseExtractorProvider";

describe("createPoseExtractorProvider", () => {
  const geminiService = new GeminiService();
  const keyPoolManager = new KeyPoolManager({
    listKeys: () => [{ id: "k1", name: "k1", apiKey: "key", status: "active", requestsToday: 0, createdAt: "", lastUsedAt: null }],
    updateKeyStatus: () => null
  });

  it("returns GeminiNativeProvider for gemini_native", () => {
    const provider = createPoseExtractorProvider({
      providerId: "gemini_native",
      geminiService,
      keyPoolManager
    });

    expect(provider.id).toBe("gemini_native");
  });

  it("returns HiggsfieldCliProvider for higgsfield_cli", () => {
    const provider = createPoseExtractorProvider({
      providerId: "higgsfield_cli",
      geminiService,
      keyPoolManager,
      higgsfieldOptions: { tmpDir: "/tmp/test-extract" }
    });

    expect(provider.id).toBe("higgsfield_cli");
  });
});

describe("GeminiNativeProvider", () => {
  it("maps quota errors to PROVIDER_QUOTA_EXCEEDED", async () => {
    const geminiService = {
      extractPoseImage: vi.fn().mockRejectedValue(new GeminiQuotaExceededError("quota"))
    };
    const keyPoolManager = {
      getNextActiveKey: vi.fn().mockResolvedValue({ id: "k1", apiKey: "key" }),
      markKeyExhausted: vi.fn().mockResolvedValue(undefined)
    };

    const provider = new GeminiNativeProvider(geminiService as unknown as GeminiService, keyPoolManager as unknown as KeyPoolManager);

    await expect(
      provider.extractPoseImage({ sourceImageBase64: "c291cmNl", sourceMimeType: "image/png" })
    ).rejects.toBeInstanceOf(ProviderQuotaExceededError);

    expect(keyPoolManager.markKeyExhausted).toHaveBeenCalledWith("k1");
  });

  it("maps exhausted keys to PROVIDER_CREDENTIALS_EXHAUSTED", async () => {
    const geminiService = { extractPoseImage: vi.fn() };
    const keyPoolManager = {
      getNextActiveKey: vi.fn().mockRejectedValue(new AllKeysExhaustedError()),
      markKeyExhausted: vi.fn()
    };

    const provider = new GeminiNativeProvider(geminiService as unknown as GeminiService, keyPoolManager as unknown as KeyPoolManager);

    await expect(
      provider.extractPoseImage({ sourceImageBase64: "c291cmNl", sourceMimeType: "image/png" })
    ).rejects.toBeInstanceOf(ProviderCredentialsExhaustedError);
  });

  it("maps gemini errors to PROVIDER_ERROR", async () => {
    const geminiService = {
      extractPoseImage: vi.fn().mockRejectedValue(new GeminiError("fail"))
    };
    const keyPoolManager = {
      getNextActiveKey: vi.fn().mockResolvedValue({ id: "k1", apiKey: "key" }),
      markKeyExhausted: vi.fn()
    };

    const provider = new GeminiNativeProvider(geminiService as unknown as GeminiService, keyPoolManager as unknown as KeyPoolManager);

    await expect(
      provider.extractPoseImage({ sourceImageBase64: "c291cmNl", sourceMimeType: "image/png" })
    ).rejects.toBeInstanceOf(ProviderError);
  });
});
