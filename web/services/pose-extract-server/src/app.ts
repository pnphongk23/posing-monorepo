import type { NextFunction, Request, Response } from "express";
import express from "express";
import fs from "node:fs";

import type { ProviderSettingsStore } from "./db/providerSettingsStore";
import { createAdminRoutes } from "./routes/adminRoutes";
import { createAdminSettingsRoutes } from "./routes/adminSettingsRoutes";
import { createExtractJobsRoutes } from "./routes/extractJobsRoutes";
import { createExtractPoseRoutes } from "./routes/extractPoseRoutes";
import { createCommunityRoutes } from "./routes/communityRoutes";
import { createAdminCommunityRoutes } from "./routes/adminCommunityRoutes";
import { createJobStatusRoutes } from "./routes/jobStatusRoutes";
import { createAccountAuthMiddleware } from "./middleware/accountAuth";
import { createAccountOrAdminAuth } from "./middleware/accountOrAdminAuth";
import { createAuthRateLimitMiddleware } from "./middleware/authRateLimit";
import { PendingAuthStore } from "./services/pendingAuthStore";
import type { ExtractionJobStore } from "./db/extractionJobStore";
import { createUploadUrl, deleteObject } from "./services/r2Storage";
import { AppError } from "./services/errors";
import type { KeyPoolManager } from "./services/keyPoolManager";
import type { KeyStore } from "./services/keyStore";
import type { PoseStore } from "./db/communityStore";
import type { AccountStore } from "./db/accountStore";
import type { SavedStore } from "./db/savedStore";
import type { EntitlementStore } from "./db/entitlementStore";
import { createAccountAuthRoutes } from "./routes/accountAuthRoutes";
import { createAccountRoutes } from "./routes/accountRoutes";
import { authRateLimitFromEnv, revenueCatFromEnv, type RevenueCatConfig } from "./config/env";
import { createSavedRoutes } from "./routes/savedRoutes";
import { createEntitlementRoutes } from "./routes/entitlementRoutes";
import { createRevenueCatWebhookRoutes } from "./routes/revenueCatWebhookRoutes";
import { createRevenueCatClient } from "./services/revenueCatClient";
import { createMyExtractJobsRoutes } from "./routes/myExtractJobsRoutes";
import { createGuideReadRoutes } from "./routes/guideReadRoutes";
import { logger } from "./utils/logger";
import { sanitizeError } from "./utils/sanitizeError";

interface GeminiServiceLike {
  extractPoseImage(input: {
    apiKey: string;
    sourceImageBase64: string;
    sourceMimeType: string;
  }): Promise<{ imageBase64: string; mimeType: "image/png" | "image/jpeg" | "image/webp" }>;
}

type ExtractPoseImage = (input: {
  sourceImageBase64: string;
  sourceMimeType: string;
}) => Promise<{
  imageBase64: string;
  mimeType: "image/png" | "image/jpeg" | "image/webp";
  processingTimeMs: number;
  keyUsed?: string;
  quotaRemaining?: string;
}>;

interface CreateAppOptions {
  version: string;
  startedAtMs?: number;
  adminSecret?: string;
  keyStore?: KeyStore;
  keyPoolManager?: KeyPoolManager;
  geminiService?: GeminiServiceLike;
  adminRateLimitWindowMs?: number;
  adminRateLimitMaxRequests?: number;
  extractRateLimitWindowMs?: number;
  extractRateLimitMaxRequests?: number;
  communityStore?: PoseStore;
  communityUploadDir?: string;
  extractionJobStore?: ExtractionJobStore;
  providerSettingsStore?: ProviderSettingsStore;
  accountStore?: AccountStore;
  supabaseUrl?: string;
  supabaseAnonKey?: string;
  supabaseServiceRoleKey?: string;
  supabaseJwtKeyId?: string;
  r2PublicUrl?: string;
  backendPublicUrl?: string;
  pendingAuthStore?: PendingAuthStore;
  savedStore?: SavedStore;
  entitlementStore?: EntitlementStore;
  /** Absent means "read the feature-scoped env"; present (even empty) is authoritative. */
  revenueCat?: {
    secretApiKey?: string;
    entitlementId?: string;
    webhookAuth?: string;
    fetchImpl?: typeof fetch;
    now?: () => number;
    timeoutMs?: number;
  };
  authRateLimitWindowMs?: number;
  authRateLimitMaxPerEmail?: number;
  authRateLimitMaxPerIp?: number;
  fetchImpl?: typeof fetch;
  fetchJwks?: typeof fetch;
  deleteObject?: typeof deleteObject;
}

