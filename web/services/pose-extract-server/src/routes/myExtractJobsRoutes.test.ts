import express from "express";
import request from "supertest";
import { describe, expect, it, vi } from "vitest";

import type { ExtractionJobListItem, ExtractionJobStore } from "../db/extractionJobStore";
import { createMyExtractJobsRoutes } from "./myExtractJobsRoutes";

const ACCOUNT = { id: "account-111", displayName: "User", createdAt: "2026-01-01T00:00:00.000Z" };

function accountMiddleware(account: typeof ACCOUNT | null = ACCOUNT) {
  return (req: express.Request, res: express.Response, next: express.NextFunction) => {
    if (account) {
      req.account = account;
      next();
    } else {
      res.status(401).json({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
    }
  };
}

describe("myExtractJobsRoutes", () => {
  const dummyJob: ExtractionJobListItem = {
    id: "job-123",
    status: "failed",
    sourceImageBase64: null,
    sourceMimeType: "image/png",
    resultImageBase64: null,
    resultMimeType: null,
    errorCode: "PROVIDER_ERROR",
    errorMessage: "Failure",
    attempts: 3,
    maxAttempts: 3,
    lockedAt: null,
    lockToken: null,
    createdAt: "2026-01-01T00:00:00.000Z",
    updatedAt: "2026-01-01T00:01:00.000Z",
    ownerAccountId: "account-111",
    poseDraft: { name: "Test Pose", tags: ["tag1"], description: "desc" },
    poseId: null,
    hiddenAt: null,
    thumbnailUrl: "https://r2.example.com/thumb.jpg"
  };

  it("returns 401 when unauthenticated", async () => {
    const jobStore = {} as ExtractionJobStore;
    const app = express().use("/api/me/extract-jobs", accountMiddleware(null), createMyExtractJobsRoutes({ jobStore }));

    const res = await request(app).get("/api/me/extract-jobs");
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe("UNAUTHORIZED");
  });

  it("lists jobs with pagination and filters", async () => {
    const listByOwner = vi.fn().mockResolvedValue({
      jobs: [dummyJob],
      nextCursor: "next-cursor-str"
    });
    const jobStore = { listByOwner } as unknown as ExtractionJobStore;
    const app = express().use("/api/me/extract-jobs", accountMiddleware(), createMyExtractJobsRoutes({ jobStore }));

    const res = await request(app).get("/api/me/extract-jobs?state=finished&limit=10");
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.data[0]).toEqual({
      jobId: dummyJob.id,
      status: dummyJob.status,
      poseDraft: dummyJob.poseDraft,
      poseId: dummyJob.poseId,
      errorCode: dummyJob.errorCode,
      errorMessage: dummyJob.errorMessage,
      thumbnailUrl: dummyJob.thumbnailUrl,
      createdAt: dummyJob.createdAt,
      updatedAt: dummyJob.updatedAt
    });
    expect(res.body.meta.nextCursor).toBe("next-cursor-str");
    expect(listByOwner).toHaveBeenCalledWith(ACCOUNT.id, {
      state: "finished",
      limit: 10,
      cursor: undefined
    });
  });

  it("rejects invalid state filter with 400", async () => {
    const jobStore = { listByOwner: vi.fn() } as unknown as ExtractionJobStore;
    const app = express().use("/api/me/extract-jobs", accountMiddleware(), createMyExtractJobsRoutes({ jobStore }));

    const res = await request(app).get("/api/me/extract-jobs?state=invalid");
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe("BAD_REQUEST");
  });

  it("rejects invalid limit with 400", async () => {
    const jobStore = { listByOwner: vi.fn() } as unknown as ExtractionJobStore;
    const app = express().use("/api/me/extract-jobs", accountMiddleware(), createMyExtractJobsRoutes({ jobStore }));

    const res1 = await request(app).get("/api/me/extract-jobs?limit=0");
    expect(res1.status).toBe(400);

    const res2 = await request(app).get("/api/me/extract-jobs?limit=101");
    expect(res2.status).toBe(400);

    const res3 = await request(app).get("/api/me/extract-jobs?limit=abc");
    expect(res3.status).toBe(400);
  });

  it("rejects invalid cursor with 400", async () => {
    const jobStore = { listByOwner: vi.fn() } as unknown as ExtractionJobStore;
    const app = express().use("/api/me/extract-jobs", accountMiddleware(), createMyExtractJobsRoutes({ jobStore }));

    const res = await request(app).get("/api/me/extract-jobs?cursor=invalid!cursor");
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe("BAD_REQUEST");
  });

  it("handles retry for requeued, not_found, and not_retryable", async () => {
    const retryFailed = vi
      .fn()
      .mockResolvedValueOnce("requeued")
      .mockResolvedValueOnce("not_found")
      .mockResolvedValueOnce("not_retryable");

    const jobStore = { retryFailed } as unknown as ExtractionJobStore;
    const app = express().use("/api/me/extract-jobs", accountMiddleware(), createMyExtractJobsRoutes({ jobStore }));

    const res1 = await request(app).post("/api/me/extract-jobs/job-1/retry");
    expect(res1.status).toBe(202);
    expect(res1.body.data.status).toBe("queued");
    expect(res1.body.meta.pollUrl).toBe("/api/extract-jobs/job-1");

    const res2 = await request(app).post("/api/me/extract-jobs/job-2/retry");
    expect(res2.status).toBe(404);
    expect(res2.body.error.code).toBe("JOB_NOT_FOUND");

    const res3 = await request(app).post("/api/me/extract-jobs/job-3/retry");
    expect(res3.status).toBe(409);
    expect(res3.body.error.code).toBe("JOB_NOT_RETRYABLE");
  });

  it("handles delete / hide with 204 and 404", async () => {
    const hide = vi
      .fn()
      .mockResolvedValueOnce(true)
      .mockResolvedValueOnce(false);

    const jobStore = { hide } as unknown as ExtractionJobStore;
    const app = express().use("/api/me/extract-jobs", accountMiddleware(), createMyExtractJobsRoutes({ jobStore }));

    const res1 = await request(app).delete("/api/me/extract-jobs/job-1");
    expect(res1.status).toBe(204);

    const res2 = await request(app).delete("/api/me/extract-jobs/job-2");
    expect(res2.status).toBe(404);
    expect(res2.body.error.code).toBe("JOB_NOT_FOUND");
  });
});
