import { randomUUID } from "node:crypto";

import type { ExtractionJobStore } from "../db/extractionJobStore";
import type { ProviderSettingsStore } from "../db/providerSettingsStore";
import {
  AppError,
  ProviderAuthRequiredError,
  ProviderCliFailedError,
  ProviderCredentialsExhaustedError,
  ProviderError,
  ProviderQuotaExceededError,
  ProviderTimeoutError
} from "../services/errors";
import { createLineartBackgroundRemover, type LineartBackgroundRemoverOptions } from "../services/lineartBackgroundRemover";
import type { ExtractionProviderId, PoseExtractorProvider } from "../services/poseExtractorProvider";
import { sanitizeError } from "../utils/sanitizeError";
import { logger } from "../utils/logger";
import { WORKER_ERROR_CODES } from "./error-codes";

function mapProviderError(error: unknown): { code: string; message: string } {
  if (error instanceof ProviderCredentialsExhaustedError) {
    return { code: error.code, message: error.message };
  }
  if (error instanceof ProviderQuotaExceededError) {
    return { code: error.code, message: error.message };
  }
  if (error instanceof ProviderAuthRequiredError) {
    return { code: error.code, message: error.message };
  }
  if (error instanceof ProviderTimeoutError) {
    return { code: error.code, message: error.message };
  }
  if (error instanceof ProviderCliFailedError) {
    return { code: error.code, message: error.message };
  }
  if (error instanceof ProviderError) {
    return { code: error.code, message: error.message };
  }
  if (error instanceof AppError) {
    return { code: error.code, message: error.message };
  }

  const message = error instanceof Error ? error.message : "Unknown worker error";
  return { code: WORKER_ERROR_CODES.providerError, message };
}

export async function processNextJob(input: {
  jobStore: ExtractionJobStore;
  providerSettingsStore: ProviderSettingsStore;
  createProvider: (providerId: ExtractionProviderId) => PoseExtractorProvider;
  staleLockSeconds: number;
  lineartBackgroundRemover?: ReturnType<typeof createLineartBackgroundRemover>;
  lineartBackgroundRemoverOptions?: LineartBackgroundRemoverOptions;
}): Promise<boolean> {
  const lockToken = randomUUID();
  const job = await input.jobStore.claimNext(lockToken, input.staleLockSeconds);

  if (!job) {
    return false;
  }

  const providerId = await input.providerSettingsStore.getActiveProvider();
  const provider = input.createProvider(providerId);
  const backgroundRemover =
    input.lineartBackgroundRemover ?? createLineartBackgroundRemover(input.lineartBackgroundRemoverOptions);

  try {
    const extracted = await provider.extractPoseImage({
      sourceImageBase64: job.sourceImageBase64,
      sourceMimeType: job.sourceMimeType
    });
    const processed = await backgroundRemover.removeBackground(extracted);
    await input.jobStore.markSucceeded(job.id, lockToken, processed.imageBase64, processed.mimeType);
    logger.info({ jobId: job.id, attempts: job.attempts, providerId }, "worker job succeeded");
  } catch (error) {
    const { code, message } = mapProviderError(error);
    await input.jobStore.markFailedOrRequeue(job.id, lockToken, code, message);
    const info = sanitizeError(error);
    logger.error(
      { jobId: job.id, providerId, name: info.name, code: info.code, message: info.message },
      "worker job failed"
    );
  }

  return true;
}
