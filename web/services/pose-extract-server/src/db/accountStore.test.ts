import { randomUUID } from "node:crypto";

import { describe, expect, it, vi } from "vitest";

import {
  AccountDeletedError,
  AccountStore,
  sweepStaleAccountPurges,
  objectKeyFromLocator
} from "./accountStore";
import { PoseStore } from "./communityStore";
import { applySchema, createDatabase, type Sql } from "./connection";
import { ExtractionJobStore, StaleLockError } from "./extractionJobStore";
import { ObjectDeletionOutbox, drainPendingObjectDeletions } from "./objectDeletionOutbox";
import { materializePose, type MediaStorage } from "../services/poseMaterializer";
import { setupTestDatabase } from "./testDb";

const TEST_DATABASE_URL = process.env.TEST_DATABASE_URL;
const R2_PUBLIC_URL = "https://cdn.example.com";

interface TableCounts {
  accounts: number;
  saved_entries: number;
  poses: number;
  media_assets: number;
  extraction_jobs: number;
}

async function countsFor(sql: Sql, accountId: string): Promise<TableCounts> {
  const rows = (await sql`
    SELECT
      (SELECT COUNT(*)::int FROM accounts WHERE id = ${accountId}) AS accounts,
      (SELECT COUNT(*)::int FROM saved_entries WHERE account_id = ${accountId}) AS saved_entries,
      (SELECT COUNT(*)::int FROM poses WHERE owner_account_id = ${accountId}) AS poses,
      (SELECT COUNT(*)::int FROM media_assets m JOIN poses p ON p.pose_id = m.pose_id WHERE p.owner_account_id = ${accountId}) AS media_assets,
      (SELECT COUNT(*)::int FROM extraction_jobs WHERE owner_account_id = ${accountId}) AS extraction_jobs
  `) as TableCounts[];
  return rows[0]!;
}

async function seedAccount(sql: Sql, accountId: string, label: string): Promise<string[]> {
  await sql`INSERT INTO accounts (id, display_name) VALUES (${accountId}, ${label})`;

  const poseIds = [`${label}-pose-1`, `${label}-pose-2`];
  const locators: string[] = [];
  for (const poseId of poseIds) {
    await sql`INSERT INTO poses (pose_id, owner_account_id, name) VALUES (${poseId}, ${accountId}, ${poseId})`;
    for (const role of ["original", "skeleton", "thumbnail"] as const) {
      const locator = `${R2_PUBLIC_URL}/poses/${poseId}/${role}.png`;
      locators.push(locator);
      await sql`INSERT INTO media_assets (media_id, pose_id, role, locator)
        VALUES (${`${poseId}-${role}`}, ${poseId}, ${role}, ${locator})`;
    }
    await sql`INSERT INTO saved_entries (account_id, pose_id) VALUES (${accountId}, ${poseId})`;
  }

  await sql`INSERT INTO extraction_jobs (id, status, source_image_base64, source_mime_type, owner_account_id)
    VALUES (${`${label}-job-queued`}, 'queued', ${"c291cmNl"}, 'image/png', ${accountId})`;
  await sql`INSERT INTO extraction_jobs (id, status, source_image_base64, source_mime_type, owner_account_id, attempts, lock_token, locked_at)
    VALUES (${`${label}-job-running`}, 'processing', ${"c291cmNl"}, 'image/png', ${accountId}, 1, ${"token"}, NOW())`;
  await sql`INSERT INTO extraction_jobs (id, status, source_mime_type, owner_account_id)
    VALUES (${`${label}-job-succeeded`}, 'succeeded', 'image/png', ${accountId})`;

  return locators.map((locator) => objectKeyFromLocator(locator, R2_PUBLIC_URL));
}

const ZERO: TableCounts = {
  accounts: 0,
  saved_entries: 0,
  poses: 0,
  media_assets: 0,
  extraction_jobs: 0
};

