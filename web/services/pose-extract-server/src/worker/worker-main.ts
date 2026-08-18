import "dotenv/config";

import { getEnv } from "../config/env";
import { applySchema, closeDatabase, createDatabase } from "../db/connection";
import { ExtractionJobStore } from "../db/extractionJobStore";
import { ProviderSettingsStore } from "../db/providerSettingsStore";
import { GeminiService } from "../services/geminiService";
import { KeyPoolManager } from "../services/keyPoolManager";
import { KeyStore } from "../services/keyStore";
import { createPoseExtractorProvider } from "../services/poseExtractorProvider";
import { logger } from "../utils/logger";
import { processNextJob } from "./job-processor";

const POLL_INTERVAL_MS = Number(process.env.WORKER_POLL_INTERVAL_MS ?? "1000");
const STALE_LOCK_SECONDS = Number(process.env.WORKER_STALE_LOCK_SECONDS ?? "120");

async function run(): Promise<void> {
  const env = getEnv();
  const sql = createDatabase(env.DATABASE_URL);
  await applySchema(sql);
  const jobStore = new ExtractionJobStore(sql);
  const providerSettingsStore = new ProviderSettingsStore(sql);
  const keyStore = new KeyStore(sql);
  const keyPoolManager = new KeyPoolManager(keyStore);
  const geminiService = new GeminiService();

  const createProvider = (providerId: Parameters<typeof createPoseExtractorProvider>[0]["providerId"]) =>
    createPoseExtractorProvider({
      providerId,
      geminiService,
      keyPoolManager
    });

  logger.info(
    {
      pollIntervalMs: POLL_INTERVAL_MS,
      staleLockSeconds: STALE_LOCK_SECONDS,
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
    await closeDatabase(sql);
    process.exit(0);
  };

  process.on("SIGINT", (signal) => {
    void shutdown(signal);
  });
  process.on("SIGTERM", (signal) => {
    void shutdown(signal);
  });

  while (!shuttingDown) {
    const processed = await processNextJob({
      jobStore,
      providerSettingsStore,
      createProvider,
      staleLockSeconds: STALE_LOCK_SECONDS
    });
    if (!processed) {
      await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
    }
  }
}

run().catch((error) => {
  logger.error({ err: error }, "worker crashed");
  process.exit(1);
});
