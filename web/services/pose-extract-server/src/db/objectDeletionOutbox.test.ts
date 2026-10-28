import { randomUUID } from "node:crypto";

import { describe, expect, it, vi } from "vitest";

import { PoseStore } from "./communityStore";
import { applySchema, createDatabase, type Sql } from "./connection";
import { ExtractionJobStore } from "./extractionJobStore";
import { ProviderSettingsStore } from "./providerSettingsStore";
import {
  ObjectDeletionOutbox,
  drainPendingObjectDeletions,
  isObjectNotFoundError
} from "./objectDeletionOutbox";
import { setupTestDatabase } from "./testDb";
import { processNextJob } from "../worker/job-processor";

const TEST_DATABASE_URL = process.env.TEST_DATABASE_URL;

function notFoundError(): Error {
  return Object.assign(new Error("NoSuchKey"), {
    name: "NoSuchKey",
    $metadata: { httpStatusCode: 404 }
  });
}

describe("ObjectDeletionOutbox", () => {
  it("reserves keys so a later drain retries them instead of losing them", async () => {
    const sql = await setupTestDatabase();
    const outbox = new ObjectDeletionOutbox(sql);

    await outbox.reserve(["poses/a/original.png"], 60);
    await outbox.reserve(["poses/a/original.png", "poses/a/skeleton.png"], 60);

    expect(await outbox.count()).toBe(2);
    const rows = await outbox.list();
    expect(rows.every((row) => row.claimedUntil !== null)).toBe(true);
  });

  it("enqueues keys once and ignores duplicates", async () => {
    const sql = await setupTestDatabase();
    const outbox = new ObjectDeletionOutbox(sql);

    await outbox.enqueue(["poses/a/original.png", "poses/a/skeleton.png"]);
    await outbox.enqueue(["poses/a/original.png", "poses/a/thumbnail.png"]);

    const keys = (await outbox.list()).map((row) => row.key).sort();
    expect(keys).toEqual(["poses/a/original.png", "poses/a/skeleton.png", "poses/a/thumbnail.png"]);
    expect(await outbox.count()).toBe(3);
  });

  it("claims a batch in enqueue order and does not hand out a claimed key twice", async () => {
    const sql = await setupTestDatabase();
    const outbox = new ObjectDeletionOutbox(sql);
    await outbox.enqueue(["k1", "k2", "k3"]);
    await sql`UPDATE pending_object_deletions SET enqueued_at = NOW() - interval '1 minute' WHERE key = 'k1'`;
    await sql`UPDATE pending_object_deletions SET enqueued_at = NOW() - interval '2 minute' WHERE key = 'k2'`;

    const first = await outbox.claim(2);
    expect(first.map((entry) => entry.key).sort()).toEqual(["k1", "k2"]);

    const second = await outbox.claim(2);
    expect(second.map((entry) => entry.key)).toEqual(["k3"]);

    const third = await outbox.claim(2);
    expect(third).toEqual([]);
  });

  it("hands out a key again once its claim has expired", async () => {
    const sql = await setupTestDatabase();
    const outbox = new ObjectDeletionOutbox(sql);
    await outbox.enqueue(["stale-claim"]);
    expect((await outbox.claim(10)).map((entry) => entry.key)).toEqual(["stale-claim"]);

    await sql`UPDATE pending_object_deletions SET claimed_until = NOW() - interval '1 second'`;
    expect((await outbox.claim(10)).map((entry) => entry.key)).toEqual(["stale-claim"]);
  });

  it("ignores an acknowledgement from a drain whose claim already expired", async () => {
    const sql = await setupTestDatabase();
    const outbox = new ObjectDeletionOutbox(sql);
    await outbox.enqueue(["contended"]);

    const [staleClaim] = await outbox.claim(10);
    await sql`UPDATE pending_object_deletions SET claimed_until = NOW() - interval '1 second'`;
    const [freshClaim] = await outbox.claim(10);
    expect(freshClaim?.key).toBe("contended");
    expect(freshClaim?.claimToken).not.toBe(staleClaim?.claimToken);

    await outbox.markDeleted("contended", staleClaim?.claimToken);
    expect(await outbox.count()).toBe(1);

    await outbox.markDeleted("contended", freshClaim?.claimToken);
    expect(await outbox.count()).toBe(0);
  });

  it("hides a reserved key from drains until its reservation expires", async () => {
    const sql = await setupTestDatabase();
    const outbox = new ObjectDeletionOutbox(sql);

    await outbox.reserve(["poses/pending/original.png"], 900);
    expect(await outbox.claim(10)).toEqual([]);

    await sql`UPDATE pending_object_deletions SET claimed_until = NOW() - interval '1 second'`;
    expect((await outbox.claim(10)).map((entry) => entry.key)).toEqual(["poses/pending/original.png"]);
  });

  it("renews a live reservation and refuses one a drain already claimed", async () => {
    const sql = await setupTestDatabase();
    const outbox = new ObjectDeletionOutbox(sql);
    await outbox.reserve(["poses/live/original.png"], 60);

    expect(await outbox.renew(["poses/live/original.png"], 900)).toBe(true);
    const [row] = await outbox.list();
    expect(new Date(row!.claimedUntil!).getTime()).toBeGreaterThan(Date.now() + 10 * 60 * 1000);

    await sql`UPDATE pending_object_deletions SET claimed_until = NOW() - interval '1 second'`;
    await outbox.claim(10);
    expect(await outbox.renew(["poses/live/original.png"], 900)).toBe(false);
    expect(await outbox.renew(["poses/missing/original.png"], 900)).toBe(false);
  });

  it("refuses to hand over the finalize lease when the reservation is missing, lapsed, or claimed", async () => {
    const sql = await setupTestDatabase();
    const outbox = new ObjectDeletionOutbox(sql);
    const keys = ["poses/f/original.png", "poses/f/skeleton.png", "poses/f/thumbnail.png"];
    await outbox.reserve(keys, 900);

    expect(await outbox.acquireFinalizeLease(sql, keys)).toBe(true);

    await sql`UPDATE pending_object_deletions SET claimed_until = NOW() - interval '1 second' WHERE key = ${keys[1]}`;
    expect(await outbox.acquireFinalizeLease(sql, keys)).toBe(false);

    await sql`UPDATE pending_object_deletions SET claimed_until = NOW() + interval '10 minutes' WHERE key = ${keys[1]}`;
    await sql`UPDATE pending_object_deletions SET claimed_until = NOW() - interval '1 second' WHERE key <> ${keys[1]}`;
    expect((await outbox.claim(10)).map((entry) => entry.key).sort()).toEqual([keys[0], keys[2]].sort());
    expect(await outbox.acquireFinalizeLease(sql, keys)).toBe(false);

    await sql`DELETE FROM pending_object_deletions WHERE key = ${keys[0]}`;
    expect(await outbox.acquireFinalizeLease(sql, keys)).toBe(false);
  });

  it("reclaims keys so a late-landing object keeps a cleanup record", async () => {
    const sql = await setupTestDatabase();
    const outbox = new ObjectDeletionOutbox(sql);
    await outbox.reserve(["poses/late/original.png"], 60);
    await sql`UPDATE pending_object_deletions SET claimed_until = NOW() - interval '1 second'`;
    const [claim] = await outbox.claim(10);
    expect(claim?.key).toBe("poses/late/original.png");

    await outbox.reclaim(["poses/late/original.png"]);

    const rows = await outbox.list();
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ key: "poses/late/original.png", claimToken: null, claimedUntil: null });

    // The drain that lost its claim can no longer acknowledge the row away.
    await outbox.markDeleted("poses/late/original.png", claim?.claimToken);
    expect(await outbox.count()).toBe(1);
  });

  it("removes reserved keys from the finalize transaction once the pose owns them", async () => {
    const sql = await setupTestDatabase();
    const outbox = new ObjectDeletionOutbox(sql);
    const keys = ["poses/live/original.png", "poses/live/skeleton.png", "poses/live/thumbnail.png"];
    await outbox.reserve(keys, 900);

    await sql.begin(async (tx) => {
      await outbox.ackKeys(tx, keys);
    });

    expect(await outbox.count()).toBe(0);
  });
});