describe("AccountStore.purgeAccountData", () => {
  it("removes every row an account owns, enqueues its object keys, and leaves another account untouched", async () => {
    const sql = await setupTestDatabase();
    const store = new AccountStore(sql);
    const accountA = randomUUID();
    const accountB = randomUUID();

    const keysA = await seedAccount(sql, accountA, "a");
    await seedAccount(sql, accountB, "b");
    const countsBBefore = await countsFor(sql, accountB);

    const purgedKeys = await store.purgeAccountData(accountA, {
      resolveObjectKey: (locator) => objectKeyFromLocator(locator, R2_PUBLIC_URL)
    });

    expect([...purgedKeys].sort()).toEqual([...keysA].sort());
    expect(await countsFor(sql, accountA)).toEqual(ZERO);
    expect(await countsFor(sql, accountB)).toEqual(countsBBefore);
    expect(countsBBefore).toMatchObject({ accounts: 1, poses: 2, media_assets: 6, extraction_jobs: 3 });

    const outboxKeys = (await new ObjectDeletionOutbox(sql).list()).map((row) => row.key).sort();
    expect(outboxKeys).toEqual([...keysA].sort());
  });

  it("rolls the whole purge back when the transaction fails, leaving no orphaned deletion rows", async () => {
    const sql = await setupTestDatabase();
    const store = new AccountStore(sql);
    const accountId = randomUUID();
    await seedAccount(sql, accountId, "rollback");
    const before = await countsFor(sql, accountId);

    await expect(
      store.purgeAccountData(accountId, {
        resolveObjectKey: (locator) => objectKeyFromLocator(locator, R2_PUBLIC_URL),
        onRowsLocked: async () => {
          throw new Error("purge aborted mid-transaction");
        }
      })
    ).rejects.toThrow("purge aborted mid-transaction");

    expect(await countsFor(sql, accountId)).toEqual(before);
    expect(await new ObjectDeletionOutbox(sql).count()).toBe(0);
  });

  it("takes the account and job rows before it collects media keys", async () => {
    const sql = await setupTestDatabase();
    const store = new AccountStore(sql);
    const accountId = randomUUID();
    await seedAccount(sql, accountId, "order");

    let jobsVisibleInsideLock = 0;
    let outboxInsideLock = -1;
    await store.purgeAccountData(accountId, {
      resolveObjectKey: (locator) => objectKeyFromLocator(locator, R2_PUBLIC_URL),
      onRowsLocked: async (transaction) => {
        const rows = (await transaction`
          SELECT COUNT(*)::int AS count FROM extraction_jobs WHERE owner_account_id = ${accountId}
        `) as Array<{ count: number }>;
        jobsVisibleInsideLock = rows[0]?.count ?? 0;
        const outboxRows = (await transaction`
          SELECT COUNT(*)::int AS count FROM pending_object_deletions
        `) as Array<{ count: number }>;
        outboxInsideLock = outboxRows[0]?.count ?? 0;
      }
    });

    expect(jobsVisibleInsideLock).toBe(3);
    expect(outboxInsideLock).toBe(0);
    expect(await countsFor(sql, accountId)).toEqual(ZERO);
  });

  it("queues the object keys of an attempt that is still in flight, with the upload horizon", async () => {
    const sql = await setupTestDatabase();
    const store = new AccountStore(sql);
    const accountId = randomUUID();
    await seedAccount(sql, accountId, "inflight");
    const poseId = randomUUID();
    const jobId = randomUUID();
    const keys = ["original", "skeleton", "thumbnail"].map((role) => `poses/${poseId}/${role}.png`);
    const { createdAt } = await store.mediaManifests.record({
      poseId,
      jobId,
      ownerAccountId: accountId,
      keys
    });

    await store.purgeAccountData(accountId);

    expect(await store.mediaManifests.abandon(poseId)).toBe(0);
    const tickets = (await sql`
      SELECT key, not_before FROM pending_object_deletions WHERE key LIKE ${`poses/${poseId}/%`}
    `) as Array<{ key: string; not_before: Date | string }>;
    expect(tickets).toHaveLength(3);
    const expectedNotBefore = Date.parse(createdAt) + 3600 * 1000;
    for (const ticket of tickets) {
      expect(Date.parse(String(ticket.not_before))).toBeGreaterThanOrEqual(expectedNotBefore - 2000);
    }
    expect(await countsFor(sql, accountId)).toEqual(ZERO);
    expect(await store.hasAccountTombstone(accountId)).toBe(true);
  });

  it("drops the purge intent row once the data is gone", async () => {
    const sql = await setupTestDatabase();
    const store = new AccountStore(sql);
    const accountId = randomUUID();
    await seedAccount(sql, accountId, "intent");
    await store.recordPurgeIntent(accountId);
    expect(await store.hasPurgeIntent(accountId)).toBe(true);

    await store.purgeAccountData(accountId);

    expect(await store.hasPurgeIntent(accountId)).toBe(false);
  });
});

