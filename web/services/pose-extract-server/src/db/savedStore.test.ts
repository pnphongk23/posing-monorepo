import { describe, expect, it } from "vitest";

import { PoseStore, type CreatePoseInput } from "./communityStore";
import { SavedStore } from "./savedStore";
import { setupTestDatabase } from "./testDb";

const ACCOUNT_A = "11111111-1111-4111-8111-111111111111";
const ACCOUNT_B = "22222222-2222-4222-8222-222222222222";

function poseInput(overrides: Partial<CreatePoseInput> = {}): CreatePoseInput {
  return {
    ownerAccountId: ACCOUNT_A,
    name: "Saved Pose",
    originalUrl: "data:image/jpeg;base64,b3JpZ2luYWw=",
    skeletonUrl: "data:image/png;base64,c2tlbGV0b24=",
    thumbnailUrl: "data:image/png;base64,dGh1bWJuYWls",
    tags: ["balance"],
    difficulty: "beginner",
    description: "Description",
    bodyParts: ["legs"],
    ...overrides
  };
}

async function publishedPose(poseStore: PoseStore) {
  const pose = await poseStore.createPose(poseInput());
  return (await poseStore.updatePose(pose.poseId, { status: "published" }))!;
}

describe("SavedStore", () => {
  it("saves only usable published poses and is idempotent", async () => {
    const sql = await setupTestDatabase();
    const poses = new PoseStore(sql);
    const saved = new SavedStore(sql);
    const published = await publishedPose(poses);
    const local = await poses.createPose(poseInput({ name: "Local" }));

    await expect(saved.save(ACCOUNT_A, local.poseId)).resolves.toBeNull();
    await expect(saved.save(ACCOUNT_A, published.poseId)).resolves.toMatchObject({ poseId: published.poseId });
    await expect(saved.save(ACCOUNT_A, published.poseId)).resolves.toMatchObject({ poseId: published.poseId });

    const rows = await sql`SELECT account_id, pose_id FROM saved_entries`;
    expect(rows).toEqual([{ account_id: ACCOUNT_A, pose_id: published.poseId }]);
  });

  it("rejects a published pose whose required media is not ready", async () => {
    const sql = await setupTestDatabase();
    const poses = new PoseStore(sql);
    const saved = new SavedStore(sql);
    const published = await publishedPose(poses);

    await sql`UPDATE media_assets SET readiness = ${"failed"} WHERE pose_id = ${published.poseId} AND role = ${"skeleton"}`;
    await expect(saved.save(ACCOUNT_A, published.poseId)).resolves.toBeNull();
    expect(await sql`SELECT pose_id FROM saved_entries WHERE pose_id = ${published.poseId}`).toHaveLength(0);
  });

  it("isolates accounts, paginates, and retains entries after pose removal", async () => {
    const sql = await setupTestDatabase();
    const poses = new PoseStore(sql);
    const saved = new SavedStore(sql);
    const first = await publishedPose(poses);
    const second = await publishedPose(poses);

    await saved.save(ACCOUNT_A, first.poseId);
    await saved.save(ACCOUNT_A, second.poseId);
    await saved.save(ACCOUNT_B, second.poseId);

    expect((await saved.list(ACCOUNT_A, 1, 1)).total).toBe(2);
    expect((await saved.list(ACCOUNT_A, 1, 1)).poses).toHaveLength(1);
    expect((await saved.list(ACCOUNT_B, 1, 20)).poses.map((pose) => pose.poseId)).toEqual([second.poseId]);

    await poses.updatePose(first.poseId, { status: "local" });
    expect((await sql`SELECT account_id, pose_id FROM saved_entries WHERE pose_id = ${first.poseId}`)).toHaveLength(1);
    expect((await saved.list(ACCOUNT_A, 1, 20)).poses.map((pose) => pose.poseId)).toEqual([second.poseId]);

    await poses.deletePose(second.poseId);
    expect((await sql`SELECT account_id, pose_id FROM saved_entries WHERE pose_id = ${second.poseId}`)).toHaveLength(2);
    expect((await saved.list(ACCOUNT_A, 1, 20)).poses).toHaveLength(0);
  });
});
