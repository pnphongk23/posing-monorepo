import type { Sql } from "../db/connection";
import type { PoseStore } from "../db/communityStore";
import type { ExtractionJobStore } from "../db/extractionJobStore";
import type { ProviderSettingsStore } from "../db/providerSettingsStore";
import type { ExtractionProviderId, PoseExtractorProvider } from "../services/poseExtractorProvider";
import type { MediaStorage } from "../services/poseMaterializer";
import { logger } from "../utils/logger";
import { sanitizeError } from "../utils/sanitizeError";
import { processNextJob } from "./job-processor";

// Backwards-compatible alias for the stable loop-error sanitizer (used by tests).
export const describeError = sanitizeError;

// Bounded backoff for transient poll/DB errors. The loop must never let a
// transient failure (e.g. PostgresError 26000 after a pooler session reset)
// escape to run().catch -> process.exit(1).
export const INITIAL_BACKOFF_MS = 1000;
export const MAX_BACKOFF_MS = 30_000;
export const BACKOFF_FACTOR = 2;

export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Sanitized, stable error fields are produced by `sanitizeError` (../utils/sanitizeError)
// and logged without the raw error object (no query/parameters/stack/CLI output).

// Pure: next backoff duration after a failed iteration, capped at MAX_BACKOFF_MS.
export function nextBackoff(current: number): number {
  return Math.min(current * BACKOFF_FACTOR, MAX_BACKOFF_MS);
}

export interface WorkerLoopDeps {
  processNextJob: typeof processNextJob;
  jobStore: ExtractionJobStore;
  providerSettingsStore: ProviderSettingsStore;
  createProvider: (providerId: ExtractionProviderId) => PoseExtractorProvider;
  staleLockSeconds: number;
  pollIntervalMs: number;
  isShuttingDown: () => boolean;
  db?: Sql;
  communityStore?: PoseStore;
  mediaStorage?: MediaStorage;
  sleep?: (ms: number) => Promise<void>;
}

// Poll loop with iteration-level error containment. A transient poll/DB error
// (claimNext, provider lookup, or requeue) is caught, logged without secrets,
// backed off with a bounded exponential schedule, and retried in-bounds. A
// successful round-trip resets the backoff. Exits when `isShuttingDown()` is true
// (wired to SIGINT/SIGTERM in worker-main.ts).
export async function runWorkerLoop(deps: WorkerLoopDeps): Promise<void> {
  const sleepFn = deps.sleep ?? sleep;
  let backoffMs = INITIAL_BACKOFF_MS;
  let consecutiveErrors = 0;

  while (!deps.isShuttingDown()) {
    try {
      const processed = await deps.processNextJob({
        jobStore: deps.jobStore,
        providerSettingsStore: deps.providerSettingsStore,
        createProvider: deps.createProvider,
        staleLockSeconds: deps.staleLockSeconds,
        db: deps.db,
        communityStore: deps.communityStore,
        mediaStorage: deps.mediaStorage
      });
      // Successful DB round-trip (job processed or queue empty): reset backoff.
      backoffMs = INITIAL_BACKOFF_MS;
      consecutiveErrors = 0;
      if (!processed) {
        await sleepFn(deps.pollIntervalMs);
      }
    } catch (error) {
      consecutiveErrors += 1;
      const waitMs = Math.min(backoffMs, MAX_BACKOFF_MS);
      const info = sanitizeError(error);
      logger.error(
        {
          name: info.name,
          code: info.code,
          message: info.message,
          consecutiveErrors,
          backoffMs: waitMs
        },
        "worker poll iteration failed; backing off before retry"
      );
      await sleepFn(waitMs);
      backoffMs = nextBackoff(backoffMs);
    }
  }
}
