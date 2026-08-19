import express from "express";
import request from "supertest";
import { describe, expect, it, vi } from "vitest";

import { setupTestDatabase } from "../db/testDb";
import { CommunityStore } from "../db/communityStore";
import { ExtractionJobStore } from "../db/extractionJobStore";
import { createAdminCommunityRoutes } from "./adminCommunityRoutes";

const PNG_PIXEL_BASE64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7Z0xkAAAAASUVORK5CYII=";
const PNG_PIXEL_BUFFER = Buffer.from(PNG_PIXEL_BASE64, "base64");

const ADMIN_SECRET = "test-admin-secret";
const R2_PUBLIC_URL = "https://cdn.example.com";

async function createTestApp(overrides?: {
  createUploadUrl?: (input: { fileName: string; mimeType: string }) => Promise<{
    uploadUrl: string;
    fileKey: string;
    fields: Record<string, string>;
  }>;
  objectExists?: (fileKey: string) => Promise<boolean>;
  uploadObject?: (input: { fileKey: string; body: Buffer; mimeType: string }) => Promise<void>;
  enqueue?: ExtractionJobStore["enqueue"];
}) {
  const sql = await setupTestDatabase();
  const communityStore = new CommunityStore(sql);
  const jobStore = new ExtractionJobStore(sql);

  const createUploadUrl =
    overrides?.createUploadUrl ??
    (async ({ fileName, mimeType }) => ({
      uploadUrl: "https://r2.example.com/upload",
      fileKey: `community/generated-${fileName}`,
      fields: { "Content-Type": mimeType, key: `community/generated-${fileName}` }
    }));

  const objectExists = overrides?.objectExists ?? (async () => true);
  const uploadObject = overrides?.uploadObject ?? (async () => undefined);

  if (overrides?.enqueue) {
    jobStore.enqueue = overrides.enqueue;
  }

  const app = express();
  app.use(express.json());
  app.use(
    "/api/admin/community/poses",
    createAdminCommunityRoutes({
      adminSecret: ADMIN_SECRET,
      communityStore,
      r2PublicUrl: R2_PUBLIC_URL,
      createUploadUrl,
      objectExists,
      uploadObject,
      jobStore
    })
  );

  return { app, communityStore };
}

describe("POST /api/admin/community/poses/upload-url", () => {
  it("rejects request without auth", async () => {
    const { app } = await createTestApp();

    const res = await request(app)
      .post("/api/admin/community/poses/upload-url")
      .send({ fileName: "pose.png", mimeType: "image/png" });

    expect(res.status).toBe(401);
  });

  it("returns upload payload", async () => {
    const createUploadUrl = vi.fn(async ({ fileName, mimeType }) => ({
      uploadUrl: "https://r2.example.com/upload",
      fileKey: `community/${fileName}`,
      fields: { "Content-Type": mimeType }
    }));

    const { app } = await createTestApp({ createUploadUrl });

    const res = await request(app)
      .post("/api/admin/community/poses/upload-url")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send({ fileName: "pose.png", mimeType: "image/png" });

    expect(res.status).toBe(200);
    expect(res.body.data).toEqual({
      uploadUrl: "https://r2.example.com/upload",
      fileKey: "community/pose.png",
      fields: { "Content-Type": "image/png" }
    });
    expect(createUploadUrl).toHaveBeenCalledWith({ fileName: "pose.png", mimeType: "image/png" });
  });

  it("returns 400 for invalid mimeType", async () => {
    const { app } = await createTestApp();

    const res = await request(app)
      .post("/api/admin/community/poses/upload-url")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send({ fileName: "pose.txt", mimeType: "text/plain" });

    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe("BAD_REQUEST");
  });
});