describe("deleted account fence", () => {
  it("refuses to recreate a purged account when a sign-in still holds valid tokens", async () => {
    const sql = await setupTestDatabase();
    const store = new AccountStore(sql);
    const accountId = randomUUID();
    await seedAccount(sql, accountId, "fenced");

    await store.purgeAccountData(accountId);
    expect(await store.hasAccountTombstone(accountId)).toBe(true);

    await expect(store.upsert({ id: accountId, displayName: "Recreated" })).rejects.toBeInstanceOf(AccountDeletedError);

    expect(await store.getById(accountId)).toBeNull();
    expect(await countsFor(sql, accountId)).toEqual(ZERO);
  });

  it("refuses an owned upload for an account that was recreated after a purge", async () => {
    const sql = await setupTestDatabase();
    const store = new AccountStore(sql);
    const accountId = randomUUID();
    await seedAccount(sql, accountId, "fenced-upload");

    await store.purgeAccountData(accountId);
    await expect(store.upsert({ id: accountId, displayName: "Recreated" })).rejects.toBeInstanceOf(AccountDeletedError);

    await expect(
      new ExtractionJobStore(sql).enqueue({
        sourceImageBase64: "c291cmNl",
        sourceMimeType: "image/png",
        ownerAccountId: accountId
      })
    ).rejects.toThrow(/Account no longer exists/);
    expect(await countsFor(sql, accountId)).toEqual(ZERO);
  });

  it("keeps the tombstone only when the purge commits", async () => {
    const sql = await setupTestDatabase();
    const store = new AccountStore(sql);
    const accountId = randomUUID();
    await seedAccount(sql, accountId, "rollback-fence");

    await expect(
      store.purgeAccountData(accountId, {
        onRowsLocked: async () => {
          throw new Error("purge aborted mid-transaction");
        }
      })
    ).rejects.toThrow("purge aborted mid-transaction");

    expect(await store.hasAccountTombstone(accountId)).toBe(false);
    await expect(store.upsert({ id: accountId, displayName: "Still here" })).resolves.toMatchObject({ id: accountId });
  });

  it("still lets a live account sign in and be purged afterwards", async () => {
    const sql = await setupTestDatabase();
    const store = new AccountStore(sql);
    const accountId = randomUUID();

    await expect(store.upsert({ id: accountId, displayName: "Live" })).resolves.toMatchObject({ id: accountId });
    await store.purgeAccountData(accountId);
    expect(await store.getById(accountId)).toBeNull();
  });
});

describe("sweepStaleAccountPurges", () => {
  it("resumes a purge whose intent is older than the grace window and drains the object keys", async () => {
    const sql = await setupTestDatabase();
    const store = new AccountStore(sql);
    const outbox = new ObjectDeletionOutbox(sql);
    const accountId = randomUUID();
    const keys = await seedAccount(sql, accountId, "stale");

    await store.recordPurgeIntent(accountId);
    await sql`UPDATE pending_account_purges SET requested_at = NOW() - interval '6 minutes'`;

    const deleteObject = vi.fn(async () => undefined);
    const result = await sweepStaleAccountPurges({ accountStore: store, outbox, deleteObject });

    expect(result.purgedAccounts).toEqual([accountId]);
    expect(await countsFor(sql, accountId)).toEqual(ZERO);
    expect(await outbox.count()).toBe(0);
    expect(deleteObject).toHaveBeenCalledTimes(keys.length);
  });

  it("leaves a fresh intent and its account alone", async () => {
    const sql = await setupTestDatabase();
    const store = new AccountStore(sql);
    const outbox = new ObjectDeletionOutbox(sql);
    const accountId = randomUUID();
    await seedAccount(sql, accountId, "fresh");
    await store.recordPurgeIntent(accountId);

    const deleteObject = vi.fn(async () => undefined);
    const result = await sweepStaleAccountPurges({ accountStore: store, outbox, deleteObject });

    expect(result.purgedAccounts).toEqual([]);
    expect(await store.hasPurgeIntent(accountId)).toBe(true);
    expect(await countsFor(sql, accountId)).toMatchObject({ accounts: 1, extraction_jobs: 3 });
    expect(deleteObject).not.toHaveBeenCalled();
  });

  it("is a no-op when there is nothing to resume and nothing queued", async () => {
    const sql = await setupTestDatabase();
    const store = new AccountStore(sql);
    const outbox = new ObjectDeletionOutbox(sql);
    const deleteObject = vi.fn(async () => undefined);

    const result = await sweepStaleAccountPurges({ accountStore: store, outbox, deleteObject });

    expect(result).toEqual({
      purgedAccounts: [],
      failedAccounts: [],
      abandonedAttempts: 0,
      drain: { deleted: 0, failed: 0 }
    });
    expect(deleteObject).not.toHaveBeenCalled();
  });

  it("retries keys left behind by an earlier storage failure", async () => {
    const sql = await setupTestDatabase();
    const store = new AccountStore(sql);
    const outbox = new ObjectDeletionOutbox(sql);
    const accountId = randomUUID();
    await seedAccount(sql, accountId, "retry");
    await store.purgeAccountData(accountId, {
      resolveObjectKey: (locator) => objectKeyFromLocator(locator, R2_PUBLIC_URL)
    });

    const failing = vi.fn(async () => {
      throw new Error("R2 unavailable");
    });
    await drainPendingObjectDeletions({ outbox, deleteObject: failing });
    expect(await outbox.count()).toBe(6);

    const result = await sweepStaleAccountPurges({
      accountStore: store,
      outbox,
      deleteObject: async () => undefined
    });
    expect(result.drain).toEqual({ deleted: 6, failed: 0 });
    expect(await outbox.count()).toBe(0);
  });
});

