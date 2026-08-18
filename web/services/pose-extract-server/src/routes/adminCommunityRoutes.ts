import { Router } from "express";
import multer from "multer";
import { z } from "zod";

import type { CommunityStore } from "../db/communityStore";
import type { ExtractionJobStore } from "../db/extractionJobStore";
import { createAdminAuthMiddleware } from "../middleware/adminAuth";
import { buildPublicUrl } from "../services/r2Storage";
import type { UploadUrlPayload } from "../services/r2Storage";

const ALLOWED_MIME_TYPES = new Set(["image/png", "image/jpeg", "image/webp"]);
const MAX_IMAGE_SIZE_BYTES = 10 * 1024 * 1024;

const uploadUrlBodySchema = z.object({
  fileName: z.string().min(1),
  mimeType: z.string().min(1),
});

const metadataSchema = z.object({
  name: z.string().trim().min(1),
  tags: z.array(z.string()).optional().default([]),
  difficulty: z.enum(["beginner", "intermediate", "advanced"]).nullable().optional(),
  description: z.string().optional().nullable(),
  bodyParts: z.array(z.string()).min(1),
  status: z.enum(["draft", "published"]).default("draft"),
});

export interface CreateAdminCommunityRoutesOptions {
  adminSecret: string;
  communityStore: CommunityStore;
  r2PublicUrl: string;
  createUploadUrl: (input: { fileName: string; mimeType: string }) => Promise<UploadUrlPayload>;
  objectExists: (fileKey: string) => Promise<boolean>;
  uploadObject: (input: { fileKey: string; body: Buffer; mimeType: string }) => Promise<void>;
  jobStore: ExtractionJobStore;
}

function createUploadMiddleware() {
  return multer({
    storage: multer.memoryStorage(),
    limits: { files: 1, fileSize: MAX_IMAGE_SIZE_BYTES },
    fileFilter(_req, file, callback) {
      if (!ALLOWED_MIME_TYPES.has(file.mimetype)) {
        callback(new Error("INVALID_IMAGE"));
        return;
      }
      callback(null, true);
    },
  });
}

function parseStringList(value: unknown): string[] {
  if (typeof value !== "string" || value.trim().length === 0) {
    return [];
  }

  try {
    const parsed = JSON.parse(value) as unknown;
    if (Array.isArray(parsed)) {
      return parsed.map((item) => String(item).trim()).filter(Boolean);
    }
  } catch {
    return value
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean);
  }

  return [];
}

export function createAdminCommunityRoutes(options: CreateAdminCommunityRoutesOptions): Router {
  const { adminSecret, communityStore, r2PublicUrl, createUploadUrl, objectExists, uploadObject, jobStore } = options;

  const auth = createAdminAuthMiddleware(adminSecret);
  const upload = createUploadMiddleware();
  const router = Router();

  router.get("/", auth, async (req, res) => {
    const page = Math.max(1, Number(req.query.page) || 1);
    const limit = Math.min(100, Math.max(1, Number(req.query.limit) || 50));
    const allStatuses: Array<"draft" | "published"> = ["draft", "published"];
    const listResults = await Promise.all(
      allStatuses.map((s) => communityStore.listPoses({ status: s, page: 1, limit: 200 }))
    );
    const results = listResults.flatMap((result) => result.poses);
    results.sort((a, b) => (a.uploadedAt < b.uploadedAt ? 1 : -1));
    const offset = (page - 1) * limit;
    const paginated = results.slice(offset, offset + limit);
    res.json({ data: paginated, pagination: { page, limit, total: results.length } });
  });

  router.post("/upload-url", auth, async (req, res) => {
    const parsed = uploadUrlBodySchema.safeParse(req.body);
    if (!parsed.success) {
      const messages = parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join(", ");
      res.status(400).json({ error: { code: "BAD_REQUEST", message: messages } });
      return;
    }

    const { fileName, mimeType } = parsed.data;

    if (!ALLOWED_MIME_TYPES.has(mimeType)) {
      res.status(400).json({
        error: {
          code: "BAD_REQUEST",
          message: `mimeType "${mimeType}" is not allowed. Allowed types: ${[...ALLOWED_MIME_TYPES].join(", ")}`,
        },
      });
      return;
    }

    const payload = await createUploadUrl({ fileName, mimeType });
    res.json({ data: payload });
  });

  router.post("/", auth, (req, res, next) => {
    upload.single("image")(req, res, (error) => {
      if (!error) {
        next();
        return;
      }
      if (error instanceof multer.MulterError && error.code === "LIMIT_FILE_SIZE") {
        res.status(400).json({ error: { code: "INVALID_IMAGE", message: "Image exceeds 10MB limit" } });
        return;
      }
      res.status(400).json({ error: { code: "INVALID_IMAGE", message: "Only PNG/JPEG/WEBP images are supported" } });
    });
  }, async (req, res) => {
    if (!req.file) {
      res.status(400).json({ error: { code: "INVALID_IMAGE", message: "Image field is required" } });
      return;
    }

    const parsed = metadataSchema.safeParse({
      name: req.body?.name,
      tags: parseStringList(req.body?.tags),
      difficulty: req.body?.difficulty || null,
      description: req.body?.description || null,
      bodyParts: parseStringList(req.body?.bodyParts),
      status: req.body?.status || "draft",
    });

    if (!parsed.success) {
      const messages = parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join(", ");
      res.status(400).json({ error: { code: "BAD_REQUEST", message: messages } });
      return;
    }

    try {
      const { name, tags, difficulty, description, bodyParts, status } = parsed.data;

      const fileKey = `community/${Date.now()}-${req.file.originalname.replace(/[^a-zA-Z0-9._-]/g, "-")}`;
      await uploadObject({ fileKey, body: req.file.buffer, mimeType: req.file.mimetype });

      const job = await jobStore.enqueue({
        sourceImageBase64: req.file.buffer.toString("base64"),
        sourceMimeType: req.file.mimetype,
      });

      const imagePath = buildPublicUrl(r2PublicUrl, fileKey);
      const pose = await communityStore.createPose({
        name,
        imagePath,
        thumbnailPath: null,
        tags,
        difficulty: difficulty ?? null,
        description: description ?? null,
        bodyParts,
        status,
      });

      res.status(202).json({ data: { pose, jobId: job.id, status: job.status } });
    } catch {
      res.status(500).json({ error: { code: "QUEUE_WRITE_FAILED", message: "Failed to enqueue extraction job" } });
    }
  });

  return router;
}
