import { Router } from "express";
import { z } from "zod";

import type { CommunityStore } from "../db/communityStore";

const listQuerySchema = z.object({
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(100).default(20),
  difficulty: z.enum(["beginner", "intermediate", "advanced"]).optional(),
  tag: z.string().optional(),
});

export function createCommunityRoutes(communityStore: CommunityStore): Router {
  const router = Router();

  router.get("/", async (req, res) => {
    const parsed = listQuerySchema.safeParse(req.query);
    if (!parsed.success) {
      const messages = parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join(", ");
      res.status(400).json({ error: { code: "BAD_REQUEST", message: messages } });
      return;
    }

    const { page, limit, difficulty, tag } = parsed.data;
    const { poses, total } = await communityStore.listPoses({
      status: "published",
      difficulty,
      tag,
      page,
      limit,
    });

    res.json({
      data: poses,
      pagination: { page, limit, total },
    });
  });

  router.get("/:id", async (req, res) => {
    const pose = await communityStore.getPoseById(req.params.id);

    if (!pose || pose.status !== "published") {
      res.status(404).json({ error: { code: "NOT_FOUND", message: "Pose not found" } });
      return;
    }

    await communityStore.incrementDownload(pose.id);
    const updated = await communityStore.getPoseById(pose.id);

    res.json({ data: updated });
  });

  return router;
}
