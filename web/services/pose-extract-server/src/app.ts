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
import type { ExtractionJobStore } from "./db/extractionJobStore";
import { createUploadUrl } from "./services/r2Storage";
import { AppError } from "./services/errors";
import type { KeyPoolManager } from "./services/keyPoolManager";
import type { KeyStore } from "./services/keyStore";
import type { PoseStore } from "./db/communityStore";
import { logger } from "./utils/logger";

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

export function createApp(options: CreateAppOptions): express.Express {
  const app = express();
  const startedAtMs = options.startedAtMs ?? Date.now();
  const communityExtractPoseImage = createCommunityExtractPoseImage(options);

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

  if (options.extractionJobStore) {
    app.use(
      "/api/extract-pose",
      createExtractPoseRoutes({
        jobStore: options.extractionJobStore,
        rateLimitWindowMs: options.extractRateLimitWindowMs,
        rateLimitMaxRequests: options.extractRateLimitMaxRequests
      })
    );
    app.use(
      "/api/extract-jobs",
      createExtractJobsRoutes({
        jobStore: options.extractionJobStore,
        rateLimitWindowMs: options.extractRateLimitWindowMs,
        rateLimitMaxRequests: options.extractRateLimitMaxRequests
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

    logger.error({ err: error }, "Unhandled application error");
    res.status(500).json({
      error: {
        code: "INTERNAL_SERVER_ERROR",
        message: "Internal server error"
      }
    });
  });

  return app;
}