describe.runIf(TEST_DATABASE_URL)("account purge against real Postgres", () => {
  async function bootstrap(accountId: string, extra?: (sql: Sql) => Promise<void>) {
    const admin = createDatabase(TEST_DATABASE_URL as string);
    await applySchema(admin);
    await admin`INSERT INTO accounts (id, display_name) VALUES (${accountId}, ${accountId})`;
    if (extra) await extra(admin);
    return admin;
  }

  /** Removes everything a gated test created, so the shared database keeps no residue. */
  async function cleanup(
    sql: Sql,
    accountId: string,
    objectKeys: readonly string[] = [],
    jobIds: readonly string[] = []
  ): Promise<void> {
    for (const key of objectKeys) {
      await sql`DELETE FROM pending_object_deletions WHERE key = ${key}`;
    }
    for (const jobId of jobIds) {
      await sql`DELETE FROM extraction_jobs WHERE id = ${jobId}`;
    }
    await sql`DELETE FROM extraction_jobs WHERE owner_account_id = ${accountId}`;
    await sql`DELETE FROM saved_entries WHERE account_id = ${accountId}`;
    await sql`DELETE FROM poses WHERE owner_account_id = ${accountId}`;
    await sql`DELETE FROM pending_account_purges WHERE account_id = ${accountId}`;
    await sql`DELETE FROM deleted_accounts WHERE account_id = ${accountId}`;
    await sql`DELETE FROM accounts WHERE id = ${accountId}`;
  }

  it("keeps a pose finalized while the purge waited for the job row lock", async () => {
    const accountId = randomUUID();
    const jobId = randomUUID();
    const poseId = randomUUID();
    const lockToken = randomUUID();
    const locators = ["original", "skeleton", "thumbnail"].map(
      (role) => `${R2_PUBLIC_URL}/poses/${poseId}/${role}.png`
    );

    const admin = await bootstrap(accountId, async (sql) => {
      await sql`INSERT INTO extraction_jobs (id, status, source_mime_type, owner_account_id, attempts, lock_token, locked_at)
        VALUES (${jobId}, 'processing', 'image/png', ${accountId}, 1, ${lockToken}, NOW())`;
    });
    const workerConn = createDatabase(TEST_DATABASE_URL as string);
    const purgeConn = createDatabase(TEST_DATABASE_URL as string);

    try {
      const workerStore = new ExtractionJobStore(workerConn);
      let committed!: () => void;
      const committedP = new Promise<void>((resolve) => {
        committed = resolve;
      });
      let release!: () => void;
      const releaseP = new Promise<void>((resolve) => {
        release = resolve;
      });

      const communityStore = new PoseStore(workerConn);
      const workerTx = workerConn.begin(async (tx) => {
        // Production order: the pose and its media are written first, then the job row is
        // finalized. The purge therefore blocks on the job row only after the pose exists.
        await communityStore.createPose(
          {
            poseId,
            ownerAccountId: accountId,
            name: "Late Pose",
            originalUrl: locators[0]!,
            skeletonUrl: locators[1]!,
            thumbnailUrl: locators[2]!,
            tags: [],
            difficulty: null,
            description: null,
            bodyParts: [],
            currentJobId: jobId
          },
          tx
        );
        await workerStore.markSucceededWithPose(tx, jobId, lockToken, poseId);
        committed();
        await releaseP;
      });
      await committedP;

      const purgeStore = new AccountStore(purgeConn);
      let purgeSettled = false;
      const purgeP = purgeStore
        .purgeAccountData(accountId, { resolveObjectKey: (locator) => objectKeyFromLocator(locator, R2_PUBLIC_URL) })
        .then((keys) => {
          purgeSettled = true;
          return keys;
        });

      await new Promise((resolve) => setTimeout(resolve, 200));
      expect(purgeSettled).toBe(false);

      release();
      await workerTx;
      const keys = await purgeP;

      expect([...keys].sort()).toEqual(
        locators.map((locator) => objectKeyFromLocator(locator, R2_PUBLIC_URL)).sort()
      );
      const poseRows = (await admin`SELECT COUNT(*)::int AS count FROM poses WHERE owner_account_id = ${accountId}`) as Array<{
        count: number;
      }>;
      expect(poseRows[0]?.count).toBe(0);
      const outboxKeys = (await new ObjectDeletionOutbox(admin).list())
        .map((row) => row.key)
        .filter((key) => key.startsWith(`poses/${poseId}/`))
        .sort();
      expect(outboxKeys).toEqual([...keys].sort());
    } finally {
      await cleanup(
        admin,
        accountId,
        locators.map((locator) => objectKeyFromLocator(locator, R2_PUBLIC_URL))
      );
      await admin.end();
      await workerConn.end();
      await purgeConn.end();
    }
  });

  it("blocks a finalize that starts after the purge, and that finalize must roll back", async () => {
    const accountId = randomUUID();
    const jobId = randomUUID();
    const poseId = randomUUID();
    const lockToken = randomUUID();

    const admin = await bootstrap(accountId, async (sql) => {
      await sql`INSERT INTO extraction_jobs (id, status, source_mime_type, owner_account_id, attempts, lock_token, locked_at)
        VALUES (${jobId}, 'processing', 'image/png', ${accountId}, 1, ${lockToken}, NOW())`;
    });
    const workerConn = createDatabase(TEST_DATABASE_URL as string);
    const purgeConn = createDatabase(TEST_DATABASE_URL as string);

    try {
      const purgeStore = new AccountStore(purgeConn);
      let rowsLocked!: () => void;
      const rowsLockedP = new Promise<void>((resolve) => {
        rowsLocked = resolve;
      });
      let releasePurge!: () => void;
      const releasePurgeP = new Promise<void>((resolve) => {
        releasePurge = resolve;
      });

      const purgeP = purgeStore.purgeAccountData(accountId, {
        resolveObjectKey: (locator) => objectKeyFromLocator(locator, R2_PUBLIC_URL),
        onRowsLocked: async () => {
          rowsLocked();
          await releasePurgeP;
        }
      });
      await rowsLockedP;

      const workerStore = new ExtractionJobStore(workerConn);
      const workerCommunityStore = new PoseStore(workerConn);
      let workerSettled = false;
      const workerP = workerConn
        .begin(async (tx) => {
          await workerCommunityStore.createPose(
            {
              poseId,
              ownerAccountId: accountId,
              name: "Racing Pose",
              originalUrl: `${R2_PUBLIC_URL}/poses/${poseId}/original.png`,
              skeletonUrl: `${R2_PUBLIC_URL}/poses/${poseId}/skeleton.png`,
              thumbnailUrl: `${R2_PUBLIC_URL}/poses/${poseId}/thumbnail.png`,
              tags: [],
              difficulty: null,
              description: null,
              bodyParts: [],
              currentJobId: jobId
            },
            tx
          );
          await workerStore.markSucceededWithPose(tx, jobId, lockToken, poseId);
        })
        .then(() => {
          workerSettled = true;
        })
        .catch((error: unknown) => {
          workerSettled = true;
          throw error;
        });
      workerP.catch(() => undefined);

      await new Promise((resolve) => setTimeout(resolve, 200));
      expect(workerSettled).toBe(false);

      releasePurge();
      await purgeP;

      await expect(workerP).rejects.toBeInstanceOf(StaleLockError);
      const poseRows = (await admin`SELECT COUNT(*)::int AS count FROM poses WHERE owner_account_id = ${accountId}`) as Array<{
        count: number;
      }>;
      expect(poseRows[0]?.count).toBe(0);
    } finally {
      await cleanup(admin, accountId);
      await admin.end();
      await workerConn.end();
      await purgeConn.end();
    }
  });

  it("removes the uploaded objects of a finalize that lost the purge race", async () => {
    const accountId = randomUUID();
    const jobId = randomUUID();
    const lockToken = randomUUID();

    const admin = await bootstrap(accountId, async (sql) => {
      await sql`INSERT INTO extraction_jobs (id, status, source_mime_type, owner_account_id, attempts, lock_token, locked_at)
        VALUES (${jobId}, 'processing', 'image/png', ${accountId}, 1, ${lockToken}, NOW())`;
    });
    const workerConn = createDatabase(TEST_DATABASE_URL as string);

    try {
      const purgeStore = new AccountStore(createDatabase(TEST_DATABASE_URL as string));
      await purgeStore.purgeAccountData(accountId);

      const removed: string[] = [];
      const mediaStorage: MediaStorage = {
        put: async () => undefined,
        remove: async (key: string) => {
          removed.push(key);
        },
        publicUrl: (key: string) => `${R2_PUBLIC_URL}/${key}`
      };
      const workerStore = new ExtractionJobStore(workerConn);
      const communityStore = new PoseStore(workerConn);

      await expect(
        materializePose({
          poseId: randomUUID(),
          ownerAccountId: accountId,
          currentJobId: jobId,
          metadata: { name: "Lost Race" },
          source: { b64: Buffer.from("source").toString("base64"), mime: "image/png" },
          result: { b64: Buffer.from("result").toString("base64"), mime: "image/png" },
          keyPrefix: "poses",
          mediaStorage,
          createPose: (input) =>
            workerConn.begin(async (tx) => {
              const pose = await communityStore.createPose(input, tx);
              await workerStore.markSucceededWithPose(tx, jobId, lockToken, input.poseId ?? "x");
              return pose;
            })
        })
      ).rejects.toBeInstanceOf(StaleLockError);

      expect(removed).toHaveLength(3);
    } finally {
      await cleanup(admin, accountId);
      await admin.end();
      await workerConn.end();
    }
  });

  it("refuses an upload that arrives while the purge holds the account lock", async () => {
    const accountId = randomUUID();
    const admin = await bootstrap(accountId);
    const uploadConn = createDatabase(TEST_DATABASE_URL as string);
    const anonymousConn = createDatabase(TEST_DATABASE_URL as string);
    const purgeConn = createDatabase(TEST_DATABASE_URL as string);
    let anonymousJobId: string | undefined;

    try {
      const purgeStore = new AccountStore(purgeConn);
      let rowsLocked!: () => void;
      const rowsLockedP = new Promise<void>((resolve) => {
        rowsLocked = resolve;
      });
      let releasePurge!: () => void;
      const releasePurgeP = new Promise<void>((resolve) => {
        releasePurge = resolve;
      });

      const purgeP = purgeStore.purgeAccountData(accountId, {
        onRowsLocked: async () => {
          rowsLocked();
          await releasePurgeP;
        }
      });
      await rowsLockedP;

      const uploadStore = new ExtractionJobStore(uploadConn);
      let uploadSettled = false;
      const uploadP = uploadStore
        .enqueue({
          sourceImageBase64: "c291cmNl",
          sourceMimeType: "image/png",
          ownerAccountId: accountId
        })
        .then((job) => {
          uploadSettled = true;
          return { job };
        })
        .catch((error: unknown) => {
          uploadSettled = true;
          return { error };
        });
      const anonymousStore = new ExtractionJobStore(anonymousConn);
      const anonymousJob = await anonymousStore.enqueue({
        sourceImageBase64: "c291cmNl",
        sourceMimeType: "image/png"
      });
      anonymousJobId = anonymousJob.id;

      await new Promise((resolve) => setTimeout(resolve, 200));
      expect(uploadSettled).toBe(false);

      releasePurge();
      await purgeP;

      const outcome = (await uploadP) as { error?: Error };
      expect(outcome.error?.name).toBe("AccountGoneError");

      const ownedJobs = (await admin`
        SELECT COUNT(*)::int AS count FROM extraction_jobs WHERE owner_account_id = ${accountId}
      `) as Array<{ count: number }>;
      expect(ownedJobs[0]?.count).toBe(0);
      const anonymousRows = (await admin`
        SELECT id FROM extraction_jobs WHERE id = ${anonymousJob.id}
      `) as Array<{ id: string }>;
      expect(anonymousRows).toHaveLength(1);
      expect(uploadSettled).toBe(true);
    } finally {
      await cleanup(admin, accountId, [], anonymousJobId ? [anonymousJobId] : []);
      await admin.end();
      await uploadConn.end();
      await anonymousConn.end();
      await purgeConn.end();
    }
  });

  it("blocks a sign-in that arrives while the purge runs, then refuses it", async () => {
    const accountId = randomUUID();
    const admin = await bootstrap(accountId);
    const signInConn = createDatabase(TEST_DATABASE_URL as string);
    const purgeConn = createDatabase(TEST_DATABASE_URL as string);

    try {
      const purgeStore = new AccountStore(purgeConn);
      let rowsLocked!: () => void;
      const rowsLockedP = new Promise<void>((resolve) => {
        rowsLocked = resolve;
      });
      let releasePurge!: () => void;
      const releasePurgeP = new Promise<void>((resolve) => {
        releasePurge = resolve;
      });

      const purgeP = purgeStore.purgeAccountData(accountId, {
        onRowsLocked: async () => {
          rowsLocked();
          await releasePurgeP;
        }
      });
      await rowsLockedP;

      const signInStore = new AccountStore(signInConn);
      let signInSettled = false;
      const signInP = signInStore
        .upsert({ id: accountId, displayName: "Resumed Session" })
        .then((account) => {
          signInSettled = true;
          return { account };
        })
        .catch((error: unknown) => {
          signInSettled = true;
          return { error };
        });

      await new Promise((resolve) => setTimeout(resolve, 200));
      expect(signInSettled).toBe(false);

      releasePurge();
      await purgeP;

      const outcome = (await signInP) as { error?: Error };
      expect(outcome.error).toBeInstanceOf(AccountDeletedError);

      const rows = (await admin`SELECT id FROM accounts WHERE id = ${accountId}`) as Array<{ id: string }>;
      expect(rows).toHaveLength(0);
    } finally {
      await cleanup(admin, accountId);
      await admin.end();
      await signInConn.end();
      await purgeConn.end();
    }
  });

  it("keeps an account that signed in before the purge started", async () => {
    const accountId = randomUUID();
    const admin = createDatabase(TEST_DATABASE_URL as string);
    const signInConn = createDatabase(TEST_DATABASE_URL as string);

    try {
      const signInStore = new AccountStore(signInConn);
      await signInStore.upsert({ id: accountId, displayName: "Before Purge" });
      await signInStore.upsert({ id: accountId, displayName: "Before Purge Again" });

      await new AccountStore(createDatabase(TEST_DATABASE_URL as string)).purgeAccountData(accountId);

      const rows = (await admin`SELECT id FROM accounts WHERE id = ${accountId}`) as Array<{ id: string }>;
      expect(rows).toHaveLength(0);
      await expect(signInStore.upsert({ id: accountId, displayName: "Too Late" })).rejects.toBeInstanceOf(
        AccountDeletedError
      );
    } finally {
      await cleanup(admin, accountId);
      await admin.end();
      await signInConn.end();
    }
  });

  it("deletes a job that committed before the purge started", async () => {
    const accountId = randomUUID();
    const admin = await bootstrap(accountId);
    const uploadConn = createDatabase(TEST_DATABASE_URL as string);

    try {
      const uploadStore = new ExtractionJobStore(uploadConn);
      const job = await uploadStore.enqueue({
        sourceImageBase64: "c291cmNl",
        sourceMimeType: "image/png",
        ownerAccountId: accountId
      });

      await new AccountStore(createDatabase(TEST_DATABASE_URL as string)).purgeAccountData(accountId);

      const rows = (await admin`SELECT id FROM extraction_jobs WHERE id = ${job.id}`) as Array<{ id: string }>;
      expect(rows).toHaveLength(0);
    } finally {
      await cleanup(admin, accountId);
      await admin.end();
      await uploadConn.end();
    }
  });
});
