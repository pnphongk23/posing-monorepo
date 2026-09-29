import { Router, type RequestHandler } from "express";

import type { ExtractionJob, ExtractionJobStore } from "../db/extractionJobStore";
import { createExtractRateLimitMiddleware } from "../middleware/extractRateLimit";

export interface CreateExtractJobsRoutesOptions {
  jobStore: ExtractionJobStore;
  authMiddleware: RequestHandler;
  rateLimitWindowMs?: number;
  rateLimitMaxRequests?: number;
}

export function createExtractJobsRoutes(options: CreateExtractJobsRoutesOptions): Router {
  const router = Router();
  const rateLimit = createExtractRateLimitMiddleware({
    windowMs: options.rateLimitWindowMs,
    maxRequests: options.rateLimitMaxRequests
  });

  router.get("/:jobId", options.authMiddleware, rateLimit, async (req, res, next) => {
    try {
      const jobId = Array.isArray(req.params.jobId) ? req.params.jobId[0] : req.params.jobId;
      let job: ExtractionJob | null = null;

      if (req.isAdmin) {
        job = await options.jobStore.getById(jobId);
      } else if (req.account) {
        job = await options.jobStore.getByIdForOwner(jobId, req.account.id);
      } else {
        res.status(401).json({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
        return;
      }

      if (!job) {
        res.status(404).json({ error: { code: "JOB_NOT_FOUND", message: "Job not found" } });
        return;
      }

      res.json({
        data: {
          jobId: job.id,
          status: job.status,
          poseId: job.poseId,
          result:
            job.status === "succeeded"
              ? { imageBase64: job.resultImageBase64, mimeType: job.resultMimeType }
              : null,
          error: job.status === "failed" ? { code: job.errorCode, message: job.errorMessage } : null,
          updatedAt: job.updatedAt
        }
      });
    } catch (err) {
      next(err);
    }
  });

  return router;
}
