import request from "supertest";
import { describe, expect, it } from "vitest";

import { createApp } from "../app";
import { PoseStore, type CreatePoseInput } from "../db/communityStore";
import { setupTestDatabase } from "../db/testDb";

const OWNER_ID = "11111111-1111-4111-8111-111111111111";

async function createTestApp() {
  const sql = await setupTestDatabase();
  const poseStore = new PoseStore(sql);
  return { app: createApp({ version: "test", communityStore: poseStore }), poseStore };
}

async function seedPose(store: PoseStore, overrides: Partial<CreatePoseInput> = {}, publish = true) {
  const pose = await store.createPose({
    ownerAccountId: OWNER_ID,
    name: "Published Pose",
    originalUrl: "data:image/jpeg;base64,b3JpZ2luYWw=",
    skeletonUrl: "data:image/png;base64,c2tlbGV0b24=",
    thumbnailUrl: "data:image/png;base64,dGh1bWJuYWls",
    tags: ["balance"],
    difficulty: "beginner",
    description: "Description",
    bodyParts: ["legs"],
    ...overrides
  });
  if (!publish) return pose;
  return (await store.updatePose(pose.poseId, { status: "published" }))!;
}

describe("community Pose projection routes", () => {
  it("lists published projections and excludes local Poses", async () => {
    const { app, poseStore } = await createTestApp();
    const published = await seedPose(poseStore);
    await seedPose(poseStore, { name: "Local Pose" }, false);

    const response = await request(app).get("/api/community/poses").expect(200);

    expect(response.body.data).toHaveLength(1);
    expect(response.body.data[0]).toMatchObject({
      poseId: published.poseId,
      status: "published",
      skeletonUrl: published.skeletonUrl,
      // Card/hero image is the source photo; the extracted line art stays in skeletonUrl.
      thumbnailUrl: published.originalUrl
    });
    expect(response.body.data[0]).not.toHaveProperty("ownerAccountId");
    expect(response.body.data[0]).not.toHaveProperty("originalUrl");
    expect(response.body.data[0]).not.toHaveProperty("currentJobId");
  });

  it("supports title search and fixed search page size", async () => {
    const { app, poseStore } = await createTestApp();
    await seedPose(poseStore, { name: "Warrior Flow" });
    await seedPose(poseStore, { name: "Tree Pose" });

    const response = await request(app).get("/api/community/poses?q=warrior&limit=1").expect(200);

    expect(response.body.data).toHaveLength(1);
    expect(response.body.data[0].name).toBe("Warrior Flow");
    expect(response.body.pagination).toMatchObject({ page: 1, limit: 20, total: 1 });
  });

  it("returns a published detail projection and increments downloads", async () => {
    const { app, poseStore } = await createTestApp();
    const published = await seedPose(poseStore);

    const response = await request(app).get(`/api/community/poses/${published.poseId}`).expect(200);

    expect(response.body.data.poseId).toBe(published.poseId);
    expect(response.body.data.downloadCount).toBe(1);
    expect(response.body.data).not.toHaveProperty("ownerAccountId");
  });

  it("returns 404 for local and unknown Poses", async () => {
    const { app, poseStore } = await createTestApp();
    const local = await seedPose(poseStore, {}, false);

    await request(app).get(`/api/community/poses/${local.poseId}`).expect(404);
    await request(app).get("/api/community/poses/33333333-3333-4333-8333-333333333333").expect(404);
  });
});