describe("drainPendingObjectDeletions", () => {
  it("removes a row after a successful delete and treats a 404 as success", async () => {
    const sql = await setupTestDatabase();
    const outbox = new ObjectDeletionOutbox(sql);
    await outbox.enqueue(["gone-already", "present"]);

    const deleted: string[] = [];
    const deleteObject = vi.fn(async (key: string) => {
      if (key === "gone-already") throw notFoundError();
      deleted.push(key);
    });

    const result = await drainPendingObjectDeletions({ outbox, deleteObject });

    expect(result).toEqual({ deleted: 2, failed: 0 });
    expect(deleted).toEqual(["present"]);
    expect(await outbox.count()).toBe(0);
  });

  it("keeps a failed key with attempts and the last error, then a healthy drain empties it", async () => {
    const sql = await setupTestDatabase();
    const outbox = new ObjectDeletionOutbox(sql);
    await outbox.enqueue(["flaky"]);

    const failingDelete = vi.fn(async () => {
      throw new Error("R2 unavailable");
    });
    await drainPendingObjectDeletions({ outbox, deleteObject: failingDelete });

    const [row] = await outbox.list();
    expect(row).toMatchObject({ key: "flaky", attempts: 1, lastError: "R2 unavailable" });
    expect(row?.claimedUntil).toBeNull();

    const result = await drainPendingObjectDeletions({ outbox, deleteObject: async () => undefined });
    expect(result).toEqual({ deleted: 1, failed: 0 });
    expect(await outbox.count()).toBe(0);
  });

  it("is a no-op on an empty outbox", async () => {
    const sql = await setupTestDatabase();
    const outbox = new ObjectDeletionOutbox(sql);
    const deleteObject = vi.fn();

    const result = await drainPendingObjectDeletions({ outbox, deleteObject });

    expect(result).toEqual({ deleted: 0, failed: 0 });
    expect(deleteObject).not.toHaveBeenCalled();
  });

  it("processes every key exactly once across back-to-back drains", async () => {
    const sql = await setupTestDatabase();
    const outbox = new ObjectDeletionOutbox(sql);
    const keys = Array.from({ length: 50 }, (_, index) => `object-${index}`);
    await outbox.enqueue(keys);

    const calls: string[] = [];
    const deleteObject = vi.fn(async (key: string) => {
      calls.push(key);
    });

    await drainPendingObjectDeletions({ outbox, deleteObject, limit: 30 });
    await drainPendingObjectDeletions({ outbox, deleteObject, limit: 30 });

    expect(calls.sort()).toEqual([...keys].sort());
    expect(new Set(calls).size).toBe(50);
    expect(await outbox.count()).toBe(0);
  });

  it("recognises not-found errors from the object storage client", () => {
    expect(isObjectNotFoundError(notFoundError())).toBe(true);
    expect(isObjectNotFoundError({ $metadata: { httpStatusCode: 404 } })).toBe(true);
    expect(isObjectNotFoundError({ statusCode: 404 })).toBe(true);
    expect(isObjectNotFoundError(new Error("R2 unavailable"))).toBe(false);
    expect(isObjectNotFoundError(undefined)).toBe(false);
  });
});

