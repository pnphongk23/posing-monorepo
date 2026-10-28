import type { Sql, SqlOrTx } from "./connection";
import { pgTimestamp } from "./pgTypes";

/** No manifest-derived key is deleted before `created_at + horizon`, and stale attempts are swept after it. */
export const MEDIA_UPLOAD_HORIZON_SECONDS = 3600;

/** A put must start within this window after its manifest was written. */
export const PUT_START_LIMIT_MS = 300_000;

/** Per-put request timeout for object storage. */
export const PUT_TIMEOUT_MS = 120_000;

/** The attempt's manifest was consumed by another owner (sweep, purge, or a competing finalize). */
export class MediaManifestLostError extends Error {
  constructor(message = "Media manifest was consumed before finalize") {
    super(message);
    this.name = "MediaManifestLostError";
  }
}

/** The upload window of this attempt closed; no further put may start. */
export class PutWindowClosedError extends Error {
  constructor(message = "Upload window closed before the object was written") {
    super(message);
    this.name = "PutWindowClosedError";
  }
}

interface RecordedManifestRow {
  created_at: Date | string;
}

/**
 * One row per owner job attempt, naming the object keys it may upload. Exactly one of
 * finalize, abandon, the stale sweep, or an account purge removes it, and moving its keys
 * into the deletion tickets happens in the same statement as that removal.
 */
export class MediaManifestStore {
  constructor(
    private readonly db: Sql,
    private readonly horizonSeconds: number = MEDIA_UPLOAD_HORIZON_SECONDS
  ) {}

  /** Before the first put. Returns the DB timestamp the upload window is measured from. */
  async record(input: { poseId: string; jobId: string; ownerAccountId: string; keys: string[] }): Promise<{ createdAt: string }> {
    const rows = (await this.db`
      INSERT INTO pose_media_manifests (pose_id, job_id, owner_account_id, object_keys)
      VALUES (${input.poseId}, ${input.jobId}, ${input.ownerAccountId}, ${input.keys})
      RETURNING created_at
    `) as RecordedManifestRow[];
    const row = rows[0];
    if (!row) throw new Error("Failed to record media manifest");
    return { createdAt: pgTimestamp(row.created_at)! };
  }

  /** Inside the finalize transaction. True only when this call removed the row. */
  async consume(sql: SqlOrTx, poseId: string, jobId: string): Promise<boolean> {
    const rows = (await sql`
      DELETE FROM pose_media_manifests
      WHERE pose_id = ${poseId} AND job_id = ${jobId}
      RETURNING pose_id
    `) as Array<{ pose_id: string }>;
    return rows.length === 1;
  }

  /** Worker failure path. Returns how many attempts were moved to deletion tickets. */
  async abandon(poseId: string): Promise<number> {
    const rows = (await this.db`
      WITH moved AS (
        DELETE FROM pose_media_manifests
        WHERE pose_id = ${poseId}
        RETURNING object_keys, created_at
      )
      , inserted AS (
        INSERT INTO pending_object_deletions (key, not_before)
        SELECT moved_key, GREATEST(NOW(), moved.created_at + (${this.horizonSeconds}::int * interval '1 second'))
        FROM moved, unnest(moved.object_keys) AS moved_key(object_key)
        ON CONFLICT (key) DO NOTHING
        RETURNING key
      )
      SELECT COUNT(*)::int AS moved FROM moved
    `) as Array<{ moved: number }>;
    return rows[0]?.moved ?? 0;
  }

  /** Periodic sweep: moves attempts older than the horizon into deletion tickets. */
  async abandonStale(limit = 100): Promise<number> {
    const rows = (await this.db`
      WITH moved AS (
        DELETE FROM pose_media_manifests
        WHERE pose_id IN (
          SELECT pose_id
          FROM pose_media_manifests
          WHERE created_at < NOW() - (${this.horizonSeconds}::int * interval '1 second')
          ORDER BY created_at
          LIMIT ${limit}
          FOR UPDATE SKIP LOCKED
        )
        RETURNING object_keys, created_at
      )
      , inserted AS (
        INSERT INTO pending_object_deletions (key, not_before)
        SELECT moved_key, GREATEST(NOW(), moved.created_at + (${this.horizonSeconds}::int * interval '1 second'))
        FROM moved, unnest(moved.object_keys) AS moved_key(object_key)
        ON CONFLICT (key) DO NOTHING
        RETURNING key
      )
      SELECT COUNT(*)::int AS moved FROM moved
    `) as Array<{ moved: number }>;
    return rows[0]?.moved ?? 0;
  }

  /** Inside the account purge transaction: queues the keys of every attempt of this account. */
  async abandonForAccount(sql: SqlOrTx, accountId: string): Promise<number> {
    const rows = (await sql`
      WITH moved AS (
        DELETE FROM pose_media_manifests
        WHERE owner_account_id = ${accountId}
        RETURNING object_keys, created_at
      )
      , inserted AS (
        INSERT INTO pending_object_deletions (key, not_before)
        SELECT moved_key, GREATEST(NOW(), moved.created_at + (${this.horizonSeconds}::int * interval '1 second'))
        FROM moved, unnest(moved.object_keys) AS moved_key(object_key)
        ON CONFLICT (key) DO NOTHING
        RETURNING key
      )
      SELECT COUNT(*)::int AS moved FROM moved
    `) as Array<{ moved: number }>;
    return rows[0]?.moved ?? 0;
  }
}
