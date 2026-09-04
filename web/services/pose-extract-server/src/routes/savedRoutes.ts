import { Router } from "express";
import { z } from "zod";

import type { SavedStore } from "../db/savedStore";
import type { PoseRecord } from "../db/communityStore";

const listQuerySchema = z.object({
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(100).default(20)
});

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

export function createSavedRoutes(savedStore: SavedStore): Router {
  const router = Router();

  router.get("/", async (req, res) => {
    const parsed = listQuerySchema.safeParse(req.query);
    if (!parsed.success) {
      const messages = parsed.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`).join(", ");
      res.status(400).json({ error: { code: "BAD_REQUEST", message: messages } });
      return;
    }

    const { page, limit } = parsed.data;
    const result = await savedStore.list(req.account!.id, page, limit);
    res.json({ data: result.poses.map(toCommunityPose), pagination: { page, limit, total: result.total } });
  });

  router.put("/:poseId", async (req, res) => {
    const pose = await savedStore.save(req.account!.id, req.params.poseId);
    if (!pose) {
      res.status(404).json({ error: { code: "NOT_FOUND", message: "Pose not found" } });
      return;
    }
    res.status(200).json({ data: toCommunityPose(pose) });
  });

  router.delete("/:poseId", async (req, res) => {
    await savedStore.remove(req.account!.id, req.params.poseId);
    res.sendStatus(204);
  });

  return router;
}