describe.runIf(TEST_DATABASE_URL)("drain against real Postgres", () => {
  it("never processes a claimed key twice across two connections", async () => {
    const admin = createDatabase(TEST_DATABASE_URL as string);
    const second = createDatabase(TEST_DATABASE_URL as string);
    await applySchema(admin);
    // Every key of this run lives under its own prefix, so the assertions never depend on
    // rows another run or another test file left in the shared database.
    const accountId = randomUUID();
    const keys = Array.from({ length: 50 }, () => `${accountId}/${randomUUID()}`);
    const ownKeys = (sql: Sql) => sql`
      SELECT COUNT(*)::int AS count FROM pending_object_deletions WHERE key LIKE ${`${accountId}/%`}
    `;

    try {
      await new ObjectDeletionOutbox(admin).enqueue(keys);
      const calls: string[] = [];
      const deleteObject = async (key: string): Promise<void> => {
        calls.push(key);
      };

      await Promise.all([
        drainPendingObjectDeletions({ outbox: new ObjectDeletionOutbox(admin), deleteObject, limit: 30 }),
        drainPendingObjectDeletions({ outbox: new ObjectDeletionOutbox(second), deleteObject, limit: 30 })
      ]);

      expect(calls).toHaveLength(50);
      expect(new Set(calls).size).toBe(50);
      expect(calls.every((key) => key.startsWith(`${accountId}/`))).toBe(true);
      expect(await ownKeys(admin)).toEqual([{ count: 0 }]);
    } finally {
      await admin`DELETE FROM pending_object_deletions WHERE key LIKE ${`${accountId}/%`}`;
      await admin.end();
      await second.end();
    }
  });
});