describe("POST /api/admin/community/poses", () => {
  it("rejects request without auth", async () => {
    const { app } = await createTestApp();

    const res = await request(app)
      .post("/api/admin/community/poses")
      .field("name", "Test Pose")
      .field("bodyParts", JSON.stringify(["legs"]))
      .attach("image", PNG_PIXEL_BUFFER, { filename: "test.png", contentType: "image/png" });

    expect(res.status).toBe(401);
  });

  it("creates pose and enqueues job with multipart payload", async () => {
    const uploadObject = vi.fn(async () => undefined);
    const { app } = await createTestApp({ uploadObject });

    const res = await request(app)
      .post("/api/admin/community/poses")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .field("name", "Warrior II")
      .field("tags", JSON.stringify(["standing", "balance"]))
      .field("difficulty", "intermediate")
      .field("description", "Classic yoga pose")
      .field("bodyParts", JSON.stringify(["legs", "arms"]))
      .field("status", "draft")
      .attach("image", PNG_PIXEL_BUFFER, { filename: "warrior2.png", contentType: "image/png" });

    expect(res.status).toBe(202);
    expect(res.body.data.pose.name).toBe("Warrior II");
    expect(res.body.data.pose.imagePath).toContain("https://cdn.example.com/community/");
    expect(res.body.data.jobId).toBeTypeOf("string");
    expect(res.body.data.status).toBe("queued");

    expect(uploadObject).toHaveBeenCalledTimes(1);
    const uploadCall = uploadObject.mock.calls[0]?.[0];
    expect(uploadCall?.fileKey).toMatch(/^community\/\d+-warrior2\.png$/);
    expect(uploadCall?.mimeType).toBe("image/png");
    expect(Buffer.isBuffer(uploadCall?.body)).toBe(true);
    expect((uploadCall?.body as Buffer).toString("base64")).toBe(PNG_PIXEL_BASE64);
  });

  it("creates pose without bodyParts or difficulty", async () => {
    const { app } = await createTestApp();

    const res = await request(app)
      .post("/api/admin/community/poses")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .field("name", "Minimal Pose")
      .attach("image", PNG_PIXEL_BUFFER, { filename: "minimal.png", contentType: "image/png" });

    expect(res.status).toBe(202);
    expect(res.body.data.pose.name).toBe("Minimal Pose");
    expect(res.body.data.pose.bodyParts).toEqual([]);
    expect(res.body.data.pose.difficulty).toBeNull();
  });

  it("creates pose with explicit empty bodyParts array", async () => {
    const { app } = await createTestApp();

    const res = await request(app)
      .post("/api/admin/community/poses")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .field("name", "Empty Parts Pose")
      .field("bodyParts", JSON.stringify([]))
      .attach("image", PNG_PIXEL_BUFFER, { filename: "empty.png", contentType: "image/png" });

    expect(res.status).toBe(202);
    expect(res.body.data.pose.bodyParts).toEqual([]);
  });

  it("returns 400 when image is missing", async () => {
    const { app } = await createTestApp();

    const res = await request(app)
      .post("/api/admin/community/poses")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .field("name", "No Image")
      .field("bodyParts", JSON.stringify(["legs"]))
      .field("status", "draft");

    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe("INVALID_IMAGE");
  });

  it("returns 400 for invalid mime type", async () => {
    const { app } = await createTestApp();

    const res = await request(app)
      .post("/api/admin/community/poses")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .field("name", "Bad Mime")
      .field("bodyParts", JSON.stringify(["legs"]))
      .field("status", "draft")
      .attach("image", Buffer.from("plain text", "utf8"), { filename: "bad.txt", contentType: "text/plain" });

    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe("INVALID_IMAGE");
  });

  it("does not create pose record when enqueue fails", async () => {
    const enqueue = vi.fn(() => {
      throw new Error("queue write failed");
    });
    const { app, communityStore } = await createTestApp({ enqueue });

    const before = (await communityStore.listPoses({ status: "draft", page: 1, limit: 100 })).poses.length;

    const res = await request(app)
      .post("/api/admin/community/poses")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .field("name", "Fail Pose")
      .field("bodyParts", JSON.stringify(["legs"]))
      .field("status", "draft")
      .attach("image", PNG_PIXEL_BUFFER, { filename: "fail.png", contentType: "image/png" });

    const after = (await communityStore.listPoses({ status: "draft", page: 1, limit: 100 })).poses.length;

    expect(res.status).toBe(500);
    expect(res.body.error.code).toBe("QUEUE_WRITE_FAILED");
    expect(after).toBe(before);
  });

  it("does not create pose record when R2 upload fails", async () => {
    const uploadObject = vi.fn(async () => {
      throw new Error("r2 upload failed");
    });
    const { app, communityStore } = await createTestApp({ uploadObject });

    const before = (await communityStore.listPoses({ status: "draft", page: 1, limit: 100 })).poses.length;

    const res = await request(app)
      .post("/api/admin/community/poses")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .field("name", "R2 Fail Pose")
      .field("bodyParts", JSON.stringify(["legs"]))
      .field("status", "draft")
      .attach("image", PNG_PIXEL_BUFFER, { filename: "r2fail.png", contentType: "image/png" });

    const after = (await communityStore.listPoses({ status: "draft", page: 1, limit: 100 })).poses.length;

    expect(uploadObject).toHaveBeenCalledTimes(1);
    expect(res.status).toBe(500);
    expect(res.body.error.code).toBe("QUEUE_WRITE_FAILED");
    expect(after).toBe(before);
  });
});

