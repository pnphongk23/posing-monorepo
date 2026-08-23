import { Router } from "express";
import { z } from "zod";

import type { PoseStore } from "../db/communityStore";
import type { PoseRecord } from "../db/communityStore";

const SEARCH_PAGE_LIMIT = 20;

const listQuerySchema = z.object({
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(100).default(20),
  difficulty: z.enum(["beginner", "intermediate", "advanced"]).optional(),
  tag: z.string().optional(),
  q: z.string().optional(),
});

/** Public read projection. It deliberately excludes owner, original media, and job metadata. */
function toCommunityPose(pose: PoseRecord) {
  return {
    poseId: pose.poseId,
    name: pose.name,
    skeletonUrl: pose.skeletonUrl,
    thumbnailUrl: pose.thumbnailUrl,
    tags: pose.tags,
    difficulty: pose.difficulty,
    description: pose.description,
    bodyParts: pose.bodyParts,
    status: "published" as const,
    uploadedAt: pose.createdAt,
    downloadCount: pose.downloadCount
  };
}

export function createCommunityRoutes(communityStore: PoseStore): Router {
  const router = Router();

  router.get("/", async (req, res) => {
    const parsed = listQuerySchema.safeParse(req.query);
    if (!parsed.success) {
      const messages = parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join(", ");
      res.status(400).json({ error: { code: "BAD_REQUEST", message: messages } });
      return;
    }

    const { page, difficulty, tag } = parsed.data;
    const q = parsed.data.q?.trim() || undefined;
    const limit = q !== undefined ? SEARCH_PAGE_LIMIT : parsed.data.limit;
    const { poses, total } = await communityStore.listPoses({
      status: "published",
      difficulty,
      tag,
      q,
      page,
      limit,
    });

    res.json({
      data: poses.map(toCommunityPose),
      pagination: { page, limit, total },
    });
  });

  router.get("/:id", async (req, res) => {
    const pose = await communityStore.getPoseById(req.params.id);

    if (!pose || pose.status !== "published") {
      res.status(404).json({ error: { code: "NOT_FOUND", message: "Pose not found" } });
      return;
    }

    await communityStore.incrementDownload(pose.poseId);
    const updated = await communityStore.getPoseById(pose.poseId);

    res.json({ data: updated ? toCommunityPose(updated) : null });
  });

  return router;
}
