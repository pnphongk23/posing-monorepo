import { Router } from "express";
import { z } from "zod";

import type { PoseStore } from "../db/communityStore";
import type { ExtractionJobStore } from "../db/extractionJobStore";
import { createAdminAuthMiddleware } from "../middleware/adminAuth";
import type { UploadUrlPayload } from "../services/r2Storage";

const ALLOWED_MIME_TYPES = new Set(["image/png", "image/jpeg", "image/webp"]);

const uploadUrlBodySchema = z.object({
  fileName: z.string().min(1),
  mimeType: z.string().min(1)
});

const createPoseSchema = z.object({
  jobId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  name: z.string().trim().min(1),
  tags: z.array(z.string()).optional().default([]),
  difficulty: z.enum(["beginner", "intermediate", "advanced"]).nullable().optional(),
  description: z.string().optional().nullable(),
  bodyParts: z.array(z.string()).min(1)
});

/** All fields optional: undefined fields are left unchanged by PoseStore.updatePose. */
const updateMetadataSchema = z.object({
  name: z.string().trim().min(1).optional(),
  tags: z.array(z.string()).optional(),
  difficulty: z.enum(["beginner", "intermediate", "advanced"]).nullable().optional(),
  description: z.string().optional().nullable(),
  bodyParts: z.array(z.string()).min(1).optional(),
  status: z.enum(["local", "published"]).optional()
});

export interface CreateAdminCommunityRoutesOptions {
  adminSecret: string;
  communityStore: PoseStore;
  createUploadUrl: (input: { fileName: string; mimeType: string }) => Promise<UploadUrlPayload>;
  jobStore: ExtractionJobStore;
}

function asDataUrl(mimeType: string, imageBase64: string): string {
  return `data:${mimeType};base64,${imageBase64}`;
}

export function createAdminCommunityRoutes(options: CreateAdminCommunityRoutesOptions): Router {
  const { adminSecret, communityStore, createUploadUrl, jobStore } = options;
  const auth = createAdminAuthMiddleware(adminSecret);
  const router = Router();

  router.use(auth);

  router.get("/", async (req, res) => {
    const page = Math.max(1, Number(req.query.page) || 1);
    const limit = Math.min(100, Math.max(1, Number(req.query.limit) || 50));
    const listResults = await Promise.all(
      (["local", "published"] as const).map((status) =>
        communityStore.listPoses({ status, page: 1, limit: 200 })
      )
    );
    const results = listResults.flatMap((result) => result.poses);
    results.sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));
    const offset = (page - 1) * limit;
    res.json({
      data: results.slice(offset, offset + limit),
      pagination: { page, limit, total: results.length }
    });
  });

  router.get("/:id", async (req, res) => {
    const pose = await communityStore.getPoseById(req.params.id);
    if (!pose) {
      res.status(404).json({ error: { code: "NOT_FOUND", message: "Pose not found" } });
      return;
    }
    res.json({ data: pose });
  });

  router.patch("/:id", async (req, res) => {
    const parsed = updateMetadataSchema.safeParse(req.body);
    if (!parsed.success) {
      const messages = parsed.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`).join(", ");
      res.status(400).json({ error: { code: "BAD_REQUEST", message: messages } });
      return;
    }

    const updated = await communityStore.updatePose(req.params.id, parsed.data);
    if (!updated) {
      res.status(404).json({ error: { code: "NOT_FOUND", message: "Pose not found" } });
      return;
    }
    res.json({ data: updated });
  });

  router.delete("/:id", async (req, res) => {
    const deleted = await communityStore.deletePose(req.params.id);
    if (!deleted) {
      res.status(404).json({ error: { code: "NOT_FOUND", message: "Pose not found" } });
      return;
    }
    res.status(204).send();
  });

  router.post("/upload-url", async (req, res) => {
    const parsed = uploadUrlBodySchema.safeParse(req.body);
    if (!parsed.success) {
      const messages = parsed.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`).join(", ");
      res.status(400).json({ error: { code: "BAD_REQUEST", message: messages } });
      return;
    }
    if (!ALLOWED_MIME_TYPES.has(parsed.data.mimeType)) {
      res.status(400).json({
        error: {
          code: "BAD_REQUEST",
          message: `mimeType "${parsed.data.mimeType}" is not allowed. Allowed types: ${[...ALLOWED_MIME_TYPES].join(", ")}`
        }
      });
      return;
    }
    res.json({ data: await createUploadUrl(parsed.data) });
  });

  /** Materializes a canonical local Pose only after the referenced extraction succeeded. */
  router.post("/", async (req, res) => {
    const parsed = createPoseSchema.safeParse(req.body);
    if (!parsed.success) {
      const messages = parsed.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`).join(", ");
      res.status(400).json({ error: { code: "BAD_REQUEST", message: messages } });
      return;
    }

    const existing = await communityStore.getPoseByCurrentJobId(parsed.data.jobId);
    if (existing) {
      res.status(201).json({ data: { pose: existing } });
      return;
    }

    const job = await jobStore.getById(parsed.data.jobId);
    if (!job) {
      res.status(404).json({ error: { code: "JOB_NOT_FOUND", message: "Extraction job not found" } });
      return;
    }
    if (job.status !== "succeeded" || !job.resultImageBase64 || !job.resultMimeType) {
      res.status(400).json({ error: { code: "JOB_NOT_SUCCEEDED", message: "Extraction job is not succeeded" } });
      return;
    }

    const originalUrl = asDataUrl(job.sourceMimeType, job.sourceImageBase64);
    const skeletonUrl = asDataUrl(job.resultMimeType, job.resultImageBase64);
    const pose = await communityStore.createPose({
      ownerAccountId: parsed.data.ownerAccountId,
      name: parsed.data.name,
      originalUrl,
      skeletonUrl,
      thumbnailUrl: skeletonUrl,
      tags: parsed.data.tags,
      difficulty: parsed.data.difficulty ?? null,
      description: parsed.data.description ?? null,
      bodyParts: parsed.data.bodyParts,
      currentJobId: job.id
    });

    res.status(201).json({ data: { pose } });
  });

  return router;
}
