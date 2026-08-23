import { describe, expect, it } from "vitest";

import { PoseStore, escapeLikePattern, type CreatePoseInput } from "./communityStore";
import { setupTestDatabase } from "./testDb";

const OWNER_ID = "11111111-1111-4111-8111-111111111111";

function poseInput(overrides: Partial<CreatePoseInput> = {}): CreatePoseInput {
  return {
    ownerAccountId: OWNER_ID,
    name: "Warrior II",
    originalUrl: "data:image/jpeg;base64,b3JpZ2luYWw=",
    skeletonUrl: "data:image/png;base64,c2tlbGV0b24=",
    thumbnailUrl: "data:image/png;base64,dGh1bWJuYWls",
    tags: ["standing"],
    difficulty: "beginner",
    description: "A stable pose",
    bodyParts: ["legs"],
    currentJobId: null,
    ...overrides
  };
}

describe("PoseStore", () => {
  it("creates a local Pose with a UUID and all three media roles", async () => {
    const sql = await setupTestDatabase();
    const store = new PoseStore(sql);

    const created = await store.createPose(poseInput());
    const media = await sql`SELECT role, locator FROM media_assets WHERE pose_id = ${created.poseId} ORDER BY role`;

    expect(created.poseId).toMatch(/^[0-9a-f-]{36}$/);
    expect(created.ownerAccountId).toBe(OWNER_ID);
    expect(created.status).toBe("local");
    expect(created.originalUrl).toContain("b3JpZ2luYWw=");
    expect(created.skeletonUrl).toContain("c2tlbGV0b24=");
    expect(created.thumbnailUrl).toContain("dGh1bWJuYWls");
    expect(media.map((row) => row.role)).toEqual(["original", "skeleton", "thumbnail"]);
  });

  it("retrieves by stable poseId and by the extraction job correlation key", async () => {
    const sql = await setupTestDatabase();
    const store = new PoseStore(sql);
    const jobId = "22222222-2222-4222-8222-222222222222";
    const created = await store.createPose(poseInput({ currentJobId: jobId }));

    expect((await store.getPoseById(created.poseId))?.poseId).toBe(created.poseId);
    expect((await store.getPoseByCurrentJobId(jobId))?.poseId).toBe(created.poseId);
    expect(await store.getPoseById("33333333-3333-4333-8333-333333333333")).toBeNull();
  });

  it("lists only the requested lifecycle status", async () => {
    const sql = await setupTestDatabase();
    const store = new PoseStore(sql);
    const local = await store.createPose(poseInput({ name: "Local" }));
    const published = await store.createPose(poseInput({ name: "Published" }));
    await store.updatePose(published.poseId, { status: "published" });

    const locals = await store.listPoses({ status: "local", page: 1, limit: 10 });
    const catalogue = await store.listPoses({ status: "published", page: 1, limit: 10 });

    expect(locals.poses.map((pose) => pose.poseId)).toEqual([local.poseId]);
    expect(catalogue.poses.map((pose) => pose.poseId)).toEqual([published.poseId]);
  });

  it("filters published poses and treats LIKE metacharacters literally", async () => {
    const sql = await setupTestDatabase();
    const store = new PoseStore(sql);
    const pose = await store.createPose(poseInput({ name: "100% Pose_a", tags: ["balance"], difficulty: "advanced" }));
    await store.updatePose(pose.poseId, { status: "published" });

    const result = await store.listPoses({
      status: "published",
      q: "100%",
      tag: "balance",
      difficulty: "advanced",
      page: 1,
      limit: 20
    });

    expect(result.total).toBe(1);
    expect(result.poses[0]?.poseId).toBe(pose.poseId);
    expect(escapeLikePattern("%_\\")).toBe("\\%\\_\\\\");
  });

  it("updates metadata without changing poseId or media locators", async () => {
    const sql = await setupTestDatabase();
    const store = new PoseStore(sql);
    const created = await store.createPose(poseInput());

    const updated = await store.updatePose(created.poseId, {
      name: "Updated",
      description: null,
      tags: ["updated"],
      bodyParts: ["arms"],
      status: "published"
    });

    expect(updated).toMatchObject({
      poseId: created.poseId,
      name: "Updated",
      description: null,
      status: "published",
      originalUrl: created.originalUrl,
      skeletonUrl: created.skeletonUrl,
      thumbnailUrl: created.thumbnailUrl
    });
  });

  it("increments downloads and deletes the Pose with cascading media", async () => {
    const sql = await setupTestDatabase();
    const store = new PoseStore(sql);
    const created = await store.createPose(poseInput());

    await store.incrementDownload(created.poseId);
    expect((await store.getPoseById(created.poseId))?.downloadCount).toBe(1);
    expect(await store.deletePose(created.poseId)).toBe(true);
    expect(await store.getPoseById(created.poseId)).toBeNull();
    const media = await sql`SELECT media_id FROM media_assets WHERE pose_id = ${created.poseId}`;
    expect(media).toHaveLength(0);
  });
});
