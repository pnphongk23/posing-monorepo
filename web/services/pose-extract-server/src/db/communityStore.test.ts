import { describe, expect, it } from "vitest";

import { setupTestDatabase } from "./testDb";
import { CommunityStore } from "./communityStore";

async function createTestStore(): Promise<CommunityStore> {
  const sql = await setupTestDatabase();
  return new CommunityStore(sql);
}

describe("CommunityStore", () => {
  it("creates and retrieves a pose by id", async () => {
    const store = await createTestStore();

    const created = await store.createPose({
      name: "Warrior II",
      imagePath: "community/warrior2.png",
      thumbnailPath: "community/warrior2_thumb.png",
      tags: ["standing", "balance"],
      difficulty: "intermediate",
      description: "Classic yoga pose",
      bodyParts: ["legs", "arms"],
      status: "draft"
    });

    expect(created.id).toBeTruthy();
    expect(created.name).toBe("Warrior II");
    expect(created.tags).toEqual(["standing", "balance"]);
    expect(created.bodyParts).toEqual(["legs", "arms"]);
    expect(created.downloadCount).toBe(0);
    expect(created.status).toBe("draft");

    const fetched = await store.getPoseById(created.id);
    expect(fetched).toEqual(created);
  });

  it("returns null for unknown id", async () => {
    const store = await createTestStore();
    expect(await store.getPoseById("nonexistent")).toBeNull();
  });

  it("lists only published poses by default", async () => {
    const store = await createTestStore();

    await store.createPose({
      name: "Draft Pose",
      imagePath: "community/draft.png",
      thumbnailPath: null,
      tags: [],
      difficulty: "beginner",
      description: null,
      bodyParts: [],
      status: "draft"
    });

    const published = await store.createPose({
      name: "Published Pose",
      imagePath: "community/pub.png",
      thumbnailPath: null,
      tags: ["standing"],
      difficulty: "beginner",
      description: null,
      bodyParts: ["legs"],
      status: "published"
    });

    const { poses, total } = await store.listPoses({ status: "published", page: 1, limit: 10 });
    expect(poses).toHaveLength(1);
    expect(poses[0].id).toBe(published.id);
    expect(total).toBe(1);
  });

  it("filters by difficulty", async () => {
    const store = await createTestStore();

    await store.createPose({
      name: "Easy Pose",
      imagePath: "community/easy.png",
      thumbnailPath: null,
      tags: [],
      difficulty: "beginner",
      description: null,
      bodyParts: [],
      status: "published"
    });

    await store.createPose({
      name: "Hard Pose",
      imagePath: "community/hard.png",
      thumbnailPath: null,
      tags: [],
      difficulty: "advanced",
      description: null,
      bodyParts: [],
      status: "published"
    });

    const { poses, total } = await store.listPoses({ status: "published", difficulty: "beginner", page: 1, limit: 10 });
    expect(poses).toHaveLength(1);
    expect(poses[0].name).toBe("Easy Pose");
    expect(total).toBe(1);
  });

  it("filters by tag", async () => {
    const store = await createTestStore();

    await store.createPose({
      name: "Balance Pose",
      imagePath: "community/balance.png",
      thumbnailPath: null,
      tags: ["balance", "standing"],
      difficulty: "beginner",
      description: null,
      bodyParts: [],
      status: "published"
    });

    await store.createPose({
      name: "Core Pose",
      imagePath: "community/core.png",
      thumbnailPath: null,
      tags: ["core"],
      difficulty: "beginner",
      description: null,
      bodyParts: [],
      status: "published"
    });

    const { poses } = await store.listPoses({ status: "published", tag: "balance", page: 1, limit: 10 });
    expect(poses).toHaveLength(1);
    expect(poses[0].name).toBe("Balance Pose");
  });

  it("paginates results", async () => {
    const store = await createTestStore();

    for (let i = 0; i < 5; i++) {
      await store.createPose({
        name: `Pose ${i}`,
        imagePath: `community/pose${i}.png`,
        thumbnailPath: null,
        tags: [],
        difficulty: "beginner",
        description: null,
        bodyParts: [],
        status: "published"
      });
    }

    const page1 = await store.listPoses({ status: "published", page: 1, limit: 3 });
    const page2 = await store.listPoses({ status: "published", page: 2, limit: 3 });

    expect(page1.poses).toHaveLength(3);
    expect(page2.poses).toHaveLength(2);
    expect(page1.total).toBe(5);
  });

  it("increments download count", async () => {
    const store = await createTestStore();

    const pose = await store.createPose({
      name: "Popular Pose",
      imagePath: "community/popular.png",
      thumbnailPath: null,
      tags: [],
      difficulty: "beginner",
      description: null,
      bodyParts: [],
      status: "published"
    });

    await store.incrementDownload(pose.id);
    await store.incrementDownload(pose.id);

    const updated = await store.getPoseById(pose.id);
    expect(updated?.downloadCount).toBe(2);
  });
});
