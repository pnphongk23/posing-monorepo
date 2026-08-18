import { Router } from "express";
import multer from "multer";

import type { ExtractionJobStore } from "../db/extractionJobStore";
import { createExtractRateLimitMiddleware } from "../middleware/extractRateLimit";
import { ImageTooLargeError, InvalidImageError } from "../services/errors";

interface CreateExtractPoseRoutesOptions {
  jobStore: ExtractionJobStore;
  rateLimitWindowMs?: number;
  rateLimitMaxRequests?: number;
}

const MAX_IMAGE_SIZE_BYTES = 10 * 1024 * 1024;
const ALLOWED_MIME_TYPES = new Set(["image/jpeg", "image/png"]);

function createUploadMiddleware() {
  return multer({
    storage: multer.memoryStorage(),
    limits: {
      files: 1,
      fileSize: MAX_IMAGE_SIZE_BYTES
    },
    fileFilter(_req, file, callback) {
      if (!ALLOWED_MIME_TYPES.has(file.mimetype)) {
        callback(new InvalidImageError("Only JPEG/PNG images are supported"));
        return;
      }
      callback(null, true);
    }
  });
}

function mapUploadError(error: unknown): Error {
  if (error instanceof multer.MulterError && error.code === "LIMIT_FILE_SIZE") {
    return new ImageTooLargeError("Image exceeds 10MB limit");
  }

  if (error instanceof InvalidImageError) {
    return error;
  }

  return new InvalidImageError();
}

export function createExtractPoseRoutes(options: CreateExtractPoseRoutesOptions): Router {
  const router = Router();
  const rateLimit = createExtractRateLimitMiddleware({
    windowMs: options.rateLimitWindowMs,
    maxRequests: options.rateLimitMaxRequests
  });
  const upload = createUploadMiddleware();

  router.post(
    "/",
    rateLimit,
    (req, res, next) => {
      upload.single("image")(req, res, (error) => {
        if (error) {
          next(mapUploadError(error));
          return;
        }
        next();
      });
    },
    async (req, res, next) => {
      if (!req.file) {
        next(new InvalidImageError("Image field is required"));
        return;
      }

      try {
        const job = await options.jobStore.enqueue({
          sourceImageBase64: req.file.buffer.toString("base64"),
          sourceMimeType: req.file.mimetype
        });

        res.status(202).json({
          success: true,
          data: {
            jobId: job.id,
            status: job.status
          },
          meta: {
            pollUrl: `/api/extract-jobs/${job.id}`
          }
        });
      } catch {
        next(new Error("QUEUE_WRITE_FAILED"));
      }
    }
  );

  return router;
}
