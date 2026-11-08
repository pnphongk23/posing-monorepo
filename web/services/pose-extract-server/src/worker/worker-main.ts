import "dotenv/config";

import { getEnv } from "../config/env";
import { applySchema, closeDatabase, createDatabase } from "../db/connection";
import { ExtractionJobStore } from "../db/extractionJobStore";
import { PoseStore } from "../db/communityStore";
import { ProviderSettingsStore } from "../db/providerSettingsStore";
import { GeminiService } from "../services/geminiService";
import { defaultCredentialsPath, withCredentialLock } from "../services/higgsfieldCredentialGuard";
import { isHiggsfieldSelfRefreshEnabled } from "../services/higgsfieldSelfRefresh";
import { KeyPoolManager } from "../services/keyPoolManager";
import { KeyStore } from "../services/keyStore";
import { createPoseExtractorProvider } from "../services/poseExtractorProvider";
import { MediaManifestStore, PUT_TIMEOUT_MS } from "../db/mediaManifestStore";
import { buildPublicUrl, deleteObject, uploadObject } from "../services/r2Storage";
import { logger } from "../utils/logger";
import { startHiggsfieldKeepalive } from "./higgsfield-keepalive";
import { processNextJob } from "./job-processor";
import { runWorkerLoop } from "./worker-loop";
import { sanitizeError } from "../utils/sanitizeError";

const POLL_INTERVAL_MS = Number(process.env.WORKER_POLL_INTERVAL_MS ?? "1000");
const STALE_LOCK_SECONDS = Number(process.env.WORKER_STALE_LOCK_SECONDS ?? "120");
/** Upper bound on waiting for an in-flight credential refresh when the worker is asked to stop. */
const SHUTDOWN_LOCK_TIMEOUT_MS = 20_000;

async function run(): Promise<void> {
  const env = getEnv();
  const sql = createDatabase(env.DATABASE_URL);
  await applySchema(sql);
  const jobStore = new ExtractionJobStore(sql);
  const providerSettingsStore = new ProviderSettingsStore(sql);
  const communityStore = new PoseStore(sql);
  const mediaManifests = new MediaManifestStore(sql);
  const keyStore = new KeyStore(sql);
  const keyPoolManager = new KeyPoolManager(keyStore);
  const geminiService = new GeminiService();

  const publicUrlBase = process.env.R2_PUBLIC_URL ?? "";
  const mediaStorage = {
    put: async (fileKey: string, body: Buffer, mimeType: string) => {
      await uploadObject({ fileKey, body, mimeType, abortSignal: AbortSignal.timeout(PUT_TIMEOUT_MS) });
    },
    remove: async (fileKey: string) => {
      await deleteObject(fileKey);
    },
    publicUrl: (fileKey: string) => buildPublicUrl(publicUrlBase, fileKey)
  };

  const createProvider = (providerId: Parameters<typeof createPoseExtractorProvider>[0]["providerId"]) =>
    createPoseExtractorProvider({
      providerId,
      geminiService,
      keyPoolManager
    });

  // Credential owner: when HIGGSFIELD_SELF_REFRESH is on the tick refreshes the token inside the
  // credential mutex an hour before expiry; otherwise it only records an expired credential without
  // ever spawning the CLI (which would delete the credential file).
  const higgsfieldKeepalive = startHiggsfieldKeepalive({
    credentialsPath: defaultCredentialsPath(process.env)
  });

  logger.info(
    {
      pollIntervalMs: POLL_INTERVAL_MS,
      staleLockSeconds: STALE_LOCK_SECONDS,
      // Booleans only: never the credential path or any token material.
      selfRefreshEnabled: isHiggsfieldSelfRefreshEnabled(process.env),
      activeProvider: await providerSettingsStore.getActiveProvider()
    },
    "worker started"
  );

  let shuttingDown = false;
  const shutdown = async (signal: NodeJS.Signals): Promise<void> => {
    if (shuttingDown) {
      return;
    }
    shuttingDown = true;
    logger.info({ signal }, "worker shutting down");
    higgsfieldKeepalive.stop();
    // A refresh may be past the provider's rotation and still writing the new token. Exiting now
    // would lose that refresh token for good, so wait for the credential lock to drain (bounded, in
    // case a CLI spawn or a stuck write never releases it).
    const lockDrained = withCredentialLock(async () => undefined);
    const lockTimeout = new Promise<void>((resolve) => {
      const timer = setTimeout(resolve, SHUTDOWN_LOCK_TIMEOUT_MS);
      timer.unref?.();
    });
    await Promise.race([lockDrained, lockTimeout]);
    await closeDatabase(sql);
    process.exit(0);
  };

  process.on("SIGINT", (signal) => {
    void shutdown(signal);
  });
  process.on("SIGTERM", (signal) => {
    void shutdown(signal);
  });

  // The loop (in worker-loop.ts) contains each iteration with bounded backoff so
  // a transient poll/DB error cannot crash the worker. Graceful shutdown is
  // preserved via the isShuttingDown predicate wired to SIGINT/SIGTERM above.
  await runWorkerLoop({
    processNextJob,
    jobStore,
    providerSettingsStore,
    createProvider,
    staleLockSeconds: STALE_LOCK_SECONDS,
    pollIntervalMs: POLL_INTERVAL_MS,
    isShuttingDown: () => shuttingDown,
    db: sql,
    communityStore,
    mediaStorage,
    manifests: mediaManifests
  });
}

run().catch((error) => {
  const info = sanitizeError(error);
  logger.error({ name: info.name, code: info.code, message: info.message }, "worker crashed");
  process.exit(1);
});