describe("GET /api/admin/community/poses/:id", () => {
  it("rejects request without auth", async () => {
    const { app } = await createTestApp();

    const res = await request(app).get("/api/admin/community/poses/some-id");

    expect(res.status).toBe(401);
  });

  it("returns pose by id", async () => {
    const { app, communityStore } = await createTestApp();
    const pose = await communityStore.createPose({
      name: "Retrievable Pose",
      imagePath: "community/retrieve.png",
      thumbnailPath: null,
      tags: ["standing"],
      difficulty: "beginner",
      description: "Can I find you?",
      bodyParts: ["legs"],
      status: "published"
    });

    const res = await request(app)
      .get(`/api/admin/community/poses/${pose.id}`)
      .set("Authorization", `Bearer ${ADMIN_SECRET}`);

    expect(res.status).toBe(200);
    expect(res.body.data).toMatchObject({
      id: pose.id,
      name: "Retrievable Pose",
      tags: ["standing"],
      difficulty: "beginner",
      description: "Can I find you?",
      bodyParts: ["legs"],
      status: "published"
    });
  });

  it("returns 404 for unknown id", async () => {
    const { app } = await createTestApp();

    const res = await request(app)
      .get("/api/admin/community/poses/nonexistent-id")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`);

    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe("NOT_FOUND");
  });
});

describe("PATCH /api/admin/community/poses/:id", () => {
  it("rejects request without auth", async () => {
    const { app } = await createTestApp();

    const res = await request(app)
      .patch("/api/admin/community/poses/some-id")
      .send({ name: "Hacked" });

    expect(res.status).toBe(401);
  });

  it("updates pose metadata", async () => {
    const { app, communityStore } = await createTestApp();
    const pose = await communityStore.createPose({
      name: "Before Edit",
      imagePath: "community/edit.png",
      thumbnailPath: null,
      tags: ["old"],
      difficulty: "beginner",
      description: "Old description",
      bodyParts: ["legs"],
      status: "draft"
    });

    const res = await request(app)
      .patch(`/api/admin/community/poses/${pose.id}`)
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send({
        name: "After Edit",
        tags: ["new", "improved"],
        difficulty: "advanced",
        description: "New description",
        bodyParts: ["legs", "arms"],
        status: "published"
      });

    expect(res.status).toBe(200);
    expect(res.body.data).toMatchObject({
      id: pose.id,
      name: "After Edit",
      tags: ["new", "improved"],
      difficulty: "advanced",
      description: "New description",
      bodyParts: ["legs", "arms"],
      status: "published"
    });
    expect(res.body.data.imagePath).toBe(pose.imagePath);

    const stored = await communityStore.getPoseById(pose.id);
    expect(stored?.name).toBe("After Edit");
  });

  it("supports partial updates leaving other fields unchanged", async () => {
    const { app, communityStore } = await createTestApp();
    const pose = await communityStore.createPose({
      name: "Partial Pose",
      imagePath: "community/partial.png",
      thumbnailPath: null,
      tags: ["a"],
      difficulty: "beginner",
      description: "Keep me",
      bodyParts: ["legs"],
      status: "draft"
    });

    const res = await request(app)
      .patch(`/api/admin/community/poses/${pose.id}`)
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send({ status: "published" });

    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe("published");
    expect(res.body.data.name).toBe("Partial Pose");
    expect(res.body.data.description).toBe("Keep me");
  });

  it("clears nullable fields with explicit null", async () => {
    const { app, communityStore } = await createTestApp();
    const pose = await communityStore.createPose({
      name: "Nullable Pose",
      imagePath: "community/nullable.png",
      thumbnailPath: null,
      tags: [],
      difficulty: "intermediate",
      description: "Will be cleared",
      bodyParts: ["legs"],
      status: "draft"
    });

    const res = await request(app)
      .patch(`/api/admin/community/poses/${pose.id}`)
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send({ difficulty: null, description: null });

    expect(res.status).toBe(200);
    expect(res.body.data.difficulty).toBeNull();
    expect(res.body.data.description).toBeNull();
  });

  it("returns 400 for invalid payload", async () => {
    const { app, communityStore } = await createTestApp();
    const pose = await communityStore.createPose({
      name: "Valid Pose",
      imagePath: "community/valid.png",
      thumbnailPath: null,
      tags: [],
      difficulty: null,
      description: null,
      bodyParts: ["legs"],
      status: "draft"
    });

    const res = await request(app)
      .patch(`/api/admin/community/poses/${pose.id}`)
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send({ name: "" });

    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe("BAD_REQUEST");
  });

  it("allows clearing bodyParts with an empty array", async () => {
    const { app, communityStore } = await createTestApp();
    const pose = await communityStore.createPose({
      name: "Parts Pose",
      imagePath: "community/parts.png",
      thumbnailPath: null,
      tags: [],
      difficulty: null,
      description: null,
      bodyParts: ["legs"],
      status: "draft"
    });

    const res = await request(app)
      .patch(`/api/admin/community/poses/${pose.id}`)
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send({ bodyParts: [] });

    expect(res.status).toBe(200);
    expect(res.body.data.bodyParts).toEqual([]);

    const stored = await communityStore.getPoseById(pose.id);
    expect(stored?.bodyParts).toEqual([]);
  });

  it("returns 404 for unknown id", async () => {
    const { app } = await createTestApp();

    const res = await request(app)
      .patch("/api/admin/community/poses/nonexistent-id")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send({ name: "Ghost" });

    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe("NOT_FOUND");
  });
});

describe("DELETE /api/admin/community/poses/:id", () => {
  it("rejects request without auth", async () => {
    const { app } = await createTestApp();

    const res = await request(app).delete("/api/admin/community/poses/some-id");

    expect(res.status).toBe(401);
  });

  it("deletes a pose", async () => {
    const { app, communityStore } = await createTestApp();
    const pose = await communityStore.createPose({
      name: "Delete Me",
      imagePath: "community/delete.png",
      thumbnailPath: null,
      tags: [],
      difficulty: null,
      description: null,
      bodyParts: ["legs"],
      status: "draft"
    });

    const res = await request(app)
      .delete(`/api/admin/community/poses/${pose.id}`)
      .set("Authorization", `Bearer ${ADMIN_SECRET}`);

    expect(res.status).toBe(204);
    expect(await communityStore.getPoseById(pose.id)).toBeNull();
  });

  it("returns 404 for unknown id", async () => {
    const { app } = await createTestApp();

    const res = await request(app)
      .delete("/api/admin/community/poses/nonexistent-id")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`);

    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe("NOT_FOUND");
  });
});
