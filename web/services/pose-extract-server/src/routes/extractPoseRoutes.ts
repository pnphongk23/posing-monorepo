import { Router, type Request, type RequestHandler } from "express";
import multer from "multer";

import type { ExtractionJobStore, PoseDraft } from "../db/extractionJobStore";
import { createExtractRateLimitMiddleware } from "../middleware/extractRateLimit";
import { ImageTooLargeError, InvalidImageError, InvalidMetadataError, UnauthorizedError } from "../services/errors";

export interface CreateExtractPoseRoutesOptions {
  jobStore: ExtractionJobStore;
  authMiddleware: RequestHandler;
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

function parseTags(raw: unknown): string[] | null {
  if (Array.isArray(raw)) {
    const items: string[] = [];
    for (const item of raw) {
      if (typeof item !== "string") return null;
      const trimmed = item.trim();
      if (!trimmed) return null;
      items.push(trimmed);
    }
    return items;
  }

  if (typeof raw === "string") {
    const trimmed = raw.trim();
    if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
      try {
        const parsed = JSON.parse(trimmed);
        if (Array.isArray(parsed)) {
          const items: string[] = [];
          for (const item of parsed) {
            if (typeof item !== "string") return null;
            const itemTrimmed = item.trim();
            if (!itemTrimmed) return null;
            items.push(itemTrimmed);
          }
          return items;
        }
        return null;
      } catch {
        return null;
      }
    }

    if (trimmed.length > 0) {
      return [trimmed];
    }
    return null;
  }

  return null;
}

function validateTags(tags: string[]): boolean {
  if (tags.length < 1 || tags.length > 10) return false;
  for (const tag of tags) {
    if (tag.length < 1 || tag.length > 30) return false;
  }
  return true;
}

function extractMetadata(req: Request): { ownerAccountId?: string; poseDraft?: PoseDraft } {
  const rawName = req.body?.name;
  let name: string | null = null;
  if (rawName !== undefined && rawName !== null) {
    if (typeof rawName !== "string") {
      throw new InvalidMetadataError("Invalid name");
    }
    const trimmed = rawName.trim();
    if (trimmed.length < 1 || trimmed.length > 80) {
      throw new InvalidMetadataError("Name must be between 1 and 80 characters");
    }
    name = trimmed;
  }

  const rawTags = req.body?.tags;
  let tags: string[] | null = null;
  if (rawTags !== undefined && rawTags !== null) {
    const parsed = parseTags(rawTags);
    if (!parsed || !validateTags(parsed)) {
      throw new InvalidMetadataError("Tags must contain 1-10 items of 1-30 characters each");
    }
    tags = parsed;
  }

  const rawDescription = req.body?.description;
  let description: string | null = null;
  if (rawDescription !== undefined && rawDescription !== null) {
    if (typeof rawDescription !== "string") {
      throw new InvalidMetadataError("Invalid description");
    }
    const trimmed = rawDescription.trim();
    if (trimmed.length > 500) {
      throw new InvalidMetadataError("Description must not exceed 500 characters");
    }
    description = trimmed.length > 0 ? trimmed : null;
  }

  if (req.account) {
    if (!name) {
      throw new InvalidMetadataError("Name is required");
    }
    if (!tags) {
      throw new InvalidMetadataError("Tags are required");
    }
    return {
      ownerAccountId: req.account.id,
      poseDraft: {
        name,
        tags,
        description
      }
    };
  }

  if (req.isAdmin) {
    let ownerAccountId: string | undefined;
    const rawOwner = req.body?.ownerAccountId;
    if (typeof rawOwner === "string" && rawOwner.trim()) {
      ownerAccountId = rawOwner.trim();
    }

    if (name && tags) {
      return {
        ownerAccountId,
        poseDraft: {
          name,
          tags,
          description
        }
      };
    }

    if (name || tags) {
      throw new InvalidMetadataError("Both name and tags are required if creating a draft");
    }

    return {
      ownerAccountId,
      poseDraft: undefined
    };
  }

  throw new UnauthorizedError();
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
    options.authMiddleware,
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
        const { ownerAccountId, poseDraft } = extractMetadata(req);

        const job = await options.jobStore.enqueue({
          sourceImageBase64: req.file.buffer.toString("base64"),
          sourceMimeType: req.file.mimetype,
          ownerAccountId,
          poseDraft
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
      } catch (err) {
        next(err);
      }
    }
  );

  return router;
}
