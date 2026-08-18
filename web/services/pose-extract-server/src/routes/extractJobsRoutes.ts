import { Router } from "express";

import type { ExtractionJobStore } from "../db/extractionJobStore";
import { createExtractRateLimitMiddleware } from "../middleware/extractRateLimit";

interface CreateExtractJobsRoutesOptions {
  jobStore: ExtractionJobStore;
  rateLimitWindowMs?: number;
  rateLimitMaxRequests?: number;
}

export function createExtractJobsRoutes(options: CreateExtractJobsRoutesOptions): Router {
  const router = Router();
  const rateLimit = createExtractRateLimitMiddleware({
    windowMs: options.rateLimitWindowMs,
    maxRequests: options.rateLimitMaxRequests
  });

  router.get("/:jobId", rateLimit, async (req, res) => {
    const jobId = Array.isArray(req.params.jobId) ? req.params.jobId[0] : req.params.jobId;
    const job = await options.jobStore.getById(jobId);
    if (!job) {
      res.status(404).json({ error: { code: "JOB_NOT_FOUND", message: "Job not found" } });
      return;
    }

    res.json({
      data: {
        jobId: job.id,
        status: job.status,
        result:
          job.status === "succeeded"
            ? { imageBase64: job.resultImageBase64, mimeType: job.resultMimeType }
            : null,
        error: job.status === "failed" ? { code: job.errorCode, message: job.errorMessage } : null,
        updatedAt: job.updatedAt
      }
    });
  });

  return router;
}