export function createCommunityExtractPoseImage(options: CreateAppOptions): ExtractPoseImage | null {
  if (!options.keyStore || !options.keyPoolManager || !options.geminiService) {
    return null;
  }

  return async ({ sourceImageBase64, sourceMimeType }) => {
    const processingStart = Date.now();
    const key = await options.keyPoolManager!.getNextActiveKey();
    const extracted = await options.geminiService!.extractPoseImage({
      apiKey: key.apiKey,
      sourceImageBase64,
      sourceMimeType,
    });

    await options.keyStore!.incrementRequestsToday(key.id);
    const processingTimeMs = Date.now() - processingStart;
    await options.keyStore!.logRequest({
      keyId: key.id,
      processingTimeMs,
      success: true,
      errorCode: null,
    });

    return {
      ...extracted,
      processingTimeMs,
      keyUsed: key.name,
    };
  };
}

  interface RevenueCatRuntimeConfig extends RevenueCatConfig {
  fetchImpl?: typeof fetch;
  now?: () => number;
  timeoutMs?: number;
}

/**
 * Feature-scoped config: explicit options win, otherwise the REVENUECAT_* env names decide
 * whether the entitlement routes serve live data or the 503 stub, and whether the webhook exists.
 */
function resolveRevenueCatConfig(overrides: RevenueCatRuntimeConfig | undefined): RevenueCatRuntimeConfig {
  if (overrides) {
    return overrides;
  }
  return revenueCatFromEnv(process.env);
}

