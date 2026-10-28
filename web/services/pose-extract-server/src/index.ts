import "dotenv/config";
import { createApp } from "./app";
import { getEnv } from "./config/env";
import { applySchema, closeDatabase, createDatabase, type Sql } from "./db/connection";
import { PoseStore } from "./db/communityStore";
import { ExtractionJobStore } from "./db/extractionJobStore";
import { ProviderSettingsStore } from "./db/providerSettingsStore";
import { AccountStore, objectKeyFromLocator, sweepStaleAccountPurges } from "./db/accountStore";
import { SavedStore } from "./db/savedStore";
import { PendingAuthStore } from "./services/pendingAuthStore";
import { GeminiService } from "./services/geminiService";
import { KeyPoolManager } from "./services/keyPoolManager";
import { KeyStore } from "./services/keyStore";
import { deleteObject } from "./services/r2Storage";
import { logger } from "./utils/logger";
import { sanitizeError } from "./utils/sanitizeError";

const SHUTDOWN_TIMEOUT_MS = 10_000;
const PURGE_SWEEP_INTERVAL_MS = 10 * 60 * 1000;

async function main(): Promise<void> {
  const env = getEnv();
  const sql: Sql = createDatabase(env.DATABASE_URL);
  await applySchema(sql);

  const keyStore = new KeyStore(sql);
  const communityStore = new PoseStore(sql);
  const extractionJobStore = new ExtractionJobStore(sql);
  const providerSettingsStore = new ProviderSettingsStore(sql);
  const accountStore = new AccountStore(sql);
  const savedStore = new SavedStore(sql);
  const keyPoolManager = new KeyPoolManager(keyStore);
  const geminiService = new GeminiService();
  const appVersion = process.env.APP_VERSION ?? process.env.npm_package_version ?? "1.0.0";
  const app = createApp({
    version: appVersion,
    adminSecret: env.ADMIN_SECRET,
    keyStore,
    keyPoolManager,
    geminiService,
    extractRateLimitWindowMs: env.RATE_LIMIT_WINDOW_MS,
    extractRateLimitMaxRequests: env.RATE_LIMIT_MAX,
    communityStore,
    communityUploadDir: env.NODE_ENV === "production" ? undefined : env.COMMUNITY_UPLOAD_DIR,
    extractionJobStore,
    providerSettingsStore,
    accountStore,
    supabaseUrl: env.SUPABASE_URL,
    supabaseAnonKey: env.SUPABASE_ANON_KEY,
    supabaseServiceRoleKey: env.SUPABASE_SERVICE_ROLE_KEY,
    supabaseJwtKeyId: env.SUPABASE_JWT_KEY_ID,
    r2PublicUrl: env.R2_PUBLIC_URL,
    backendPublicUrl: env.BACKEND_PUBLIC_URL,
    pendingAuthStore: new PendingAuthStore(),
    savedStore
  });

  // Resumes deletions that were confirmed upstream but never finished, and retries
  // object keys that storage refused earlier.
  const purgeSweepTimer = setInterval(() => {
    void sweepStaleAccountPurges({
      accountStore,
      outbox: accountStore.objectDeletions,
      deleteObject,
      resolveObjectKey: (locator) => objectKeyFromLocator(locator, env.R2_PUBLIC_URL)
    }).catch((error) => {
      const info = sanitizeError(error);
      logger.error({ name: info.name, code: info.code, message: info.message }, "account purge sweep failed");
    });
  }, PURGE_SWEEP_INTERVAL_MS);
  purgeSweepTimer.unref();

  let shuttingDown = false;

  const server = app.listen(env.PORT, () => {
    logger.info({ port: env.PORT }, "pose-extract-server started");
  });

  const shutdown = (signal: NodeJS.Signals): void => {
    if (shuttingDown) {
      logger.warn({ signal }, "Shutdown already in progress");
      return;
    }
    shuttingDown = true;
    logger.info({ signal }, "Shutting down server");

    const forceExitTimer = setTimeout(() => {
      logger.error({ signal, timeoutMs: SHUTDOWN_TIMEOUT_MS }, "Force exiting after shutdown timeout");
      process.exit(1);
    }, SHUTDOWN_TIMEOUT_MS);
    forceExitTimer.unref();

    server.close(async () => {
      clearTimeout(forceExitTimer);
      try {
        await closeDatabase(sql);
        process.exit(0);
      } catch (error) {
        const info = sanitizeError(error);
        logger.error({ name: info.name, code: info.code, message: info.message }, "Failed to close database during shutdown");
        process.exit(1);
      }
    });
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

main().catch((error) => {
  const info = sanitizeError(error);
  logger.error({ name: info.name, code: info.code, message: info.message }, "server failed to start");
  process.exit(1);
});
