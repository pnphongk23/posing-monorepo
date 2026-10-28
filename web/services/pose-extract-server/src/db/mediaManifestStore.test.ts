import { randomUUID } from "node:crypto";

import { describe, expect, it } from "vitest";

import { applySchema, createDatabase, type Sql } from "./connection";
import { MEDIA_UPLOAD_HORIZON_SECONDS, MediaManifestStore } from "./mediaManifestStore";
import { setupTestDatabase } from "./testDb";

const TEST_DATABASE_URL = process.env.TEST_DATABASE_URL;

function keysFor(poseId: string): string[] {
  return ["original", "skeleton", "thumbnail"].map((role) => `poses/${poseId}/${role}.png`);
}

async function ticketsFor(sql: Sql, keys: readonly string[]) {
  const rows: Array<{ key: string; not_before: Date | string }> = [];
  for (const key of keys) {
    const found = (await sql`
      SELECT key, not_before FROM pending_object_deletions WHERE key = ${key}
    `) as Array<{ key: string; not_before: Date | string }>;
    rows.push(...found);
  }
  return rows;
}

describe("MediaManifestStore", () => {
  it("lets exactly one consumer own the attempt", async () => {
    const sql = await setupTestDatabase();
    const store = new MediaManifestStore(sql);
    const poseId = randomUUID();
    const jobId = randomUUID();

    const { createdAt } = await store.record({
      poseId,
      jobId,
      ownerAccountId: randomUUID(),
      keys: keysFor(poseId)
    });
    expect(Number.isNaN(Date.parse(createdAt))).toBe(false);

    await sql.begin(async (tx) => {
      expect(await store.consume(tx, poseId, jobId)).toBe(true);
    });
    expect(await store.consume(sql, poseId, jobId)).toBe(false);

    const otherPoseId = randomUUID();
    await store.record({ poseId: otherPoseId, jobId, ownerAccountId: randomUUID(), keys: keysFor(otherPoseId) });
    expect(await store.abandon(otherPoseId)).toBe(1);
    expect(await store.consume(sql, otherPoseId, jobId)).toBe(false);
    expect(await store.abandon(otherPoseId)).toBe(0);
  });

  it("turns an abandoned attempt into deletion tickets that wait for the horizon", async () => {
    const sql = await setupTestDatabase();
    const store = new MediaManifestStore(sql);
    const poseId = randomUUID();
    const keys = keysFor(poseId);
    const { createdAt } = await store.record({
      poseId,
      jobId: randomUUID(),
      ownerAccountId: randomUUID(),
      keys
    });

    expect(await store.abandon(poseId)).toBe(1);
    expect(await store.abandon(poseId)).toBe(0);

    const tickets = await ticketsFor(sql, keys);
    expect(tickets).toHaveLength(3);
    const expectedNotBefore = Date.parse(createdAt) + MEDIA_UPLOAD_HORIZON_SECONDS * 1000;
    for (const ticket of tickets) {
      const notBefore = ticket.not_before instanceof Date ? ticket.not_before.getTime() : Date.parse(String(ticket.not_before));
      expect(notBefore).toBeGreaterThanOrEqual(expectedNotBefore - 2000);
    }
  });

  it("sweeps only attempts older than the horizon", async () => {
    const sql = await setupTestDatabase();
    const store = new MediaManifestStore(sql);
    const staleId = randomUUID();
    const freshId = randomUUID();
    await store.record({ poseId: staleId, jobId: randomUUID(), ownerAccountId: randomUUID(), keys: keysFor(staleId) });
    await store.record({ poseId: freshId, jobId: randomUUID(), ownerAccountId: randomUUID(), keys: keysFor(freshId) });
    await sql`UPDATE pose_media_manifests SET created_at = NOW() - interval '2 hours' WHERE pose_id = ${staleId}`;

    expect(await store.abandonStale(10)).toBe(1);

    const remaining = (await sql`SELECT pose_id FROM pose_media_manifests`) as Array<{ pose_id: string }>;
    expect(remaining.map((row) => row.pose_id)).toEqual([freshId]);
    expect(await ticketsFor(sql, keysFor(staleId))).toHaveLength(3);
  });

  it("moves only the purged account's attempts", async () => {
    const sql = await setupTestDatabase();
    const store = new MediaManifestStore(sql);
    const accountA = randomUUID();
    const accountB = randomUUID();
    const poseA = randomUUID();
    const poseB = randomUUID();
    await store.record({ poseId: poseA, jobId: randomUUID(), ownerAccountId: accountA, keys: keysFor(poseA) });
    await store.record({ poseId: poseB, jobId: randomUUID(), ownerAccountId: accountB, keys: keysFor(poseB) });

    await sql.begin(async (tx) => {
      expect(await store.abandonForAccount(tx, accountA)).toBe(1);
    });

    expect(await store.abandon(poseA)).toBe(0);
    const remaining = (await sql`SELECT pose_id FROM pose_media_manifests`) as Array<{ pose_id: string }>;
    expect(remaining.map((row) => row.pose_id)).toEqual([poseB]);
    expect(await ticketsFor(sql, keysFor(poseA))).toHaveLength(3);
  });
});

