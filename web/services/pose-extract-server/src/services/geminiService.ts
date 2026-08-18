import { GeminiError, GeminiQuotaExceededError } from "./errors";
import { DEFAULT_EXTRACT_PROMPT } from "./extractPrompt";
import type { ExtractedImage } from "./types";

const DEFAULT_MODEL = "gemini-2.0-flash-exp";
const DEFAULT_BASE_URL = "https://generativelanguage.googleapis.com/v1beta";
const BASE64_REGEX = /^[A-Za-z0-9+/]+={0,2}$/;

interface GeminiServiceOptions {
  fetchImpl?: typeof fetch;
  model?: string;
  baseUrl?: string;
}

interface ExtractPoseImageInput {
  apiKey: string;
  sourceImageBase64: string;
  sourceMimeType: string;
  prompt?: string;
}

type JsonObject = Record<string, unknown>;

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null;
}

function getProviderError(payload: unknown): JsonObject | null {
  if (!isObject(payload) || !isObject(payload.error)) {
    return null;
  }
  return payload.error;
}

function isAllowedMimeType(value: string): value is ExtractedImage["mimeType"] {
  return value === "image/png" || value === "image/jpeg" || value === "image/webp";
}

function isValidBase64(value: string): boolean {
  return value.length > 0 && value.length % 4 === 0 && BASE64_REGEX.test(value);
}

function providerMessage(payload: unknown): string | undefined {
  const error = getProviderError(payload);
  if (!error) {
    return undefined;
  }
  return typeof error.message === "string" ? error.message : undefined;
}

function isQuotaError(status: number, payload: unknown): boolean {
  if (status === 429) {
    return true;
  }

  const error = getProviderError(payload);
  if (!error) {
    return false;
  }

  if (error.status === "RESOURCE_EXHAUSTED" || error.code === 429 || error.code === 8) {
    return true;
  }

  if (typeof error.message === "string") {
    const lowered = error.message.toLowerCase();
    return lowered.includes("quota") || lowered.includes("rate limit");
  }

  return false;
}

function getInlineImage(payload: unknown): { data: string; mimeType: string } | null {
  if (!isObject(payload) || !Array.isArray(payload.candidates)) {
    return null;
  }

  for (const candidate of payload.candidates) {
    if (!isObject(candidate) || !isObject(candidate.content) || !Array.isArray(candidate.content.parts)) {
      continue;
    }

    for (const part of candidate.content.parts) {
      if (!isObject(part)) {
        continue;
      }

      const inlineData = isObject(part.inlineData) ? part.inlineData : isObject(part.inline_data) ? part.inline_data : null;
      if (!inlineData) {
        continue;
      }

      if (typeof inlineData.data !== "string" || typeof inlineData.mimeType !== "string") {
        continue;
      }

      return {
        data: inlineData.data,
        mimeType: inlineData.mimeType
      };
    }
  }

  return null;
}

function normalizeExtractedImage(payload: unknown): ExtractedImage {
  const inlineImage = getInlineImage(payload);
  if (!inlineImage) {
    throw new GeminiError("Malformed Gemini response: missing image payload");
  }

  const imageBase64 = inlineImage.data.trim();
  const mimeType = inlineImage.mimeType.trim().toLowerCase();

  if (!isValidBase64(imageBase64)) {
    throw new GeminiError("Malformed Gemini response: invalid image data");
  }

  if (!isAllowedMimeType(mimeType)) {
    throw new GeminiError(`Unsupported Gemini mime type: ${mimeType || "unknown"}`);
  }

  return {
    imageBase64,
    mimeType
  };
}

export class GeminiService {
  private readonly fetchImpl: typeof fetch;
  private readonly model: string;
  private readonly baseUrl: string;

  constructor(options: GeminiServiceOptions = {}) {
    this.fetchImpl = options.fetchImpl ?? fetch;
    this.model = options.model ?? DEFAULT_MODEL;
    this.baseUrl = options.baseUrl ?? DEFAULT_BASE_URL;
  }

  async extractPoseImage(input: ExtractPoseImageInput): Promise<ExtractedImage> {
    let response: Response;
    try {
      response = await this.fetchImpl(this.buildRequestUrl(input.apiKey), {
        method: "POST",
        headers: {
          "content-type": "application/json"
        },
        body: JSON.stringify({
          contents: [
            {
              role: "user",
              parts: [
                {
                  text: input.prompt ?? DEFAULT_EXTRACT_PROMPT
                },
                {
                  inlineData: {
                    mimeType: input.sourceMimeType,
                    data: input.sourceImageBase64
                  }
                }
              ]
            }
          ]
        })
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown Gemini transport failure";
      throw new GeminiError(`Gemini request failed: ${message}`);
    }

    const payload = await this.readJson(response);

    if (!response.ok || getProviderError(payload)) {
      if (isQuotaError(response.status, payload)) {
        throw new GeminiQuotaExceededError(providerMessage(payload) ?? "Gemini quota/rate-limit reached");
      }
      throw new GeminiError(providerMessage(payload) ?? `Gemini API failed with status ${response.status}`);
    }

    return normalizeExtractedImage(payload);
  }

  private buildRequestUrl(apiKey: string): string {
    const encodedModel = encodeURIComponent(this.model);
    const encodedKey = encodeURIComponent(apiKey);
    return `${this.baseUrl}/models/${encodedModel}:generateContent?key=${encodedKey}`;
  }

  private async readJson(response: Response): Promise<unknown> {
    try {
      return await response.json();
    } catch {
      throw new GeminiError("Malformed Gemini response: invalid JSON");
    }
  }
}
