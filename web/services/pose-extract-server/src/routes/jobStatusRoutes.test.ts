import express from "express";
import request from "supertest";
import { describe, expect, it, vi } from "vitest";

import type { ExtractionJob, ExtractionJobStore } from "../db/extractionJobStore";
import { createJobStatusRoutes } from "./jobStatusRoutes";

const ADMIN_SECRET = "admin-secret";
const ACCOUNT_TOKEN =
  "eyJhbGciOiJFUzI1NiIsImtpZCI6InRlc3Qta2V5LWlkIn0.eyJzdWIiOiJhY2NvdW50LWFhYSIsImF1ZCI6ImF1dGhlbnRpY2F0ZWQifQ.c2lnbmF0dXJl";

function makeJob(overrides: Partial<ExtractionJob> & Pick<ExtractionJob, "id">): ExtractionJob {
  return {
    status: "processing",
    sourceImageBase64: null,
    sourceMimeType: "image/png",
    resultImageBase64: null,
    resultMimeType: null,
    errorCode: null,
    errorMessage: null,
    attempts: 2,
    maxAttempts: 3,
    lockedAt: null,
    lockToken: null,
    createdAt: "2026-01-01T00:00:00.000Z",
    updatedAt: "2026-01-01T00:01:00.000Z",
    ownerAccountId: "account-aaa",
    poseDraft: null,
    poseId: null,
    hiddenAt: null,
    ...overrides
  };
}

function createJobStore(job: ExtractionJob | null) {
  const getById = vi.fn(async () => job);
  return { store: { getById } as unknown as ExtractionJobStore, getById };
}

function buildApp(jobStore: ExtractionJobStore) {
  return express()
    .use(express.json())
    .use("/api/admin/jobs", createJobStatusRoutes({ adminSecret: ADMIN_SECRET, jobStore }));
}

describe("jobStatusRoutes", () => {
  it("returns 401 without a bearer token and never reads the store", async () => {
    const { store, getById } = createJobStore(makeJob({ id: "job-a" }));

    const res = await request(buildApp(store)).get("/api/admin/jobs/job-a");

    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
    expect(getById).not.toHaveBeenCalled();
  });

  it("returns 401 for a wrong admin bearer and never reads the store", async () => {
    const { store, getById } = createJobStore(makeJob({ id: "job-a" }));

    const res = await request(buildApp(store))
      .get("/api/admin/jobs/job-a")
      .set("Authorization", "Bearer wrong-secret");

    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe("UNAUTHORIZED");
    expect(getById).not.toHaveBeenCalled();
  });

  it("returns 401 for an account token that is not the admin secret", async () => {
    const { store, getById } = createJobStore(makeJob({ id: "job-a" }));

    const res = await request(buildApp(store))
      .get("/api/admin/jobs/job-a")
      .set("Authorization", `Bearer ${ACCOUNT_TOKEN}`);

    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe("UNAUTHORIZED");
    expect(getById).not.toHaveBeenCalled();
  });

  it("returns the full admin payload with attempts and maxAttempts", async () => {
    const job = makeJob({
      id: "job-a",
      status: "succeeded",
      attempts: 1,
      maxAttempts: 4,
      resultImageBase64: "cmVzdWx0",
      resultMimeType: "image/png"
    });
    const { store, getById } = createJobStore(job);

    const res = await request(buildApp(store))
      .get("/api/admin/jobs/job-a")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`);

    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      data: {
        jobId: "job-a",
        status: "succeeded",
        attempts: 1,
        maxAttempts: 4,
        result: { imageBase64: "cmVzdWx0", mimeType: "image/png" },
        error: null,
        updatedAt: job.updatedAt
      }
    });
    expect(getById).toHaveBeenCalledWith("job-a");
  });

  it("maps a failed job to error details", async () => {
    const job = makeJob({
      id: "job-failed",
      status: "failed",
      attempts: 3,
      errorCode: "PROVIDER_ERROR",
      errorMessage: "Provider request failed"
    });
    const { store } = createJobStore(job);

    const res = await request(buildApp(store))
      .get("/api/admin/jobs/job-failed")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`);

    expect(res.status).toBe(200);
    expect(res.body.data.result).toBeNull();
    expect(res.body.data.error).toEqual({ code: "PROVIDER_ERROR", message: "Provider request failed" });
  });

  it("returns 404 for a missing job", async () => {
    const { store, getById } = createJobStore(null);

    const res = await request(buildApp(store))
      .get("/api/admin/jobs/job-missing")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`);

    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: { code: "JOB_NOT_FOUND", message: "Job not found" } });
    expect(getById).toHaveBeenCalledWith("job-missing");
  });
});
