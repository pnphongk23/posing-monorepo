import { randomUUID } from "node:crypto";

import type { Sql, SqlOrTx } from "./connection";
import { pgTimestamp } from "./pgTypes";

export interface PendingObjectDeletion {
  key: string;
  enqueuedAt: string;
  attempts: number;
  claimedUntil: string | null;
  claimToken: string | null;
  lastError: string | null;
}

export interface ClaimedObjectKey {
  key: string;
  claimToken: string;
}

export interface DrainObjectDeletionsResult {
  deleted: number;
  failed: number;
}

export interface DrainObjectDeletionsOptions {
  outbox: ObjectDeletionOutbox;
  deleteObject: (key: string) => Promise<void>;
  limit?: number;
}

export const DEFAULT_DRAIN_LIMIT = 200;

/** Claims are time-boxed so a replica that dies mid-drain cannot strand an object key. */
const CLAIM_TTL_MINUTES = 5;

/** A reservation hides keys that are still being uploaded from the sweep. */
export const DEFAULT_RESERVATION_SECONDS = 1800;

interface OutboxRow {
  key: string;
  enqueued_at: Date | string;
  attempts: number;
  claimed_until: Date | string | null;
  claim_token: string | null;
  last_error: string | null;
}

function toEntry(row: OutboxRow): PendingObjectDeletion {
  return {
    key: row.key,
    enqueuedAt: pgTimestamp(row.enqueued_at)!,
    attempts: row.attempts,
    claimedUntil: pgTimestamp(row.claimed_until),
    claimToken: row.claim_token,
    lastError: row.last_error
  };
}

/**
 * Durable list of object-storage keys that must disappear once their owning rows are
 * gone. Keys are claimed atomically, so overlapping drains (a request drain and the
 * periodic sweep, or two replicas) never act on the same key twice.
 */
export class ObjectDeletionOutbox {
  constructor(private readonly db: Sql) {}

  async enqueue(keys: readonly string[]): Promise<void> {
    const uniqueKeys = [...new Set(keys.filter((key) => typeof key === "string" && key.length > 0))];
    for (const key of uniqueKeys) {
      await this.db`
        INSERT INTO pending_object_deletions (key)
        VALUES (${key})
        ON CONFLICT (key) DO NOTHING
      `;
    }
  }

  /**
   * Durably records keys that are not uploaded yet. The reservation keeps them out of the
   * sweep until they either become live objects (see ackKeys) or are retried after it expires.
   */
  async reserve(keys: readonly string[], ttlSeconds: number = DEFAULT_RESERVATION_SECONDS): Promise<void> {
    const uniqueKeys = [...new Set(keys.filter((key) => typeof key === "string" && key.length > 0))];
    for (const key of uniqueKeys) {
      await this.db`
        INSERT INTO pending_object_deletions (key, claimed_until)
        VALUES (${key}, NOW() + (${ttlSeconds}::int * interval '1 second'))
        ON CONFLICT (key) DO NOTHING
      `;
    }
  }

  /**
   * Removes rows whose objects the caller now owns. Used inside the finalize transaction so
   * the acknowledgement commits or rolls back with the pose that references the objects.
   */
  async ackKeys(sql: SqlOrTx, keys: readonly string[]): Promise<void> {
    for (const key of keys) {
      await sql`DELETE FROM pending_object_deletions WHERE key = ${key}`;
    }
  }

  /**
   * Claims a batch with a token. A drain that lost its claim (expired and re-claimed by
   * another drain) can no longer acknowledge rows that now belong to someone else.
   */
  async claim(limit: number = DEFAULT_DRAIN_LIMIT): Promise<ClaimedObjectKey[]> {
    const claimToken = randomUUID();
    const rows = (await this.db`
      UPDATE pending_object_deletions
      SET claimed_until = NOW() + (${CLAIM_TTL_MINUTES}::int * interval '1 minute'),
          claim_token = ${claimToken}
      WHERE key IN (
        SELECT key
        FROM pending_object_deletions
        WHERE claimed_until IS NULL OR claimed_until < NOW()
        ORDER BY enqueued_at ASC
        LIMIT ${limit}
        FOR UPDATE SKIP LOCKED
      )
      RETURNING key
    `) as Array<{ key: string }>;
    return rows.map((row) => ({ key: row.key, claimToken }));
  }

  async markDeleted(key: string, claimToken?: string | null): Promise<void> {
    await this.db`
      DELETE FROM pending_object_deletions
      WHERE key = ${key} AND claim_token IS NOT DISTINCT FROM ${claimToken ?? null}::text
    `;
  }

  async markFailed(key: string, claimToken: string | null, errorMessage: string): Promise<void> {
    await this.db`
      UPDATE pending_object_deletions
      SET attempts = attempts + 1,
          last_error = ${errorMessage},
          claimed_until = NULL,
          claim_token = NULL
      WHERE key = ${key} AND claim_token IS NOT DISTINCT FROM ${claimToken}::text
    `;
  }

  async list(): Promise<PendingObjectDeletion[]> {
    const rows = (await this.db`
      SELECT key, enqueued_at, attempts, claimed_until, claim_token, last_error
      FROM pending_object_deletions
      ORDER BY enqueued_at ASC, key ASC
    `) as OutboxRow[];
    return rows.map(toEntry);
  }

  async count(): Promise<number> {
    const rows = (await this.db`
      SELECT COUNT(*)::int AS count FROM pending_object_deletions
    `) as Array<{ count: number }>;
    return rows[0]?.count ?? 0;
  }
}

function errorMessageOf(error: unknown): string {
  if (error instanceof Error && error.message) return error.message;
  if (typeof error === "string" && error) return error;
  return "Unknown object deletion failure";
}

/**
 * An object storage client reports a missing key in more than one shape: the AWS SDK
 * uses $metadata.httpStatusCode, some wrappers use a plain statusCode/status.
 */
export function isObjectNotFoundError(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const candidate = error as {
    name?: unknown;
    status?: unknown;
    statusCode?: unknown;
    $metadata?: { httpStatusCode?: unknown };
  };
  const statuses = [candidate.$metadata?.httpStatusCode, candidate.statusCode, candidate.status];
  if (statuses.some((status) => Number(status) === 404)) return true;
  return candidate.name === "NoSuchKey" || candidate.name === "NotFound";
}

/**
 * Deletes every claimable key. A missing object counts as deleted. Any other failure
 * keeps the row with attempts and the error message so a later drain retries it.
 */
export async function drainPendingObjectDeletions(
  options: DrainObjectDeletionsOptions
): Promise<DrainObjectDeletionsResult> {
  const claims = await options.outbox.claim(options.limit);
  let deleted = 0;
  let failed = 0;

  for (const { key, claimToken } of claims) {
    try {
      await options.deleteObject(key);
      await options.outbox.markDeleted(key, claimToken);
      deleted += 1;
    } catch (error) {
      if (isObjectNotFoundError(error)) {
        await options.outbox.markDeleted(key, claimToken);
        deleted += 1;
        continue;
      }
      failed += 1;
      await options.outbox.markFailed(key, claimToken, errorMessageOf(error));
    }
  }

  return { deleted, failed };
}
