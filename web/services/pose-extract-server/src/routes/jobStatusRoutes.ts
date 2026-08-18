import { Router } from "express";

import type { ExtractionJobStore } from "../db/extractionJobStore";
import { createAdminAuthMiddleware } from "../middleware/adminAuth";

export function createJobStatusRoutes(input: { adminSecret: string; jobStore: ExtractionJobStore }): Router {
  const router = Router();
  const auth = createAdminAuthMiddleware(input.adminSecret);

  router.get("/:jobId", auth, async (req, res) => {
    const jobId = Array.isArray(req.params.jobId) ? req.params.jobId[0] : req.params.jobId;
    const job = await input.jobStore.getById(jobId);
    if (!job) {
      res.status(404).json({ error: { code: "JOB_NOT_FOUND", message: "Job not found" } });
      return;
    }

    res.json({
      data: {
        jobId: job.id,
        status: job.status,
        attempts: job.attempts,
        maxAttempts: job.maxAttempts,
        result: job.status === "succeeded" ? { imageBase64: job.resultImageBase64, mimeType: job.resultMimeType } : null,
        error: job.status === "failed" ? { code: job.errorCode, message: job.errorMessage } : null,
        updatedAt: job.updatedAt
      }
    });
  });

  return router;
}
