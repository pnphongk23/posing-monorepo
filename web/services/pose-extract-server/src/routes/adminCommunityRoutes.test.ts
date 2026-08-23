import express from "express";
import request from "supertest";
import { describe, expect, it, vi } from "vitest";

import { PoseStore } from "../db/communityStore";
import { ExtractionJobStore } from "../db/extractionJobStore";
import { setupTestDatabase } from "../db/testDb";
import { createAdminCommunityRoutes } from "./adminCommunityRoutes";

const ADMIN_SECRET = "test-admin-secret";
const OWNER_ID = "11111111-1111-4111-8111-111111111111";

async function createTestApp() {
  const sql = await setupTestDatabase();
  const poseStore = new PoseStore(sql);
  const jobStore = new ExtractionJobStore(sql);
  const createUploadUrl = vi.fn(async ({ fileName, mimeType }: { fileName: string; mimeType: string }) => ({
    uploadUrl: "https://r2.example.com/upload",
    fileKey: `community/${fileName}`,
    fields: { "Content-Type": mimeType }
  }));
  const uploaded: string[] = [];
  const uploadObject = vi.fn(async ({ fileKey }: { fileKey: string; body: Buffer; mimeType: string }) => {
    uploaded.push(fileKey);
  });
  const deleteObject = vi.fn(async (_fileKey: string) => undefined);
  const app = express();
  app.use(express.json());
  app.use(
    "/api/admin/community/poses",
    createAdminCommunityRoutes({
      adminSecret: ADMIN_SECRET,
      communityStore: poseStore,
      createUploadUrl,
      uploadObject,
      deleteObject,
      publicUrlBase: "https://cdn.example.com",
      jobStore
    })
  );
  return { app, poseStore, jobStore, createUploadUrl, uploadObject, deleteObject, uploaded };
}

async function succeededJob(jobStore: ExtractionJobStore) {
  const queued = await jobStore.enqueue({ sourceImageBase64: "b3JpZ2luYWw=", sourceMimeType: "image/jpeg" });
  const claimed = await jobStore.claimNext("test-lock", 60);
  expect(claimed?.id).toBe(queued.id);
  await jobStore.markSucceeded(queued.id, "test-lock", "c2tlbGV0b24=", "image/png");
  return queued.id;
}

function createBody(jobId: string) {
  return {
    jobId,
    ownerAccountId: OWNER_ID,
    name: "Warrior II",
    tags: ["standing"],
    difficulty: "beginner",
    description: "Description",
    bodyParts: ["legs"]
  };
}

describe("admin canonical Pose routes", () => {
  it("requires admin Bearer auth", async () => {
    const { app } = await createTestApp();
    await request(app).get("/api/admin/community/poses").expect(401);
  });

  it("creates a local Pose with 201 only after extraction succeeded", async () => {
    const { app, jobStore } = await createTestApp();
    const jobId = await succeededJob(jobStore);

    const response = await request(app)
      .post("/api/admin/community/poses")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send(createBody(jobId))
      .expect(201);

    expect(response.body.data.pose).toMatchObject({
      ownerAccountId: OWNER_ID,
      status: "local",
      currentJobId: jobId,
      originalUrl: expect.stringMatching(/^https:\/\/cdn\.example\.com\/community\/.+\/original\.jpeg$/),
      skeletonUrl: expect.stringMatching(/^https:\/\/cdn\.example\.com\/community\/.+\/skeleton\.png$/),
      thumbnailUrl: expect.stringMatching(/^https:\/\/cdn\.example\.com\/community\/.+\/thumbnail\.png$/)
    });
    expect(response.body.data.pose.poseId).toMatch(/^[0-9a-f-]{36}$/);
  });

  it("removes uploaded objects when one upload fails", async () => {
    const { app, jobStore, poseStore, uploadObject, deleteObject } = await createTestApp();
    const jobId = await succeededJob(jobStore);
    uploadObject.mockImplementationOnce(async () => undefined).mockRejectedValueOnce(new Error("R2 unavailable"));

    await request(app)
      .post("/api/admin/community/poses")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send(createBody(jobId))
      .expect(500);

    expect(deleteObject).toHaveBeenCalled();
    expect(await poseStore.getPoseByCurrentJobId(jobId)).toBeNull();
  });

  it("removes all uploaded objects when database materialization fails", async () => {
    const { app, jobStore, poseStore, deleteObject, uploaded } = await createTestApp();
    const jobId = await succeededJob(jobStore);
    vi.spyOn(poseStore, "createPose").mockRejectedValueOnce(new Error("database unavailable"));

    await request(app)
      .post("/api/admin/community/poses")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send(createBody(jobId))
      .expect(500);

    expect(uploaded).toHaveLength(3);
    expect(deleteObject).toHaveBeenCalledTimes(3);
    expect(await poseStore.getPoseByCurrentJobId(jobId)).toBeNull();
  });

  it("rejects a queued job and does not create a Pose", async () => {
    const { app, jobStore, poseStore } = await createTestApp();
    const queued = await jobStore.enqueue({ sourceImageBase64: "b3JpZ2luYWw=", sourceMimeType: "image/jpeg" });

    const response = await request(app)
      .post("/api/admin/community/poses")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send(createBody(queued.id))
      .expect(400);

    expect(response.body.error.code).toBe("JOB_NOT_SUCCEEDED");
    expect(await poseStore.getPoseByCurrentJobId(queued.id)).toBeNull();
  });

  it("requires an explicit ownerAccountId", async () => {
    const { app, jobStore } = await createTestApp();
    const jobId = await succeededJob(jobStore);
    const body = createBody(jobId);
    const { ownerAccountId: _ownerAccountId, ...withoutOwner } = body;

    const response = await request(app)
      .post("/api/admin/community/poses")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send(withoutOwner)
      .expect(400);

    expect(response.body.error.code).toBe("BAD_REQUEST");
  });

  it("uses the same poseId when publishing", async () => {
    const { app, jobStore } = await createTestApp();
    const jobId = await succeededJob(jobStore);
    const created = await request(app)
      .post("/api/admin/community/poses")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send(createBody(jobId))
      .expect(201);
    const poseId = created.body.data.pose.poseId;

    const updated = await request(app)
      .patch(`/api/admin/community/poses/${poseId}`)
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send({ status: "published" })
      .expect(200);

    expect(updated.body.data).toMatchObject({ poseId, status: "published" });
  });

  it("returns a presigned upload payload without creating a Pose", async () => {
    const { app, createUploadUrl } = await createTestApp();
    const response = await request(app)
      .post("/api/admin/community/poses/upload-url")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send({ fileName: "pose.png", mimeType: "image/png" })
      .expect(200);

    expect(response.body.data.fileKey).toBe("community/pose.png");
    expect(createUploadUrl).toHaveBeenCalledOnce();
  });
});
