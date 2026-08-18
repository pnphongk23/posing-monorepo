import { AllKeysExhaustedError, GeminiError, GeminiQuotaExceededError } from "./errors";
import {
  ProviderCredentialsExhaustedError,
  ProviderError,
  ProviderQuotaExceededError
} from "./errors";
import type { GeminiService } from "./geminiService";
import type { KeyPoolManager } from "./keyPoolManager";
import type { PoseExtractorProvider } from "./poseExtractorProvider";
import type { ExtractedImage } from "./types";

export class GeminiNativeProvider implements PoseExtractorProvider {
  readonly id = "gemini_native" as const;

  constructor(
    private readonly geminiService: GeminiService,
    private readonly keyPoolManager: KeyPoolManager
  ) {}

  async extractPoseImage(input: {
    sourceImageBase64: string;
    sourceMimeType: string;
  }): Promise<ExtractedImage> {
    let apiKey;
    try {
      apiKey = await this.keyPoolManager.getNextActiveKey();
    } catch (error) {
      if (error instanceof AllKeysExhaustedError) {
        throw new ProviderCredentialsExhaustedError(error.message);
      }
      throw error;
    }

    try {
      return await this.geminiService.extractPoseImage({
        apiKey: apiKey.apiKey,
        sourceImageBase64: input.sourceImageBase64,
        sourceMimeType: input.sourceMimeType
      });
    } catch (error) {
      if (error instanceof GeminiQuotaExceededError) {
        await this.keyPoolManager.markKeyExhausted(apiKey.id);
        throw new ProviderQuotaExceededError(error.message);
      }
      if (error instanceof GeminiError) {
        throw new ProviderError(error.message);
      }
      throw error;
    }
  }
}