describe.runIf(TEST_DATABASE_URL)("reservation lease against real Postgres", () => {
  async function startPausedOwnerJob() {
    const admin = createDatabase(TEST_DATABASE_URL as string);
    await applySchema(admin);
    const workerConn = createDatabase(TEST_DATABASE_URL as string);
    const sweepConn = createDatabase(TEST_DATABASE_URL as string);
    const accountId = randomUUID();
    await admin`INSERT INTO accounts (id, display_name) VALUES (${accountId}, ${accountId})`;

    const jobStore = new ExtractionJobStore(workerConn);
    const job = await jobStore.enqueue({
      ownerAccountId: accountId,
      poseDraft: { name: "Leased", tags: [], description: null },
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });

    const pending: Array<{ key: string; release: () => void }> = [];
    const uploaded: string[] = [];
    const mediaStorage = {
      put: async (key: string) => {
        await new Promise<void>((resolve) => {
          pending.push({ key, release: resolve });
        });
        uploaded.push(key);
      },
      remove: async () => undefined,
      publicUrl: (key: string) => `https://cdn.example.com/${key}`
    };

    const running = processNextJob({
      jobStore,
      providerSettingsStore: new ProviderSettingsStore(workerConn),
      createProvider: () => ({
        id: "gemini_native" as const,
        extractPoseImage: async () => ({
          imageBase64: Buffer.from("skeleton").toString("base64"),
          mimeType: "image/png" as const
        })
      }),
      staleLockSeconds: 120,
      db: workerConn,
      communityStore: new PoseStore(workerConn),
      mediaStorage,
      lineartBackgroundRemover: {
        enabled: true,
        removeBackground: async (image: { imageBase64: string; mimeType: "image/png" | "image/jpeg" | "image/webp" }) => ({
          imageBase64: image.imageBase64,
          mimeType: "image/png" as const
        })
      }
    });

    for (let waited = 0; pending.length < 3; waited += 1) {
      if (waited > 400) throw new Error("uploads did not start");
      await new Promise((resolve) => setTimeout(resolve, 10));
    }

    return {
      admin,
      workerConn,
      sweepConn,
      accountId,
      job,
      jobStore,
      running,
      pending,
      uploaded,
      sweepOutbox: new ObjectDeletionOutbox(sweepConn)
    };
  }

  async function teardown(
    admin: Sql,
    accountId: string,
    jobId: string,
    keys: readonly string[],
    connections: Sql[]
  ): Promise<void> {
    for (const key of keys) {
      await admin`DELETE FROM pending_object_deletions WHERE key = ${key}`;
    }
    await admin`DELETE FROM extraction_jobs WHERE id = ${jobId}`;
    await admin`DELETE FROM media_assets WHERE pose_id IN (SELECT pose_id FROM poses WHERE owner_account_id = ${accountId})`;
    await admin`DELETE FROM poses WHERE owner_account_id = ${accountId}`;
    await admin`DELETE FROM deleted_accounts WHERE account_id = ${accountId}`;
    await admin`DELETE FROM accounts WHERE id = ${accountId}`;
    for (const connection of connections) await connection.end();
  }

  it("never succeeds a job whose reservation the sweep claimed while uploads were in flight", async () => {
    const harness = await startPausedOwnerJob();
    const keys = harness.pending.map((entry) => entry.key);

    try {
      // The lease lapses and a second connection sweeps every key before the uploads land.
      await harness.admin`
        UPDATE pending_object_deletions
        SET claimed_until = NOW() - interval '1 second'
        WHERE key IN ${harness.admin(keys)}
      `;
      const swept: string[] = [];
      await drainPendingObjectDeletions({
        outbox: harness.sweepOutbox,
        deleteObject: async (key: string) => {
          swept.push(key);
        }
      });
      expect(swept.sort()).toEqual([...keys].sort());

      for (const upload of harness.pending) upload.release();
      await expect(harness.running).resolves.toBe(true);

      const job = await harness.jobStore.getById(harness.job.id);
      expect(job?.status).toBe("queued");
      expect(job?.errorCode).toBe("POSE_MATERIALIZE_FAILED");

      const poseRows = (await harness.admin`
        SELECT pose_id FROM poses WHERE owner_account_id = ${harness.accountId}
      `) as Array<{ pose_id: string }>;
      expect(poseRows).toHaveLength(0);

      const outbox = new ObjectDeletionOutbox(harness.admin);
      const reclaimed = (await outbox.list())
        .map((row) => row.key)
        .filter((key) => keys.includes(key))
        .sort();
      expect(reclaimed).toEqual([...harness.uploaded].sort());

      const retried: string[] = [];
      await drainPendingObjectDeletions({
        outbox,
        deleteObject: async (key: string) => {
          retried.push(key);
        }
      });
      expect(retried.sort()).toEqual([...keys].sort());
    } finally {
      await teardown(
        harness.admin,
        harness.accountId,
        harness.job.id,
        keys,
        [harness.admin, harness.workerConn, harness.sweepConn]
      );
    }
  });

  it("keeps a cleanup record for an object that lands after the sweep acknowledged its key", async () => {
    const harness = await startPausedOwnerJob();
    const keys = harness.pending.map((entry) => entry.key);
    const target = keys[0]!;

    try {
      await harness.admin`
        UPDATE pending_object_deletions
        SET claimed_until = NOW() - interval '1 second'
        WHERE key = ${target}
      `;
      await drainPendingObjectDeletions({
        outbox: harness.sweepOutbox,
        deleteObject: async () => undefined
      });

      for (const upload of harness.pending) upload.release();
      await expect(harness.running).resolves.toBe(true);

      const job = await harness.jobStore.getById(harness.job.id);
      expect(job?.status).toBe("queued");
      expect(job?.errorCode).toBe("POSE_MATERIALIZE_FAILED");

      const rows = await new ObjectDeletionOutbox(harness.admin).list();
      const own = rows.map((row) => row.key).filter((key) => keys.includes(key)).sort();
      expect(own).toEqual([...harness.uploaded].sort());

      const retried: string[] = [];
      await drainPendingObjectDeletions({
        outbox: new ObjectDeletionOutbox(harness.admin),
        deleteObject: async (key: string) => {
          retried.push(key);
        }
      });
      expect(retried).toContain(target);
    } finally {
      await teardown(
        harness.admin,
        harness.accountId,
        harness.job.id,
        keys,
        [harness.admin, harness.workerConn, harness.sweepConn]
      );
    }
  });

  it("cannot let a drain claim the keys while the finalize transaction holds them", async () => {
    const admin = createDatabase(TEST_DATABASE_URL as string);
    await applySchema(admin);
    const workerConn = createDatabase(TEST_DATABASE_URL as string);
    const sweepConn = createDatabase(TEST_DATABASE_URL as string);
    const lockConn = createDatabase(TEST_DATABASE_URL as string);
    const accountId = randomUUID();
    const mediaStorageKeys: string[] = [];
    let lockedJobRow!: () => void;
    const jobRowLocked = new Promise<void>((resolve) => {
      lockedJobRow = resolve;
    });
    let releaseJobRow!: () => void;
    const jobRowRelease = new Promise<void>((resolve) => {
      releaseJobRow = resolve;
    });
    let jobLockTx: Promise<unknown> | null = null;
    let jobId = "";

    try {
      await admin`INSERT INTO accounts (id, display_name) VALUES (${accountId}, ${accountId})`;
      const jobStore = new ExtractionJobStore(workerConn);
      const job = await jobStore.enqueue({
        ownerAccountId: accountId,
        poseDraft: { name: "Locked Finalize", tags: [], description: null },
        sourceImageBase64: Buffer.from("source").toString("base64"),
        sourceMimeType: "image/png"
      });
      jobId = job.id;

      // Hold the job row open after the worker claimed it: the finalize transaction then parks
      // on that row with its reservation rows already locked.
      const running = processNextJob({
        jobStore,
        providerSettingsStore: new ProviderSettingsStore(workerConn),
        createProvider: () => ({
          id: "gemini_native" as const,
          extractPoseImage: async () => {
            jobLockTx = lockConn.begin(async (tx) => {
              await tx`SELECT id FROM extraction_jobs WHERE id = ${job.id} FOR UPDATE`;
              lockedJobRow();
              await jobRowRelease;
            });
            await jobRowLocked;
            return {
              imageBase64: Buffer.from("skeleton").toString("base64"),
              mimeType: "image/png" as const
            };
          }
        }),
        staleLockSeconds: 120,
        db: workerConn,
        communityStore: new PoseStore(workerConn),
        mediaStorage: {
          put: async (key: string) => {
            mediaStorageKeys.push(key);
          },
          remove: async () => undefined,
          publicUrl: (key: string) => `https://cdn.example.com/${key}`
        },
        lineartBackgroundRemover: {
          enabled: true,
          removeBackground: async (image: { imageBase64: string; mimeType: "image/png" | "image/jpeg" | "image/webp" }) => ({
            imageBase64: image.imageBase64,
            mimeType: "image/png" as const
          })
        }
      });

      // Give the finalize transaction time to reach the job row, then sweep concurrently.
      await new Promise((resolve) => setTimeout(resolve, 400));
      const swept: string[] = [];
      const claimable = await new ObjectDeletionOutbox(sweepConn).claim(10);
      await drainPendingObjectDeletions({
        outbox: new ObjectDeletionOutbox(sweepConn),
        deleteObject: async (key: string) => {
          swept.push(key);
        }
      });

      expect(claimable).toEqual([]);
      expect(swept).toEqual([]);

      // The locked reservation row must refuse a concurrent lock attempt outright.
      let lockErrorCode: string | null = null;
      try {
        await sweepConn`
          SELECT key FROM pending_object_deletions
          WHERE key = ${mediaStorageKeys[0]!}
          FOR UPDATE NOWAIT
        `;
      } catch (error) {
        lockErrorCode = (error as { code?: string }).code ?? "unknown";
      }
      expect(lockErrorCode).toBe("55P03");

      releaseJobRow();
      await jobLockTx;
      await expect(running).resolves.toBe(true);

      const updated = await jobStore.getById(job.id);
      expect(updated?.status).toBe("succeeded");
      expect(mediaStorageKeys).toHaveLength(3);
      expect(await new ObjectDeletionOutbox(admin).count()).toBe(0);

      const poseRows = (await admin`
        SELECT pose_id FROM poses WHERE owner_account_id = ${accountId}
      `) as Array<{ pose_id: string }>;
      expect(poseRows).toHaveLength(1);
    } finally {
      releaseJobRow();
      await jobLockTx;
      if (jobId) {
        await admin`DELETE FROM pending_object_deletions WHERE key LIKE ${`poses/%`} AND key IN (
          SELECT locator FROM media_assets WHERE pose_id IN (SELECT pose_id FROM poses WHERE current_job_id = ${jobId})
        )`;
        await admin`DELETE FROM media_assets WHERE pose_id IN (SELECT pose_id FROM poses WHERE owner_account_id = ${accountId})`;
        await admin`DELETE FROM poses WHERE owner_account_id = ${accountId}`;
        await admin`DELETE FROM extraction_jobs WHERE id = ${jobId}`;
      }
      await admin`DELETE FROM deleted_accounts WHERE account_id = ${accountId}`;
      await admin`DELETE FROM accounts WHERE id = ${accountId}`;
      for (const connection of [admin, workerConn, sweepConn, lockConn]) await connection.end();
    }
  });
});
