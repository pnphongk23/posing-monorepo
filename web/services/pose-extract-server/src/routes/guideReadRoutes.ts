import { Router, type RequestHandler } from "express";

import type { PoseRecord, PoseStore } from "../db/communityStore";

export interface CreateGuideReadRoutesOptions {
  communityStore: PoseStore;
  authMiddleware?: RequestHandler;
}

function toPose(pose: PoseRecord) {
  return {
    poseId: pose.poseId,
    ownerAccountId: pose.ownerAccountId,
    name: pose.name,
    description: pose.description,
    tags: pose.tags,
    difficulty: pose.difficulty,
    bodyParts: pose.bodyParts,
    status: pose.status,
    originalUrl: pose.originalUrl,
    skeletonUrl: pose.skeletonUrl,
    thumbnailUrl: pose.thumbnailUrl,
    currentJobId: pose.currentJobId,
    createdAt: pose.createdAt,
    updatedAt: pose.updatedAt
  };
}

export function createGuideReadRoutes(options: CreateGuideReadRoutesOptions): Router {
  const router = Router();
  if (options.authMiddleware) {
    router.use(options.authMiddleware);
  }

  router.get("/:id", async (req, res, next) => {
    try {
      if (!req.account) {
        res.status(401).json({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
        return;
      }

      const id = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
      const pose = await options.communityStore.getPoseById(id);

      if (!pose || pose.ownerAccountId !== req.account.id) {
        res.status(404).json({ error: { code: "NOT_FOUND", message: "Pose not found" } });
        return;
      }

      res.json({ data: toPose(pose) });
    } catch (err) {
      next(err);
    }
  });

  return router;
}
