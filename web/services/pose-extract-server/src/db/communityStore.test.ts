import { describe, expect, it } from "vitest";

import { setupTestDatabase } from "./testDb";
import { CommunityStore, escapeLikePattern } from "./communityStore";

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

  describe("title search (q)", () => {
    it("escapeLikePattern escapes backslash, percent, and underscore", () => {
      expect(escapeLikePattern("100%")).toBe("100\\%");
      expect(escapeLikePattern("a_b")).toBe("a\\_b");
      expect(escapeLikePattern("path\\to")).toBe("path\\\\to");
      expect(escapeLikePattern("mix\\%_")).toBe("mix\\\\\\%\\_");
    });

    it("blank q returns all published poses (no name filter)", async () => {
      const store = await createTestStore();
      await store.createPose({
        name: "Alpha Pose",
        imagePath: "community/alpha.png",
        thumbnailPath: null,
        tags: [],
        difficulty: "beginner",
        description: null,
        bodyParts: [],
        status: "published"
      });
      await store.createPose({
        name: "Beta Pose",
        imagePath: "community/beta.png",
        thumbnailPath: null,
        tags: [],
        difficulty: "beginner",
        description: null,
        bodyParts: [],
        status: "published"
      });

      const { poses, total } = await store.listPoses({ status: "published", q: "", page: 1, limit: 20 });
      expect(poses).toHaveLength(2);
      expect(total).toBe(2);
    });

    it("matches name case-insensitively", async () => {
      const store = await createTestStore();
      await store.createPose({
        name: "Warrior II",
        imagePath: "community/warrior.png",
        thumbnailPath: null,
        tags: [],
        difficulty: "beginner",
        description: null,
        bodyParts: [],
        status: "published"
      });
      await store.createPose({
        name: "Tree Pose",
        imagePath: "community/tree.png",
        thumbnailPath: null,
        tags: [],
        difficulty: "beginner",
        description: null,
        bodyParts: [],
        status: "published"
      });

      const { poses, total } = await store.listPoses({ status: "published", q: "warrior", page: 1, limit: 20 });
      expect(poses).toHaveLength(1);
      expect(poses[0].name).toBe("Warrior II");
      expect(total).toBe(1);
    });

    it("excludes draft poses when searching", async () => {
      const store = await createTestStore();
      await store.createPose({
        name: "Secret Warrior",
        imagePath: "community/secret.png",
        thumbnailPath: null,
        tags: [],
        difficulty: "beginner",
        description: null,
        bodyParts: [],
        status: "draft"
      });
      await store.createPose({
        name: "Public Warrior",
        imagePath: "community/public.png",
        thumbnailPath: null,
        tags: [],
        difficulty: "beginner",
        description: null,
        bodyParts: [],
        status: "published"
      });

      const { poses, total } = await store.listPoses({ status: "published", q: "warrior", page: 1, limit: 20 });
      expect(poses).toHaveLength(1);
      expect(poses[0].name).toBe("Public Warrior");
      expect(total).toBe(1);
    });

    it("returns empty result when no name matches", async () => {
      const store = await createTestStore();
      await store.createPose({
        name: "Tree Pose",
        imagePath: "community/tree.png",
        thumbnailPath: null,
        tags: [],
        difficulty: "beginner",
        description: null,
        bodyParts: [],
        status: "published"
      });

      const { poses, total } = await store.listPoses({ status: "published", q: "nonexistent", page: 1, limit: 20 });
      expect(poses).toEqual([]);
      expect(total).toBe(0);
    });

    it("returns filtered total matching count query", async () => {
      const store = await createTestStore();
      for (let i = 0; i < 3; i++) {
        await store.createPose({
          name: `Yoga Flow ${i}`,
          imagePath: `community/flow${i}.png`,
          thumbnailPath: null,
          tags: [],
          difficulty: "beginner",
          description: null,
          bodyParts: [],
          status: "published"
        });
      }
      await store.createPose({
        name: "Stretch Session",
        imagePath: "community/stretch.png",
        thumbnailPath: null,
        tags: [],
        difficulty: "beginner",
        description: null,
        bodyParts: [],
        status: "published"
      });

      const { poses, total } = await store.listPoses({ status: "published", q: "yoga", page: 1, limit: 20 });
      expect(poses).toHaveLength(3);
      expect(total).toBe(3);
    });

    it("paginates 21+ search results without overlapping IDs between pages", async () => {
      const store = await createTestStore();
      for (let i = 0; i < 25; i++) {
        await store.createPose({
          name: `Search Match ${String(i).padStart(2, "0")}`,
          imagePath: `community/match${i}.png`,
          thumbnailPath: null,
          tags: [],
          difficulty: "beginner",
          description: null,
          bodyParts: [],
          status: "published"
        });
      }
      await store.createPose({
        name: "Unrelated Pose",
        imagePath: "community/other.png",
        thumbnailPath: null,
        tags: [],
        difficulty: "beginner",
        description: null,
        bodyParts: [],
        status: "published"
      });

      const page1 = await store.listPoses({ status: "published", q: "search", page: 1, limit: 20 });
      const page2 = await store.listPoses({ status: "published", q: "search", page: 2, limit: 20 });

      expect(page1.poses).toHaveLength(20);
      expect(page2.poses).toHaveLength(5);
      expect(page1.total).toBe(25);

      const page1Ids = new Set(page1.poses.map((p) => p.id));
      const page2Ids = page2.poses.map((p) => p.id);
      for (const id of page2Ids) {
        expect(page1Ids.has(id)).toBe(false);
      }
    });

    it("treats percent, underscore, and backslash as literal characters", async () => {
      const store = await createTestStore();
      await store.createPose({
        name: "100% Complete",
        imagePath: "community/percent.png",
        thumbnailPath: null,
        tags: [],
        difficulty: "beginner",
        description: null,
        bodyParts: [],
        status: "published"
      });
      await store.createPose({
        name: "Pose_a",
        imagePath: "community/underscore.png",
        thumbnailPath: null,
        tags: [],
        difficulty: "beginner",
        description: null,
        bodyParts: [],
        status: "published"
      });
      await store.createPose({
        name: "path\\file",
        imagePath: "community/backslash.png",
        thumbnailPath: null,
        tags: [],
        difficulty: "beginner",
        description: null,
        bodyParts: [],
        status: "published"
      });
      await store.createPose({
        name: "Wildcard Flood",
        imagePath: "community/flood.png",
        thumbnailPath: null,
        tags: [],
        difficulty: "beginner",
        description: null,
        bodyParts: [],
        status: "published"
      });

      const percent = await store.listPoses({ status: "published", q: "100%", page: 1, limit: 20 });
      expect(percent.poses).toHaveLength(1);
      expect(percent.poses[0].name).toBe("100% Complete");

      const underscore = await store.listPoses({ status: "published", q: "Pose_a", page: 1, limit: 20 });
      expect(underscore.poses).toHaveLength(1);
      expect(underscore.poses[0].name).toBe("Pose_a");

      const backslash = await store.listPoses({ status: "published", q: "path\\file", page: 1, limit: 20 });
      expect(backslash.poses).toHaveLength(1);
      expect(backslash.poses[0].name).toBe("path\\file");

      const lonePercent = await store.listPoses({ status: "published", q: "%", page: 1, limit: 20 });
      expect(lonePercent.poses).toHaveLength(1);
      expect(lonePercent.poses[0].name).toBe("100% Complete");
    });
  });
});
