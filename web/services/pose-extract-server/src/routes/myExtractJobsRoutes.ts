import { Router, type RequestHandler } from "express";

import type { ExtractionJobStore } from "../db/extractionJobStore";

export interface CreateMyExtractJobsRoutesOptions {
  jobStore: ExtractionJobStore;
  authMiddleware?: RequestHandler;
}

function isValidCursor(cursor: string): boolean {
  try {
    const raw = Buffer.from(cursor, "base64url").toString("utf8");
    const separatorIdx = raw.indexOf("|");
    if (separatorIdx === -1) return false;
    const createdAt = raw.slice(0, separatorIdx);
    const id = raw.slice(separatorIdx + 1);
    if (!createdAt || !id) return false;
    const d = new Date(createdAt);
    if (Number.isNaN(d.getTime())) return false;
    return true;
  } catch {
    return false;
  }
}

export function createMyExtractJobsRoutes(options: CreateMyExtractJobsRoutesOptions): Router {
  const router = Router();
  if (options.authMiddleware) {
    router.use(options.authMiddleware);
  }

  router.get("/", async (req, res, next) => {
    try {
      if (!req.account) {
        res.status(401).json({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
        return;
      }

      let state: "active" | "finished" | undefined;
      if (req.query.state !== undefined) {
        if (req.query.state === "active" || req.query.state === "finished") {
          state = req.query.state;
        } else {
          res.status(400).json({ error: { code: "BAD_REQUEST", message: "Invalid state filter" } });
          return;
        }
      }

      let limit = 20;
      if (req.query.limit !== undefined) {
        const rawLimit = Number(req.query.limit);
        if (!Number.isInteger(rawLimit) || rawLimit < 1 || rawLimit > 100) {
          res.status(400).json({ error: { code: "BAD_REQUEST", message: "Invalid limit" } });
          return;
        }
        limit = rawLimit;
      }

      let cursor: string | undefined;
      if (req.query.cursor !== undefined) {
        const rawCursor = String(req.query.cursor);
        if (!rawCursor || !isValidCursor(rawCursor)) {
          res.status(400).json({ error: { code: "BAD_REQUEST", message: "Invalid cursor" } });
          return;
        }
        cursor = rawCursor;
      }

      const result = await options.jobStore.listByOwner(req.account.id, {
        state,
        limit,
        cursor
      });

      res.json({
        success: true,
        data: result.jobs.map((job) => ({
          jobId: job.id,
          status: job.status,
          poseDraft: job.poseDraft,
          poseId: job.poseId,
          errorCode: job.errorCode,
          errorMessage: job.errorMessage,
          thumbnailUrl: job.thumbnailUrl,
          createdAt: job.createdAt,
          updatedAt: job.updatedAt
        })),
        meta: {
          nextCursor: result.nextCursor
        }
      });
    } catch (err) {
      next(err);
    }
  });

  router.post("/:jobId/retry", async (req, res, next) => {
    try {
      if (!req.account) {
        res.status(401).json({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
        return;
      }

      const jobId = Array.isArray(req.params.jobId) ? req.params.jobId[0] : req.params.jobId;
      const outcome = await options.jobStore.retryFailed(jobId, req.account.id);

      if (outcome === "requeued") {
        res.status(202).json({
          success: true,
          data: {
            jobId,
            status: "queued"
          },
          meta: {
            pollUrl: `/api/extract-jobs/${jobId}`
          }
        });
        return;
      }

      if (outcome === "not_found") {
        res.status(404).json({ error: { code: "JOB_NOT_FOUND", message: "Job not found" } });
        return;
      }

      res.status(409).json({ error: { code: "JOB_NOT_RETRYABLE", message: "Job is not in failed state" } });
    } catch (err) {
      next(err);
    }
  });

  router.delete("/:jobId", async (req, res, next) => {
    try {
      if (!req.account) {
        res.status(401).json({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
        return;
      }

      const jobId = Array.isArray(req.params.jobId) ? req.params.jobId[0] : req.params.jobId;
      const hidden = await options.jobStore.hide(jobId, req.account.id);

      if (!hidden) {
        res.status(404).json({ error: { code: "JOB_NOT_FOUND", message: "Job not found" } });
        return;
      }

      res.status(204).end();
    } catch (err) {
      next(err);
    }
  });

  return router;
}
