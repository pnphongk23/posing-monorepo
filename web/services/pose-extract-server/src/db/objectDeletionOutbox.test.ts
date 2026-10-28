import { randomUUID } from "node:crypto";

import { describe, expect, it, vi } from "vitest";

import { createDatabase } from "./connection";
import {
  ObjectDeletionOutbox,
  drainPendingObjectDeletions,
  isObjectNotFoundError
} from "./objectDeletionOutbox";
import { setupTestDatabase } from "./testDb";

const TEST_DATABASE_URL = process.env.TEST_DATABASE_URL;

function notFoundError(): Error {
  return Object.assign(new Error("NoSuchKey"), {
    name: "NoSuchKey",
    $metadata: { httpStatusCode: 404 }
  });
}

describe("ObjectDeletionOutbox", () => {
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
    expect([...first].sort()).toEqual(["k1", "k2"]);

    const second = await outbox.claim(2);
    expect(second).toEqual(["k3"]);

    const third = await outbox.claim(2);
    expect(third).toEqual([]);
  });

  it("hands out a key again once its claim has expired", async () => {
    const sql = await setupTestDatabase();
    const outbox = new ObjectDeletionOutbox(sql);
    await outbox.enqueue(["stale-claim"]);
    expect(await outbox.claim(10)).toEqual(["stale-claim"]);

    await sql`UPDATE pending_object_deletions SET claimed_until = NOW() - interval '1 second'`;
    expect(await outbox.claim(10)).toEqual(["stale-claim"]);
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
    const accountId = randomUUID();
    const keys = Array.from({ length: 50 }, () => `${accountId}/${randomUUID()}`);

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
      expect(await new ObjectDeletionOutbox(admin).count()).toBe(0);
    } finally {
      await admin.end();
      await second.end();
    }
  });
});
