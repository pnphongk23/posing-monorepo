import express from "express";
import request from "supertest";
import { describe, expect, it, vi } from "vitest";

import type { PoseRecord, PoseStore } from "../db/communityStore";
import { createGuideReadRoutes } from "./guideReadRoutes";

const ACCOUNT_A = { id: "account-aaa", displayName: "User A", createdAt: "2026-01-01T00:00:00.000Z" };

function accountMiddleware(account: typeof ACCOUNT_A | null = ACCOUNT_A) {
  return (req: express.Request, res: express.Response, next: express.NextFunction) => {
    if (account) {
      req.account = account;
      next();
    } else {
      res.status(401).json({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
    }
  };
}

describe("guideReadRoutes", () => {
  const poseA: PoseRecord = {
    poseId: "pose-111",
    ownerAccountId: "account-aaa",
    name: "Pose A",
    originalUrl: "https://r2.example.com/orig.jpg",
    skeletonUrl: "https://r2.example.com/skel.png",
    thumbnailUrl: "https://r2.example.com/thumb.jpg",
    tags: ["yoga"],
    difficulty: "beginner",
    description: "A beginner pose",
    bodyParts: ["arms"],
    status: "local",
    currentJobId: "job-111",
    createdAt: "2026-01-01T00:00:00.000Z",
    updatedAt: "2026-01-01T00:01:00.000Z",
    downloadCount: 0
  };

  it("returns 401 when unauthenticated", async () => {
    const communityStore = {} as PoseStore;
    const app = express().use("/api/guides", accountMiddleware(null), createGuideReadRoutes({ communityStore }));

    const res = await request(app).get("/api/guides/pose-111");
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe("UNAUTHORIZED");
  });

  it("returns pose when owned by account", async () => {
    const getPoseById = vi.fn().mockResolvedValue(poseA);
    const communityStore = { getPoseById } as unknown as PoseStore;
    const app = express().use("/api/guides", accountMiddleware(ACCOUNT_A), createGuideReadRoutes({ communityStore }));

    const res = await request(app).get("/api/guides/pose-111");
    expect(res.status).toBe(200);
    expect(res.body.data).toEqual({
      poseId: "pose-111",
      ownerAccountId: "account-aaa",
      name: "Pose A",
      description: "A beginner pose",
      tags: ["yoga"],
      difficulty: "beginner",
      bodyParts: ["arms"],
      status: "local",
      originalUrl: "https://r2.example.com/orig.jpg",
      skeletonUrl: "https://r2.example.com/skel.png",
      thumbnailUrl: "https://r2.example.com/thumb.jpg",
      currentJobId: "job-111",
      createdAt: "2026-01-01T00:00:00.000Z",
      updatedAt: "2026-01-01T00:01:00.000Z"
    });
  });

  it("returns 404 when pose belongs to another account", async () => {
    const getPoseById = vi.fn().mockResolvedValue(poseA);
    const communityStore = { getPoseById } as unknown as PoseStore;
    const accountB = { id: "account-bbb", displayName: "User B", createdAt: "2026-01-01T00:00:00.000Z" };
    const app = express().use("/api/guides", accountMiddleware(accountB), createGuideReadRoutes({ communityStore }));

    const res = await request(app).get("/api/guides/pose-111");
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe("NOT_FOUND");
  });

  it("returns 404 when pose does not exist", async () => {
    const getPoseById = vi.fn().mockResolvedValue(null);
    const communityStore = { getPoseById } as unknown as PoseStore;
    const app = express().use("/api/guides", accountMiddleware(ACCOUNT_A), createGuideReadRoutes({ communityStore }));

    const res = await request(app).get("/api/guides/non-existent");
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe("NOT_FOUND");
  });
});