export function createApp(options: CreateAppOptions): express.Express {
  const app = express();
  const startedAtMs = options.startedAtMs ?? Date.now();
  const communityExtractPoseImage = createCommunityExtractPoseImage(options);
  const envRateLimit = authRateLimitFromEnv();
  const revenueCatConfig = resolveRevenueCatConfig(options.revenueCat);
  const revenueCatClient =
    revenueCatConfig.secretApiKey && revenueCatConfig.entitlementId
      ? createRevenueCatClient({
          apiKey: revenueCatConfig.secretApiKey,
          entitlementId: revenueCatConfig.entitlementId,
          fetchImpl: revenueCatConfig.fetchImpl ?? options.fetchImpl,
          now: revenueCatConfig.now,
          timeoutMs: revenueCatConfig.timeoutMs
        })
      : undefined;

  // Railway sits behind at least one reverse proxy hop.
  app.set("trust proxy", 1);
  app.use(express.json());

  // CORS — allow browser clients (Next.js dev/prod)
  app.use((req, res, next) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
    if (req.method === "OPTIONS") {
      res.sendStatus(204);
      return;
    }
    next();
  });

    app.get("/api/health", (_req, res) => {
    const uptime = Math.max((Date.now() - startedAtMs) / 1000, 0);
    res.json({
      status: "ok",
      uptime,
      version: options.version
    });

    });

    const accountAuthMiddleware = (options.accountStore && options.supabaseUrl)
      ? createAccountAuthMiddleware({
          supabaseUrl: options.supabaseUrl,
          keyId: options.supabaseJwtKeyId ?? "61218C19-FDB0-498D-B773-CEBE34CBF90A",
          accountStore: options.accountStore,
          fetchJwks: options.fetchJwks
        })
      : undefined;

    if (options.accountStore && options.supabaseUrl && accountAuthMiddleware) {
      app.use("/api/auth", createAccountAuthRoutes({
        supabaseUrl: options.supabaseUrl,
        anonKey: options.supabaseAnonKey,
        backendPublicUrl: options.backendPublicUrl,
        pendingAuthStore: options.pendingAuthStore,
        accountStore: options.accountStore,
        keyId: options.supabaseJwtKeyId,
        authRateLimitWindowMs: options.authRateLimitWindowMs ?? envRateLimit.windowMs,
        authRateLimitMaxPerEmail: options.authRateLimitMaxPerEmail ?? envRateLimit.maxPerEmail,
        authRateLimitMaxPerIp: options.authRateLimitMaxPerIp ?? envRateLimit.maxPerIp,
        fetchImpl: options.fetchImpl,
        fetchJwks: options.fetchJwks
      }));
      app.delete("/api/account", accountAuthMiddleware, createAccountRoutes({
        supabaseUrl: options.supabaseUrl,
        serviceRoleKey: options.supabaseServiceRoleKey,
        r2PublicUrl: options.r2PublicUrl,
        accountStore: options.accountStore,
        fetchImpl: options.fetchImpl,
        deleteObject: options.deleteObject
      }));
      app.get("/api/account/me", accountAuthMiddleware, (req, res) => res.json({ data: req.account }));
      if (options.savedStore) {
        app.use("/api/me/saved", accountAuthMiddleware, createSavedRoutes(options.savedStore));
      }
      app.use(
        "/api/me/entitlement",
        accountAuthMiddleware,
        createEntitlementRoutes({
          store: options.entitlementStore,
          client: revenueCatClient,
          entitlementId: revenueCatConfig.entitlementId,
          now: revenueCatConfig.now
        })
      );
    }

  // The webhook only exists when it can authenticate callers and re-read the truth.
  if (options.accountStore && options.entitlementStore && revenueCatClient && revenueCatConfig.webhookAuth) {
    app.use(
      "/api/webhooks/revenuecat",
      createRevenueCatWebhookRoutes({
        accountStore: options.accountStore,
        entitlementStore: options.entitlementStore,
        client: revenueCatClient,
        webhookAuth: revenueCatConfig.webhookAuth
      })
    );
  }

  if (options.adminSecret && options.keyStore) {
    app.use(
      "/api/admin",
      createAdminRoutes({
        adminSecret: options.adminSecret,
        keyStore: options.keyStore,
        rateLimitWindowMs: options.adminRateLimitWindowMs,
        rateLimitMaxRequests: options.adminRateLimitMaxRequests
      })
    );
  }

  if (options.adminSecret && options.providerSettingsStore) {
    app.use(
      "/api/admin/settings",
      createAdminSettingsRoutes({
        adminSecret: options.adminSecret,
        providerSettingsStore: options.providerSettingsStore,
        rateLimitWindowMs: options.adminRateLimitWindowMs,
        rateLimitMaxRequests: options.adminRateLimitMaxRequests
      })
    );
  }

  const extractAuthMiddleware = createAccountOrAdminAuth({
    adminSecret: options.adminSecret,
    accountAuth: accountAuthMiddleware
  });

  if (options.extractionJobStore) {
    app.use(
      "/api/extract-pose",
      createExtractPoseRoutes({
        jobStore: options.extractionJobStore,
        authMiddleware: extractAuthMiddleware,
        rateLimitWindowMs: options.extractRateLimitWindowMs,
        rateLimitMaxRequests: options.extractRateLimitMaxRequests
      })
    );
    app.use(
      "/api/extract-jobs",
      createExtractJobsRoutes({
        jobStore: options.extractionJobStore,
        authMiddleware: extractAuthMiddleware,
        rateLimitWindowMs: options.extractRateLimitWindowMs,
        rateLimitMaxRequests: options.extractRateLimitMaxRequests
      })
    );
  }

  if (options.extractionJobStore && accountAuthMiddleware) {
    app.use(
      "/api/me/extract-jobs",
      createMyExtractJobsRoutes({
        jobStore: options.extractionJobStore,
        authMiddleware: accountAuthMiddleware
      })
    );
  }

  if (options.communityStore && accountAuthMiddleware) {
    app.use(
      "/api/guides",
      createGuideReadRoutes({
        communityStore: options.communityStore,
        authMiddleware: accountAuthMiddleware
      })
    );
  }

  // Community public routes
  if (options.communityStore) {
    app.use("/api/community/poses", createCommunityRoutes(options.communityStore));
  }

  // Admin community routes
  if (options.adminSecret && options.communityStore && options.extractionJobStore) {
    app.use(
      "/api/admin/community/poses",
      createAdminCommunityRoutes({
        adminSecret: options.adminSecret,
        communityStore: options.communityStore,
        createUploadUrl,
        publicUrlBase: process.env.R2_PUBLIC_URL,
        jobStore: options.extractionJobStore,
      })
    );
  }

  if (options.adminSecret && options.extractionJobStore) {
    app.use("/api/admin/jobs", createJobStatusRoutes({ adminSecret: options.adminSecret, jobStore: options.extractionJobStore }));
  }

  // Serve uploaded community images as static files (development/test only).
  // Production serves community images from Cloudflare R2, never from local disk.
  if (options.communityUploadDir && process.env.NODE_ENV !== "production") {
    const uploadDir = options.communityUploadDir;
    fs.mkdirSync(uploadDir, { recursive: true });
    app.use("/community", express.static(uploadDir));
  }

  app.use((_req, res) => {
    res.status(404).json({
      error: {
        code: "NOT_FOUND",
        message: "Route not found"
      }
    });
  });

  app.use((error: unknown, _req: Request, res: Response, next: NextFunction) => {
    if (res.headersSent) {
      next(error);
      return;
    }

    if (error instanceof AppError) {
      res.status(error.statusCode).json({
        error: {
          code: error.code,
          message: error.message
        }
      });
      return;
    }

    const info = sanitizeError(error);
    logger.error({ name: info.name, code: info.code, message: info.message }, "Unhandled application error");
    res.status(500).json({
      error: {
        code: "INTERNAL_SERVER_ERROR",
        message: "Internal server error"
      }
    });
  });

  return app;
}