describe.runIf(TEST_DATABASE_URL)("MediaManifestStore against real Postgres", () => {
  const PREFIX = `a01-manifest-${randomUUID()}`;
  const createdPoseIds: string[] = [];

  async function bootstrap(): Promise<Sql> {
    const sql = createDatabase(TEST_DATABASE_URL as string);
    await applySchema(sql);
    return sql;
  }

  async function cleanup(sql: Sql): Promise<void> {
    for (const poseId of createdPoseIds) {
      for (const key of keysFor(poseId)) {
        await sql`DELETE FROM pending_object_deletions WHERE key = ${key}`;
      }
      await sql`DELETE FROM pose_media_manifests WHERE pose_id = ${poseId}`;
    }
  }

  it("cannot be consumed or swept twice, whichever wins the row lock first", async () => {
    const first = await bootstrap();
    const second = await bootstrap();
    const consumeConn = await bootstrap();
    const poseId = randomUUID();
    createdPoseIds.push(poseId);
    let lockedConsume!: () => void;
    const consumeHeld = new Promise<void>((resolve) => {
      lockedConsume = resolve;
    });
    let releaseConsume!: () => void;
    const consumeRelease = new Promise<void>((resolve) => {
      releaseConsume = resolve;
    });

    try {
      const store = new MediaManifestStore(first);
      await store.record({
        poseId,
        jobId: randomUUID(),
        ownerAccountId: `${PREFIX}-owner`,
        keys: keysFor(poseId)
      });
      await first`UPDATE pose_media_manifests SET created_at = NOW() - interval '2 hours' WHERE pose_id = ${poseId}`;

      const consumingTx = consumeConn.begin(async (tx) => {
        expect(await store.consume(tx, poseId, (await tx`SELECT job_id FROM pose_media_manifests WHERE pose_id = ${poseId}`)[0]!.job_id as string)).toBe(true);
        lockedConsume();
        await consumeRelease;
      });
      await consumeHeld;

      const sweepStore = new MediaManifestStore(second);
      expect(await sweepStore.abandonStale(10)).toBe(0);

      releaseConsume();
      await consumingTx;
      expect(await sweepStore.abandonStale(10)).toBe(0);
      expect(await ticketsFor(first, keysFor(poseId))).toHaveLength(0);
    } finally {
      await cleanup(first);
      await first.end();
      await second.end();
      await consumeConn.end();
    }
  });

  it("gives the attempt to the sweep when the sweep wins first", async () => {
    const first = await bootstrap();
    const second = await bootstrap();
    const poseId = randomUUID();
    createdPoseIds.push(poseId);
    const jobId = randomUUID();

    try {
      const store = new MediaManifestStore(first);
      await store.record({ poseId, jobId, ownerAccountId: `${PREFIX}-owner`, keys: keysFor(poseId) });
      await first`UPDATE pose_media_manifests SET created_at = NOW() - interval '2 hours' WHERE pose_id = ${poseId}`;

      expect(await new MediaManifestStore(second).abandonStale(10)).toBe(1);
      expect(await store.consume(first, poseId, jobId)).toBe(false);
      expect(await ticketsFor(first, keysFor(poseId))).toHaveLength(3);
    } finally {
      await cleanup(first);
      await first.end();
      await second.end();
    }
  });
});
