import { randomUUID } from "node:crypto";

import type { Sql } from "../db/connection";
import { StaleLockError, type ExtractionJobStore } from "../db/extractionJobStore";
import {
  MediaManifestLostError,
  MediaManifestStore,
  PUT_START_LIMIT_MS,
  PUT_TIMEOUT_MS,
  PutWindowClosedError
} from "../db/mediaManifestStore";
import type { PoseStore } from "../db/communityStore";
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
import { buildPoseObjectKey, materializePose, type MediaStorage } from "../services/poseMaterializer";
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

const LOGGABLE_ERROR_CLASSES = new Set([
  "Error",
  "TypeError",
  "RangeError",
  "PostgresError",
  "StaleLockError",
  "MediaManifestLostError",
  "PutWindowClosedError"
]);

/** A fixed class/code pair, never the message: messages can carry keys or user data. */
function errorIdentity(error: unknown): { errorClass: string; errorCode: string | null } {
  if (!error || typeof error !== "object") {
    return { errorClass: "Error", errorCode: null };
  }
  const candidate = error as { name?: unknown; code?: unknown };
  const errorClass =
    typeof candidate.name === "string" && LOGGABLE_ERROR_CLASSES.has(candidate.name) ? candidate.name : "Error";
  const errorCode = typeof candidate.code === "string" && /^[A-Za-z0-9_]{1,16}$/.test(candidate.code) ? candidate.code : null;
  return { errorClass, errorCode };
}

function isUniqueViolation(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const err = error as { code?: string; message?: string };
  return (
    err.code === "23505" ||
    (typeof err.message === "string" &&
      (err.message.includes("duplicate key value violates unique constraint") ||
        err.message.includes("unique constraint") ||
        err.message.includes("idx_poses_current_job_id")))
  );
}

export interface ProcessNextJobInput {
  jobStore: ExtractionJobStore;
  providerSettingsStore: ProviderSettingsStore;
  createProvider: (providerId: ExtractionProviderId) => PoseExtractorProvider;
  staleLockSeconds: number;
  db?: Sql;
  communityStore?: PoseStore;
  mediaStorage?: MediaStorage;
  manifests?: MediaManifestStore;
  /** A put may not start later than this after its manifest was written. */
  putStartLimitMs?: number;
  /** Clock for the upload window, injectable for tests. */
  now?: () => number;
  lineartBackgroundRemover?: ReturnType<typeof createLineartBackgroundRemover>;
  lineartBackgroundRemoverOptions?: LineartBackgroundRemoverOptions;
}

