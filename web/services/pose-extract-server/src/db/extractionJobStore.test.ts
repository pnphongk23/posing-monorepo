import { describe, expect, it } from "vitest";

import { PoseStore } from "./communityStore";
import { ExtractionJobStore, StaleLockError, type PoseDraft } from "./extractionJobStore";
import { setupTestDatabase } from "./testDb";

const OWNER_A = "11111111-1111-4111-8111-111111111111";
const OWNER_B = "22222222-2222-4222-8222-222222222222";

const SAMPLE_DRAFT: PoseDraft = {
  name: "Tree Pose",
  tags: ["balance", "standing"],
  description: "A one-legged balancing pose"
};

describe("ExtractionJobStore", () => {
  it("enqueues jobs with ownerAccountId, poseDraft, and defaults", async () => {
    const sql = await setupTestDatabase();
    const store = new ExtractionJobStore(sql);

    const job = await store.enqueue({
      sourceImageBase64: "c291cmNl",
      sourceMimeType: "image/jpeg",
      ownerAccountId: OWNER_A,
      poseDraft: SAMPLE_DRAFT
    });

    expect(job.id).toMatch(/^[0-9a-f-]{36}$/);
    expect(job.status).toBe("queued");
    expect(job.sourceImageBase64).toBe("c291cmNl");
    expect(job.sourceMimeType).toBe("image/jpeg");
    expect(job.ownerAccountId).toBe(OWNER_A);
    expect(job.poseDraft).toEqual(SAMPLE_DRAFT);
    expect(job.poseId).toBeNull();
    expect(job.hiddenAt).toBeNull();
    expect(job.attempts).toBe(0);
    expect(job.maxAttempts).toBe(3);
  });

  it("enforces owner isolation on getByIdForOwner", async () => {
    const sql = await setupTestDatabase();
    const store = new ExtractionJobStore(sql);

    const jobA = await store.enqueue({
      sourceImageBase64: "c291cmNl",
      sourceMimeType: "image/jpeg",
      ownerAccountId: OWNER_A,
      poseDraft: SAMPLE_DRAFT
    });

    // Owner A can fetch their job
    const fetchedByA = await store.getByIdForOwner(jobA.id, OWNER_A);
    expect(fetchedByA?.id).toBe(jobA.id);

    // Owner B cannot fetch Owner A's job
    const fetchedByB = await store.getByIdForOwner(jobA.id, OWNER_B);
    expect(fetchedByB).toBeNull();

    // Unknown ID returns null
    const fetchedUnknown = await store.getByIdForOwner("00000000-0000-0000-0000-000000000000", OWNER_A);
    expect(fetchedUnknown).toBeNull();
  });

  it("excludes hidden jobs from getByIdForOwner", async () => {
    const sql = await setupTestDatabase();
    const store = new ExtractionJobStore(sql);

    const job = await store.enqueue({
      sourceImageBase64: "c291cmNl",
      sourceMimeType: "image/jpeg",
      ownerAccountId: OWNER_A,
      poseDraft: SAMPLE_DRAFT
    });

    await store.hide(job.id, OWNER_A);

    const fetched = await store.getByIdForOwner(job.id, OWNER_A);
    expect(fetched).toBeNull();

    // Raw getById still finds it with hiddenAt populated
    const raw = await store.getById(job.id);
    expect(raw?.hiddenAt).not.toBeNull();
  });

  it("paginates across 25 jobs with keyset cursor and respects limits", async () => {
    const sql = await setupTestDatabase();
    const store = new ExtractionJobStore(sql);

    // Insert 25 jobs with distinct timestamps
    for (let i = 0; i < 25; i++) {
      const id = `job-page-${String(i).padStart(2, "0")}`;
      await sql`
        INSERT INTO extraction_jobs (
          id, status, source_image_base64, source_mime_type, owner_account_id, created_at, updated_at
        ) VALUES (
          ${id}, 'queued', 'c291cmNl', 'image/jpeg', ${OWNER_A},
          NOW() - (${25 - i} * interval '1 minute'),
          NOW() - (${25 - i} * interval '1 minute')
        )
      `;
    }

    // Page 1: limit 10
    const page1 = await store.listByOwner(OWNER_A, { limit: 10 });
    expect(page1.jobs).toHaveLength(10);
    expect(page1.nextCursor).not.toBeNull();
    // Newest first -> job-page-24 down to job-page-15
    expect(page1.jobs[0].id).toBe("job-page-24");
    expect(page1.jobs[9].id).toBe("job-page-15");

    // Page 2: limit 10 using page1 nextCursor
    const page2 = await store.listByOwner(OWNER_A, { limit: 10, cursor: page1.nextCursor });
    expect(page2.jobs).toHaveLength(10);
    expect(page2.nextCursor).not.toBeNull();
    expect(page2.jobs[0].id).toBe("job-page-14");
    expect(page2.jobs[9].id).toBe("job-page-05");

    // Page 3: limit 10 using page2 nextCursor (remaining 5 jobs)
    const page3 = await store.listByOwner(OWNER_A, { limit: 10, cursor: page2.nextCursor });
    expect(page3.jobs).toHaveLength(5);
    expect(page3.nextCursor).toBeNull();
    expect(page3.jobs[0].id).toBe("job-page-04");
    expect(page3.jobs[4].id).toBe("job-page-00");

    // Total unique IDs retrieved across pages is 25
    const allIds = [...page1.jobs, ...page2.jobs, ...page3.jobs].map((j) => j.id);
    expect(new Set(allIds).size).toBe(25);
  });

  it("filters listByOwner by state ('active' vs 'finished')", async () => {
    const sql = await setupTestDatabase();
    const store = new ExtractionJobStore(sql);

    await sql`
      INSERT INTO extraction_jobs (id, status, source_image_base64, source_mime_type, owner_account_id) VALUES
      ('j-queued', 'queued', 'src', 'image/png', ${OWNER_A}),
      ('j-processing', 'processing', 'src', 'image/png', ${OWNER_A}),
      ('j-succeeded', 'succeeded', 'src', 'image/png', ${OWNER_A}),
      ('j-failed', 'failed', 'src', 'image/png', ${OWNER_A})
    `;

    const activeList = await store.listByOwner(OWNER_A, { state: "active" });
    const activeIds = activeList.jobs.map((j) => j.id);
    expect(activeIds).toEqual(expect.arrayContaining(["j-queued", "j-processing"]));
    expect(activeIds).not.toContain("j-succeeded");
    expect(activeIds).not.toContain("j-failed");

    const finishedList = await store.listByOwner(OWNER_A, { state: "finished" });
    const finishedIds = finishedList.jobs.map((j) => j.id);
    expect(finishedIds).toEqual(expect.arrayContaining(["j-succeeded", "j-failed"]));
    expect(finishedIds).not.toContain("j-queued");
    expect(finishedIds).not.toContain("j-processing");
  });

  it("excludes hidden jobs from listByOwner and joins thumbnailUrl", async () => {
    const sql = await setupTestDatabase();
    const store = new ExtractionJobStore(sql);
    const poseStore = new PoseStore(sql);

    const pose = await poseStore.createPose({
      ownerAccountId: OWNER_A,
      name: "Warrior",
      originalUrl: "https://r2.example.com/original.png",
      skeletonUrl: "https://r2.example.com/skeleton.png",
      thumbnailUrl: "https://r2.example.com/thumbnail.png",
      tags: ["standing"],
      difficulty: "beginner",
      description: "Warrior pose",
      bodyParts: ["legs"]
    });

    await sql`
      INSERT INTO extraction_jobs (id, status, source_image_base64, source_mime_type, owner_account_id, pose_id)
      VALUES ('job-with-pose', 'succeeded', NULL, 'image/png', ${OWNER_A}, ${pose.poseId});
    `;

    const visibleJob = await store.enqueue({
      sourceImageBase64: "src",
      sourceMimeType: "image/png",
      ownerAccountId: OWNER_A
    });

    const hiddenJob = await store.enqueue({
      sourceImageBase64: "src",
      sourceMimeType: "image/png",
      ownerAccountId: OWNER_A
    });
    await store.hide(hiddenJob.id, OWNER_A);

    const result = await store.listByOwner(OWNER_A);
    const ids = result.jobs.map((j) => j.id);

    expect(ids).toContain("job-with-pose");
    expect(ids).toContain(visibleJob.id);
    expect(ids).not.toContain(hiddenJob.id);

    const poseJobItem = result.jobs.find((j) => j.id === "job-with-pose");
    expect(poseJobItem?.thumbnailUrl).toBe("https://r2.example.com/thumbnail.png");

    const visibleJobItem = result.jobs.find((j) => j.id === visibleJob.id);
    expect(visibleJobItem?.thumbnailUrl).toBeNull();
  });

  describe("retryFailed", () => {
    it("requeues a failed job and resets attempts and errors", async () => {
      const sql = await setupTestDatabase();
      const store = new ExtractionJobStore(sql);

      await sql`
        INSERT INTO extraction_jobs (
          id, status, source_image_base64, source_mime_type, owner_account_id, attempts, error_code, error_message
        ) VALUES (
          'failed-1', 'failed', 'c291cmNl', 'image/png', ${OWNER_A}, 3, 'PROVIDER_ERROR', 'Timeout'
        )
      `;

      const result = await store.retryFailed("failed-1", OWNER_A);
      expect(result).toBe("requeued");

      const job = await store.getById("failed-1");
      expect(job?.status).toBe("queued");
      expect(job?.attempts).toBe(0);
      expect(job?.errorCode).toBeNull();
      expect(job?.errorMessage).toBeNull();
      expect(job?.lockToken).toBeNull();
    });

    it("returns not_retryable for queued, processing, or succeeded statuses", async () => {
      const sql = await setupTestDatabase();
      const store = new ExtractionJobStore(sql);

      await sql`
        INSERT INTO extraction_jobs (id, status, source_image_base64, source_mime_type, owner_account_id) VALUES
        ('j-q', 'queued', 'src', 'image/png', ${OWNER_A}),
        ('j-p', 'processing', 'src', 'image/png', ${OWNER_A}),
        ('j-s', 'succeeded', 'src', 'image/png', ${OWNER_A})
      `;

      expect(await store.retryFailed("j-q", OWNER_A)).toBe("not_retryable");
      expect(await store.retryFailed("j-p", OWNER_A)).toBe("not_retryable");
      expect(await store.retryFailed("j-s", OWNER_A)).toBe("not_retryable");
    });

    it("returns not_found for foreign-owned, non-existent, or hidden failed jobs", async () => {
      const sql = await setupTestDatabase();
      const store = new ExtractionJobStore(sql);

      await sql`
        INSERT INTO extraction_jobs (id, status, source_image_base64, source_mime_type, owner_account_id, hidden_at) VALUES
        ('j-foreign', 'failed', 'src', 'image/png', ${OWNER_B}, NULL),
        ('j-hidden-failed', 'failed', 'src', 'image/png', ${OWNER_A}, NOW())
      `;

      expect(await store.retryFailed("j-foreign", OWNER_A)).toBe("not_found");
      expect(await store.retryFailed("j-hidden-failed", OWNER_A)).toBe("not_found");
      expect(await store.retryFailed("non-existent-id", OWNER_A)).toBe("not_found");
    });
  });

  describe("hide", () => {
    it("is idempotent and preserves initial hidden_at timestamp", async () => {
      const sql = await setupTestDatabase();
      const store = new ExtractionJobStore(sql);

      const job = await store.enqueue({
        sourceImageBase64: "src",
        sourceMimeType: "image/png",
        ownerAccountId: OWNER_A
      });

      const firstHide = await store.hide(job.id, OWNER_A);
      expect(firstHide).toBe(true);

      const afterFirst = await store.getById(job.id);
      expect(afterFirst?.hiddenAt).not.toBeNull();

      const secondHide = await store.hide(job.id, OWNER_A);
      expect(secondHide).toBe(true);

      const afterSecond = await store.getById(job.id);
      expect(afterSecond?.hiddenAt).toBe(afterFirst?.hiddenAt);
    });

    it("nulls source_image_base64 only when status is failed", async () => {
      const sql = await setupTestDatabase();
      const store = new ExtractionJobStore(sql);

      await sql`
        INSERT INTO extraction_jobs (id, status, source_image_base64, source_mime_type, owner_account_id) VALUES
        ('hide-queued', 'queued', 'source-q', 'image/png', ${OWNER_A}),
        ('hide-failed', 'failed', 'source-f', 'image/png', ${OWNER_A})
      `;

      await store.hide("hide-queued", OWNER_A);
      const queuedJob = await store.getById("hide-queued");
      expect(queuedJob?.sourceImageBase64).toBe("source-q");

      await store.hide("hide-failed", OWNER_A);
      const failedJob = await store.getById("hide-failed");
      expect(failedJob?.sourceImageBase64).toBeNull();
    });

    it("returns false for foreign-owned or non-existent jobs", async () => {
      const sql = await setupTestDatabase();
      const store = new ExtractionJobStore(sql);

      await sql`
        INSERT INTO extraction_jobs (id, status, source_image_base64, source_mime_type, owner_account_id)
        VALUES ('foreign-job', 'queued', 'src', 'image/png', ${OWNER_B})
      `;

      expect(await store.hide("foreign-job", OWNER_A)).toBe(false);
      expect(await store.hide("missing-job", OWNER_A)).toBe(false);
    });
  });

  describe("markSucceededWithPose", () => {
    it("sets status='succeeded', pose_id, and nulls both base64 fields", async () => {
      const sql = await setupTestDatabase();
      const store = new ExtractionJobStore(sql);

      await sql`
        INSERT INTO extraction_jobs (
          id, status, source_image_base64, result_image_base64, source_mime_type, lock_token, locked_at
        ) VALUES (
          'job-to-succeed', 'processing', 'src-b64', 'res-b64', 'image/png', 'token-123', NOW()
        )
      `;

      await sql.begin(async (tx) => {
        await store.markSucceededWithPose(tx, "job-to-succeed", "token-123", "pose-uuid-999");
      });

      const updated = await store.getById("job-to-succeed");
      expect(updated?.status).toBe("succeeded");
      expect(updated?.poseId).toBe("pose-uuid-999");
      expect(updated?.sourceImageBase64).toBeNull();
      expect(updated?.resultImageBase64).toBeNull();
      expect(updated?.lockToken).toBeNull();
      expect(updated?.lockedAt).toBeNull();
    });

    it("throws StaleLockError and leaves row unchanged on stale lock token", async () => {
      const sql = await setupTestDatabase();
      const store = new ExtractionJobStore(sql);

      await sql`
        INSERT INTO extraction_jobs (
          id, status, source_image_base64, result_image_base64, source_mime_type, lock_token, locked_at
        ) VALUES (
          'job-stale', 'processing', 'original-src', 'original-res', 'image/png', 'correct-token', NOW()
        )
      `;

      await expect(
        sql.begin(async (tx) => {
          await store.markSucceededWithPose(tx, "job-stale", "wrong-token", "pose-uuid-999");
        })
      ).rejects.toThrow(StaleLockError);

      const unchanged = await store.getById("job-stale");
      expect(unchanged?.status).toBe("processing");
      expect(unchanged?.poseId).toBeNull();
      expect(unchanged?.sourceImageBase64).toBe("original-src");
      expect(unchanged?.resultImageBase64).toBe("original-res");
      expect(unchanged?.lockToken).toBe("correct-token");
    });
  });
});
