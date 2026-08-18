import express from "express";
import request from "supertest";
import { describe, expect, it } from "vitest";

import { setupTestDatabase } from "../db/testDb";
import { CommunityStore } from "../db/communityStore";
import { createCommunityRoutes } from "./communityRoutes";

async function createTestApp() {
  const sql = await setupTestDatabase();
  const communityStore = new CommunityStore(sql);

  const app = express();
  app.use("/api/community/poses", createCommunityRoutes(communityStore));

  return { app, communityStore };
}

async function seedPose(
  store: CommunityStore,
  overrides: Partial<Parameters<CommunityStore["createPose"]>[0]> = {}
) {
  return store.createPose({
    name: "Test Pose",
    imagePath: "community/test.png",
    thumbnailPath: null,
    tags: ["standing"],
    difficulty: "beginner",
    description: "A test pose",
    bodyParts: ["legs"],
    status: "published",
    ...overrides
  });
}

describe("GET /api/community/poses", () => {
  it("returns empty list when no poses", async () => {
    const { app } = await createTestApp();

    const res = await request(app).get("/api/community/poses");

    expect(res.status).toBe(200);
    expect(res.body.data).toEqual([]);
    expect(res.body.pagination.total).toBe(0);
  });

  it("returns only published poses", async () => {
    const { app, communityStore } = await createTestApp();
    await seedPose(communityStore, { status: "published", name: "Published" });
    await seedPose(communityStore, { status: "draft", name: "Draft" });

    const res = await request(app).get("/api/community/poses");

    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.data[0].name).toBe("Published");
  });

  it("filters by difficulty query param", async () => {
    const { app, communityStore } = await createTestApp();
    await seedPose(communityStore, { difficulty: "beginner", name: "Easy" });
    await seedPose(communityStore, { difficulty: "advanced", name: "Hard" });

    const res = await request(app).get("/api/community/poses?difficulty=beginner");

    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.data[0].name).toBe("Easy");
  });

  it("filters by tag query param", async () => {
    const { app, communityStore } = await createTestApp();
    await seedPose(communityStore, { tags: ["balance"], name: "Balance" });
    await seedPose(communityStore, { tags: ["core"], name: "Core" });

    const res = await request(app).get("/api/community/poses?tag=balance");

    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.data[0].name).toBe("Balance");
  });

  it("paginates with page and limit params", async () => {
    const { app, communityStore } = await createTestApp();
    for (let i = 0; i < 5; i++) {
      await seedPose(communityStore, { name: `Pose ${i}` });
    }

    const res = await request(app).get("/api/community/poses?page=1&limit=3");

    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(3);
    expect(res.body.pagination.total).toBe(5);
    expect(res.body.pagination.page).toBe(1);
    expect(res.body.pagination.limit).toBe(3);
  });

  it("rejects invalid difficulty param", async () => {
    const { app } = await createTestApp();

    const res = await request(app).get("/api/community/poses?difficulty=extreme");

    expect(res.status).toBe(400);
  });

  describe("title search (q)", () => {
    it("blank q returns first page of published catalogue with limit 20", async () => {
      const { app, communityStore } = await createTestApp();
      await seedPose(communityStore, { status: "published", name: "Published A" });
      await seedPose(communityStore, { status: "draft", name: "Draft A" });

      const res = await request(app).get("/api/community/poses?q=");

      expect(res.status).toBe(200);
      expect(res.body.data).toHaveLength(1);
      expect(res.body.data[0].name).toBe("Published A");
      expect(res.body.pagination.limit).toBe(20);
      expect(res.body.pagination.page).toBe(1);
    });

    it("missing q behaves like blank q", async () => {
      const { app, communityStore } = await createTestApp();
      await seedPose(communityStore, { name: "Catalogue Pose" });

      const res = await request(app).get("/api/community/poses");

      expect(res.status).toBe(200);
      expect(res.body.data).toHaveLength(1);
      expect(res.body.pagination.limit).toBe(20);
    });

    it("searches by name case-insensitively", async () => {
      const { app, communityStore } = await createTestApp();
      await seedPose(communityStore, { name: "Warrior II" });
      await seedPose(communityStore, { name: "Tree Pose" });

      const res = await request(app).get("/api/community/poses?q=WARRIOR");

      expect(res.status).toBe(200);
      expect(res.body.data).toHaveLength(1);
      expect(res.body.data[0].name).toBe("Warrior II");
      expect(res.body.pagination.limit).toBe(20);
    });

    it("excludes draft poses from search results", async () => {
      const { app, communityStore } = await createTestApp();
      await seedPose(communityStore, { status: "draft", name: "Hidden Warrior" });
      await seedPose(communityStore, { status: "published", name: "Visible Warrior" });

      const res = await request(app).get("/api/community/poses?q=warrior");

      expect(res.status).toBe(200);
      expect(res.body.data).toHaveLength(1);
      expect(res.body.data[0].name).toBe("Visible Warrior");
    });

    it("returns empty data for no matches", async () => {
      const { app, communityStore } = await createTestApp();
      await seedPose(communityStore, { name: "Tree Pose" });

      const res = await request(app).get("/api/community/poses?q=zzz-no-match");

      expect(res.status).toBe(200);
      expect(res.body.data).toEqual([]);
      expect(res.body.pagination.total).toBe(0);
    });

    it("returns filtered total in pagination", async () => {
      const { app, communityStore } = await createTestApp();
      for (let i = 0; i < 3; i++) {
        await seedPose(communityStore, { name: `Yoga Flow ${i}` });
      }
      await seedPose(communityStore, { name: "Stretch" });

      const res = await request(app).get("/api/community/poses?q=yoga");

      expect(res.status).toBe(200);
      expect(res.body.data).toHaveLength(3);
      expect(res.body.pagination.total).toBe(3);
    });

    it("paginates 21+ search results with non-overlapping page-one and page-two IDs", async () => {
      const { app, communityStore } = await createTestApp();
      for (let i = 0; i < 25; i++) {
        await seedPose(communityStore, { name: `Search Item ${String(i).padStart(2, "0")}` });
      }

      const page1 = await request(app).get("/api/community/poses?q=search&page=1");
      const page2 = await request(app).get("/api/community/poses?q=search&page=2");

      expect(page1.status).toBe(200);
      expect(page2.status).toBe(200);
      expect(page1.body.data).toHaveLength(20);
      expect(page2.body.data).toHaveLength(5);
      expect(page1.body.pagination.total).toBe(25);
      expect(page1.body.pagination.limit).toBe(20);
      expect(page2.body.pagination.limit).toBe(20);

      const page1Ids = new Set(page1.body.data.map((p: { id: string }) => p.id));
      for (const pose of page2.body.data) {
        expect(page1Ids.has(pose.id)).toBe(false);
      }
    });

    it("forces limit 20 when q is provided even if client requests higher", async () => {
      const { app, communityStore } = await createTestApp();
      for (let i = 0; i < 25; i++) {
        await seedPose(communityStore, { name: `Match ${i}` });
      }

      const res = await request(app).get("/api/community/poses?q=match&limit=100");

      expect(res.status).toBe(200);
      expect(res.body.data).toHaveLength(20);
      expect(res.body.pagination.limit).toBe(20);
    });

    it("matches wildcard characters literally", async () => {
      const { app, communityStore } = await createTestApp();
      await seedPose(communityStore, { name: "100% Complete" });
      await seedPose(communityStore, { name: "Pose_a" });
      await seedPose(communityStore, { name: "path\\file" });
      await seedPose(communityStore, { name: "Normal Pose" });

      const percent = await request(app).get("/api/community/poses?q=100%25");
      expect(percent.body.data).toHaveLength(1);
      expect(percent.body.data[0].name).toBe("100% Complete");

      const underscore = await request(app).get("/api/community/poses?q=Pose_a");
      expect(underscore.body.data).toHaveLength(1);
      expect(underscore.body.data[0].name).toBe("Pose_a");

      const backslash = await request(app).get("/api/community/poses?q=path%5Cfile");
      expect(backslash.body.data).toHaveLength(1);
      expect(backslash.body.data[0].name).toBe("path\\file");
    });

    it("rejects invalid pagination values", async () => {
      const { app } = await createTestApp();

      const zeroPage = await request(app).get("/api/community/poses?page=0");
      expect(zeroPage.status).toBe(400);

      const negativePage = await request(app).get("/api/community/poses?q=test&page=-1");
      expect(negativePage.status).toBe(400);

      const zeroLimit = await request(app).get("/api/community/poses?limit=0");
      expect(zeroLimit.status).toBe(400);
    });
  });
});

describe("GET /api/community/poses/:id", () => {
  it("returns 404 for unknown id", async () => {
    const { app } = await createTestApp();

    const res = await request(app).get("/api/community/poses/nonexistent");

    expect(res.status).toBe(404);
  });

  it("returns pose and increments download count", async () => {
    const { app, communityStore } = await createTestApp();
    const pose = await seedPose(communityStore);

    const res1 = await request(app).get(`/api/community/poses/${pose.id}`);
    expect(res1.status).toBe(200);
    expect(res1.body.data.id).toBe(pose.id);
    expect(res1.body.data.downloadCount).toBe(1);

    const res2 = await request(app).get(`/api/community/poses/${pose.id}`);
    expect(res2.body.data.downloadCount).toBe(2);
  });

  it("returns 404 for draft poses", async () => {
    const { app, communityStore } = await createTestApp();
    const draft = await seedPose(communityStore, { status: "draft" });

    const res = await request(app).get(`/api/community/poses/${draft.id}`);

    expect(res.status).toBe(404);
  });
});