export async function processNextJob(input: ProcessNextJobInput): Promise<boolean> {
  const lockToken = randomUUID();
  const job = await input.jobStore.claimNext(lockToken, input.staleLockSeconds);

  if (!job) {
    return false;
  }

  const providerId = await input.providerSettingsStore.getActiveProvider();
  const provider = input.createProvider(providerId);
  const backgroundRemover =
    input.lineartBackgroundRemover ?? createLineartBackgroundRemover(input.lineartBackgroundRemoverOptions);

  if (!job.sourceImageBase64) {
    await input.jobStore.markFailedOrRequeue(
      job.id,
      lockToken,
      WORKER_ERROR_CODES.sourceMissing,
      "Source image is missing"
    );
    logger.error({ jobId: job.id }, "worker job failed: source image is missing");
    return true;
  }

  let processed: { imageBase64: string; mimeType: "image/png" | "image/jpeg" | "image/webp" };
  try {
    const extracted = await provider.extractPoseImage({
      sourceImageBase64: job.sourceImageBase64,
      sourceMimeType: job.sourceMimeType
    });
    processed = await backgroundRemover.removeBackground(extracted);
  } catch (error) {
    const { code, message } = mapProviderError(error);
    // A provider authentication failure is terminal: requeueing only delays the same answer and
    // burns the job's remaining attempts, so the client is told on this attempt.
    if (error instanceof ProviderAuthRequiredError) {
      await input.jobStore.markFailed(job.id, lockToken, code, message);
    } else {
      await input.jobStore.markFailedOrRequeue(job.id, lockToken, code, message);
    }
    const info = sanitizeError(error);
    logger.error(
      { jobId: job.id, providerId, name: info.name, code: info.code, message: info.message },
      "worker job failed"
    );
    return true;
  }

  // Legacy admin (owner-less) path: result image saved directly on job row.
  if (!job.ownerAccountId) {
    await input.jobStore.markSucceeded(job.id, lockToken, processed.imageBase64, processed.mimeType);
    logger.info({ jobId: job.id, attempts: job.attempts, providerId }, "worker job succeeded");
    return true;
  }

  // Owner path: materialize Pose + 3 assets, null base64 on job row.
  const { db, communityStore, mediaStorage } = input;
  if (!db || !communityStore || !mediaStorage) {
    await input.jobStore.markFailedOrRequeue(
      job.id,
      lockToken,
      WORKER_ERROR_CODES.poseMaterializeFailed,
      "Storage, database, or community store is not configured for owner pose materialization"
    );
    logger.error({ jobId: job.id }, "owner job materialization failed: dependencies missing");
    return true;
  }

  const safeFinalize = async (targetPoseId: string): Promise<void> => {
    try {
      await db.begin(async (tx) => {
        await input.jobStore.markSucceededWithPose(tx, job.id, lockToken, targetPoseId);
      });
      logger.info(
        { jobId: job.id, poseId: targetPoseId, attempts: job.attempts, providerId },
        "worker owner job finalized"
      );
    } catch (error) {
      if (error instanceof StaleLockError) {
        logger.warn(
          { jobId: job.id, poseId: targetPoseId, error },
          "stale lock during safeFinalize; ignoring"
        );
        return;
      }
      throw error;
    }
  };

  const poseId = randomUUID();
  const draft = job.poseDraft;
  const manifests = input.manifests ?? new MediaManifestStore(db);
  const putStartLimitMs = input.putStartLimitMs ?? PUT_START_LIMIT_MS;
  const now = input.now ?? Date.now;
  const plannedKeys = [
    buildPoseObjectKey("poses", poseId, "original", job.sourceMimeType),
    buildPoseObjectKey("poses", poseId, "skeleton", processed.mimeType),
    buildPoseObjectKey("poses", poseId, "thumbnail", processed.mimeType)
  ];

  let manifestRecorded = false;
  let manifestCreatedAtMs = 0;

  // Uploads are gated by the attempt's manifest: no put starts outside its window, and a
  // put that cannot start must fail before it touches storage.
  const guardedStorage: MediaStorage = {
    put: async (fileKey, body, mimeType, options) => {
      if (!manifestRecorded || now() - manifestCreatedAtMs > putStartLimitMs) {
        throw new PutWindowClosedError();
      }
      await mediaStorage.put(fileKey, body, mimeType, {
        ...options,
        abortSignal: AbortSignal.timeout(PUT_TIMEOUT_MS)
      });
    },
    remove: mediaStorage.remove,
    publicUrl: mediaStorage.publicUrl
  };

  /** Any failure after the manifest exists hands its keys to the deletion tickets. */
  const abandonAttempt = async (): Promise<void> => {
    try {
      await manifests.abandon(poseId);
    } catch (error) {
      // The manifest row is still there, so the stale sweep moves it after the horizon.
      logger.error(
        { jobId: job.id, ...errorIdentity(error) },
        "worker owner job failed: could not move its media manifest to deletion tickets"
      );
    }
  };

  try {
    const existing = await communityStore.getPoseByCurrentJobId(job.id);
    if (existing) {
      await safeFinalize(existing.poseId);
      return true;
    }

    try {
      const { createdAt } = await manifests.record({
        poseId,
        jobId: job.id,
        ownerAccountId: job.ownerAccountId,
        keys: plannedKeys
      });
      manifestCreatedAtMs = Date.parse(createdAt);
      manifestRecorded = true;
    } catch (error) {
      await input.jobStore.markFailedOrRequeue(
        job.id,
        lockToken,
        WORKER_ERROR_CODES.poseMaterializeFailed,
        "Failed to record the media manifest for this attempt"
      );
      logger.error(
        { jobId: job.id, keyCount: plannedKeys.length, ...errorIdentity(error) },
        "worker owner job materialization failed: media manifest not recorded"
      );
      return true;
    }

    await materializePose({
      poseId,
      ownerAccountId: job.ownerAccountId,
      currentJobId: job.id,
      metadata: {
        name: draft?.name || "Pose",
        tags: draft?.tags || [],
        description: draft?.description ?? null,
        bodyParts: [],
        difficulty: null
      },
      source: { b64: job.sourceImageBase64, mime: job.sourceMimeType },
      result: { b64: processed.imageBase64, mime: processed.mimeType },
      keyPrefix: "poses",
      mediaStorage: guardedStorage,
      removeUploadedOnFailure: false,
      createPose: (createInput) =>
        db.begin(async (tx) => {
          // Job lock first (same order as the account purge), then the manifest row.
          await input.jobStore.markSucceededWithPose(tx, job.id, lockToken, poseId);
          if (!(await manifests.consume(tx, poseId, job.id))) {
            throw new MediaManifestLostError();
          }
          return communityStore.createPose(createInput, tx);
        })
    });
    logger.info(
      { jobId: job.id, poseId, attempts: job.attempts, providerId },
      "worker owner job materialized and succeeded"
    );
  } catch (error) {
    if (error instanceof StaleLockError) {
      logger.warn({ jobId: job.id, error }, "stale lock during pose materialization; ignoring");
      await abandonAttempt();
      return true;
    }
    if (error instanceof MediaManifestLostError) {
      await abandonAttempt();
      await input.jobStore.markFailedOrRequeue(
        job.id,
        lockToken,
        WORKER_ERROR_CODES.poseMaterializeFailed,
        "Media manifest was consumed before the pose was finalized"
      );
      logger.warn({ jobId: job.id }, "worker owner job aborted: media manifest lost");
      return true;
    }
    if (isUniqueViolation(error)) {
      const winner = await communityStore.getPoseByCurrentJobId(job.id);
      if (winner) {
        await safeFinalize(winner.poseId);
        await abandonAttempt();
        return true;
      }
    }
    const msg = error instanceof Error ? error.message : "Failed to materialize pose";
    // Anything after the manifest may have left objects behind, whatever failed.
    await abandonAttempt();
    await input.jobStore.markFailedOrRequeue(
      job.id,
      lockToken,
      WORKER_ERROR_CODES.poseMaterializeFailed,
      msg
    );
    logger.error(
      { jobId: job.id, error: sanitizeError(error) },
      "worker owner job materialization failed"
    );
  }

  return true;
}
