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
