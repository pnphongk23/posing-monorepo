import { randomUUID } from "node:crypto";

import type { Sql } from "../db/connection";
import { StaleLockError, type ExtractionJobStore } from "../db/extractionJobStore";
import { ObjectDeletionOutbox, ObjectLeaseLostError } from "../db/objectDeletionOutbox";
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

/** A fixed class/code pair, never the message: messages can carry keys or user data. */
function errorIdentity(error: unknown): { errorClass: string; errorCode: string | null } {
  if (!error || typeof error !== "object") {
    return { errorClass: "UnknownError", errorCode: null };
  }
  const candidate = error as { name?: unknown; code?: unknown };
  const errorClass = typeof candidate.name === "string" && candidate.name ? candidate.name : "Error";
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
  objectDeletions?: ObjectDeletionOutbox;
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
    await input.jobStore.markFailedOrRequeue(job.id, lockToken, code, message);
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
  const objectDeletions = input.objectDeletions ?? new ObjectDeletionOutbox(db);
  const plannedKeys = [
    buildPoseObjectKey("poses", poseId, "original", job.sourceMimeType),
    buildPoseObjectKey("poses", poseId, "skeleton", processed.mimeType),
    buildPoseObjectKey("poses", poseId, "thumbnail", processed.mimeType)
  ];

  // The reservation is a lease: it is renewed before and after every upload, so a slow job
  // keeps its claim while a sweep can still collect keys the job abandoned. Renewals are
  // serialised because the three uploads start together.
  let leaseChain: Promise<void> = Promise.resolve();
  const renewLease = (): Promise<boolean> => {
    const renewal = leaseChain.then(() => objectDeletions.renew(plannedKeys));
    leaseChain = renewal.then(
      () => undefined,
      () => undefined
    );
    return renewal;
  };

  const assertLease = async (): Promise<void> => {
    if (!(await renewLease())) {
      throw new ObjectLeaseLostError();
    }
  };

  const failWithReclaimedKeys = async (reason: string): Promise<void> => {
    try {
      await objectDeletions.reclaim(plannedKeys);
    } catch (error) {
      logger.error(
        { jobId: job.id, keyCount: plannedKeys.length, ...errorIdentity(error) },
        "worker owner job failed: could not reclaim its object keys"
      );
    }
    await input.jobStore.markFailedOrRequeue(
      job.id,
      lockToken,
      WORKER_ERROR_CODES.poseMaterializeFailed,
      reason
    );
    logger.warn(
      { jobId: job.id, keyCount: plannedKeys.length, reason },
      "worker owner job aborted: object lease lost"
    );
  };

  try {
    const existing = await communityStore.getPoseByCurrentJobId(job.id);
    if (existing) {
      await safeFinalize(existing.poseId);
      return true;
    }

    // The keys are durable before the first upload, so neither a failed finalize nor a failed
    // cleanup can strand an object: the sweep deletes whatever the pose never came to own.
    try {
      await objectDeletions.reserve(plannedKeys);
    } catch (error) {
      await input.jobStore.markFailedOrRequeue(
        job.id,
        lockToken,
        WORKER_ERROR_CODES.poseMaterializeFailed,
        "Failed to record object keys for deletion"
      );
      logger.error(
        { jobId: job.id, keyCount: plannedKeys.length, ...errorIdentity(error) },
        "worker owner job materialization failed: object keys not recorded"
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
      mediaStorage,
      beforeUpload: assertLease,
      afterUpload: assertLease,
      onCleanupFailed: async (keys) => {
        // Those keys are already recorded, so the sweep retries them without another write.
        logger.warn(
          { jobId: job.id, failedCount: keys.length },
          "pose object cleanup failed; left for the deletion sweep"
        );
      },
      createPose: (createInput) =>
        db.begin(async (tx) => {
          // Verified and locked inside the finalize transaction: a lease that lapsed or was
          // claimed by a drain can never end with a succeeded job pointing at deleted objects.
          if (!(await objectDeletions.acquireFinalizeLease(tx, plannedKeys))) {
            throw new ObjectLeaseLostError();
          }
          const pose = await communityStore.createPose(createInput, tx);
          await input.jobStore.markSucceededWithPose(tx, job.id, lockToken, poseId);
          await objectDeletions.ackKeys(tx, plannedKeys);
          return pose;
        })
    });
    logger.info(
      { jobId: job.id, poseId, attempts: job.attempts, providerId },
      "worker owner job materialized and succeeded"
    );
  } catch (error) {
    if (error instanceof StaleLockError) {
      logger.warn({ jobId: job.id, error }, "stale lock during pose materialization; ignoring");
      return true;
    }
    if (error instanceof ObjectLeaseLostError) {
      await failWithReclaimedKeys("Object storage lease expired before the pose was finalized");
      return true;
    }
    if (isUniqueViolation(error)) {
      const winner = await communityStore.getPoseByCurrentJobId(job.id);
      if (winner) {
        await safeFinalize(winner.poseId);
        return true;
      }
    }
    const msg = error instanceof Error ? error.message : "Failed to materialize pose";
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
