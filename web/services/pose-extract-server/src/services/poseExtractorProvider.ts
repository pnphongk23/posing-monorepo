import { GeminiNativeProvider } from "./geminiNativeProvider";
import { HiggsfieldCliProvider, type HiggsfieldCliProviderOptions } from "./higgsfieldCliProvider";
import type { KeyPoolManager } from "./keyPoolManager";
import type { GeminiService } from "./geminiService";
import type { ExtractedImage } from "./types";

export type ExtractionProviderId = "gemini_native" | "higgsfield_cli";

export const SUPPORTED_EXTRACTION_PROVIDERS: readonly ExtractionProviderId[] = ["gemini_native", "higgsfield_cli"] as const;

export function isExtractionProviderId(value: string): value is ExtractionProviderId {
  return (SUPPORTED_EXTRACTION_PROVIDERS as readonly string[]).includes(value);
}

export interface PoseExtractorProvider {
  readonly id: ExtractionProviderId;

  extractPoseImage(input: {
    sourceImageBase64: string;
    sourceMimeType: string;
  }): Promise<ExtractedImage>;
}

export type { ExtractedImage };

export interface PoseExtractorProviderFactoryDeps {
  providerId: ExtractionProviderId;
  geminiService: GeminiService;
  keyPoolManager: KeyPoolManager;
  higgsfieldOptions?: HiggsfieldCliProviderOptions;
}

export function createPoseExtractorProvider(deps: PoseExtractorProviderFactoryDeps): PoseExtractorProvider {
  switch (deps.providerId) {
    case "gemini_native":
      return new GeminiNativeProvider(deps.geminiService, deps.keyPoolManager);
    case "higgsfield_cli":
      return new HiggsfieldCliProvider(deps.higgsfieldOptions);
    default: {
      const exhaustive: never = deps.providerId;
      throw new Error(`Unsupported extraction provider: ${exhaustive}`);
    }
  }
}
