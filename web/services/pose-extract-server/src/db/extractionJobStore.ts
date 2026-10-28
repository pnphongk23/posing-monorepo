import { randomUUID } from "node:crypto";

import type { Sql, SqlOrTx } from "./connection";
import { pgTimestamp } from "./pgTypes";

export type ExtractionJobStatus = "queued" | "processing" | "succeeded" | "failed";

export interface PoseDraft {
  name: string;
  tags: string[];
  description: string | null;
}

export interface ExtractionJob {
  id: string;
  status: ExtractionJobStatus;
  sourceImageBase64: string | null;
  sourceMimeType: string;
  resultImageBase64: string | null;
  resultMimeType: string | null;
  errorCode: string | null;
  errorMessage: string | null;
  attempts: number;
  maxAttempts: number;
  lockedAt: string | null;
  lockToken: string | null;
  createdAt: string;
  updatedAt: string;
  ownerAccountId: string | null;
  poseDraft: PoseDraft | null;
  poseId: string | null;
  hiddenAt: string | null;
}

export interface ExtractionJobListItem extends ExtractionJob {
  thumbnailUrl: string | null;
}

export interface ListByOwnerOptions {
  state?: "active" | "finished";
  limit?: number;
  cursor?: string | null;
}

export interface ListByOwnerResult {
  jobs: ExtractionJobListItem[];
  nextCursor: string | null;
}

/** The signed-in owner has no account row any more, so the upload must not be stored. */
export class AccountGoneError extends Error {
  constructor(message = "Account no longer exists") {
    super(message);
    this.name = "AccountGoneError";
  }
}

export class StaleLockError extends Error {
  constructor(message = "Stale lock token on extraction job") {
    super(message);
    this.name = "StaleLockError";
  }
}

interface ExtractionJobRow {
  id: string;
  status: ExtractionJobStatus;
  source_image_base64: string | null;
  source_mime_type: string;
  result_image_base64: string | null;
  result_mime_type: string | null;
  error_code: string | null;
  error_message: string | null;
  attempts: number;
  max_attempts: number;
  locked_at: Date | string | null;
  lock_token: string | null;
  created_at: Date | string;
  updated_at: Date | string;
  owner_account_id: string | null;
  pose_draft: PoseDraft | string | null;
  pose_id: string | null;
  hidden_at: Date | string | null;
}

interface ExtractionJobListItemRow extends ExtractionJobRow {
  thumbnail_url: string | null;
}

function encodeCursor(createdAt: string, id: string): string {
  return Buffer.from(`${createdAt}|${id}`).toString("base64url");
}

function decodeCursor(cursor: string): { createdAt: string; id: string } | null {
  try {
    const raw = Buffer.from(cursor, "base64url").toString("utf8");
    const separatorIdx = raw.indexOf("|");
    if (separatorIdx === -1) return null;
    const createdAt = raw.slice(0, separatorIdx);
    const id = raw.slice(separatorIdx + 1);
    if (!createdAt || !id) return null;
    const d = new Date(createdAt);
    if (Number.isNaN(d.getTime())) return null;
    return { createdAt, id };
  } catch {
    return null;
  }
}

export class ExtractionJobStore {
  constructor(private readonly db: Sql) {}

  async enqueue(input: {
    sourceImageBase64: string;
    sourceMimeType: string;
    maxAttempts?: number;
    ownerAccountId?: string;
    poseDraft?: PoseDraft;
  }): Promise<ExtractionJob> {
    const id = randomUUID();
    const poseDraftJson = input.poseDraft ? JSON.stringify(input.poseDraft) : null;
    const maxAttempts = input.maxAttempts ?? 3;

    // An owned upload is only admitted while the account row exists. The shared lock on
    // that row makes the insert wait for a running purge and then find nothing.
    const rows = input.ownerAccountId
      ? ((await this.db`
          WITH acct AS (
            SELECT id FROM accounts WHERE id = ${input.ownerAccountId} FOR KEY SHARE
          )
          INSERT INTO extraction_jobs (
            id,
            status,
            source_image_base64,
            source_mime_type,
            max_attempts,
            owner_account_id,
            pose_draft
          )
          SELECT
            ${id},
            'queued',
            ${input.sourceImageBase64},
            ${input.sourceMimeType},
            ${maxAttempts},
            acct.id,
            ${poseDraftJson}
          FROM acct
          RETURNING *
        `) as ExtractionJobRow[])
      : ((await this.db`
          INSERT INTO extraction_jobs (
            id,
            status,
            source_image_base64,
            source_mime_type,
            max_attempts,
            owner_account_id,
            pose_draft
          )
          VALUES (
            ${id},
            'queued',
            ${input.sourceImageBase64},
            ${input.sourceMimeType},
            ${maxAttempts},
            NULL,
            ${poseDraftJson}
          )
          RETURNING *
        `) as ExtractionJobRow[]);

    const job = rows[0];
    if (!job) {
      if (input.ownerAccountId) throw new AccountGoneError();
      throw new Error("Failed to enqueue extraction job");
    }
    return this.toJob(job);
  }

  async getById(id: string): Promise<ExtractionJob | null> {
    const rows = (await this.db`SELECT * FROM extraction_jobs WHERE id = ${id}`) as ExtractionJobRow[];
    const row = rows[0];
    return row ? this.toJob(row) : null;
  }

  async getByIdForOwner(id: string, ownerAccountId: string): Promise<ExtractionJob | null> {
    const rows = (await this.db`
      SELECT *
      FROM extraction_jobs
      WHERE id = ${id}
        AND owner_account_id = ${ownerAccountId}
        AND hidden_at IS NULL
    `) as ExtractionJobRow[];
    const row = rows[0];
    return row ? this.toJob(row) : null;
  }

  async listByOwner(ownerAccountId: string, options: ListByOwnerOptions = {}): Promise<ListByOwnerResult> {
    const stateCondition =
      options.state === "active"
        ? this.db` AND j.status IN ('queued', 'processing')`
        : options.state === "finished"
          ? this.db` AND j.status IN ('succeeded', 'failed')`
          : this.db``;

    const parsedCursor = options.cursor ? decodeCursor(options.cursor) : null;
    const cursorCondition = parsedCursor
      ? this.db` AND (j.created_at < ${parsedCursor.createdAt}::timestamptz OR (j.created_at = ${parsedCursor.createdAt}::timestamptz AND j.id < ${parsedCursor.id}))`
      : this.db``;

    const limit = options.limit && options.limit > 0 ? options.limit : 20;
    const fetchLimit = limit + 1;

    const rows = (await this.db`
      SELECT
        j.*,
        m.locator AS thumbnail_url
      FROM extraction_jobs j
      LEFT JOIN media_assets m ON m.pose_id = j.pose_id AND m.role = 'thumbnail'
      WHERE j.owner_account_id = ${ownerAccountId}
        AND j.hidden_at IS NULL
        ${stateCondition}
        ${cursorCondition}
      ORDER BY j.created_at DESC, j.id DESC
      LIMIT ${fetchLimit}
    `) as ExtractionJobListItemRow[];

    const hasMore = rows.length > limit;
    const pageRows = hasMore ? rows.slice(0, limit) : rows;

    const jobs = pageRows.map((row) => this.toListItem(row));
    const nextCursor =
      hasMore && pageRows.length > 0
        ? encodeCursor(jobs[jobs.length - 1].createdAt, jobs[jobs.length - 1].id)
        : null;

    return {
      jobs,
      nextCursor
    };
  }

  async retryFailed(id: string, ownerAccountId: string): Promise<"requeued" | "not_found" | "not_retryable"> {
    const updated = await this.db`
      UPDATE extraction_jobs
      SET status = 'queued',
          attempts = 0,
          error_code = NULL,
          error_message = NULL,
          lock_token = NULL,
          locked_at = NULL,
          updated_at = NOW()
      WHERE id = ${id}
        AND owner_account_id = ${ownerAccountId}
        AND status = 'failed'
        AND hidden_at IS NULL
        AND source_image_base64 IS NOT NULL
    `;

    if (updated.count > 0) {
      return "requeued";
    }

    const rows = (await this.db`
      SELECT id, owner_account_id, hidden_at, status, source_image_base64
      FROM extraction_jobs
      WHERE id = ${id}
    `) as Array<{
      id: string;
      owner_account_id: string | null;
      hidden_at: Date | string | null;
      status: ExtractionJobStatus;
      source_image_base64: string | null;
    }>;

    const row = rows[0];
    if (!row || row.owner_account_id !== ownerAccountId || row.hidden_at !== null) {
      return "not_found";
    }

    return "not_retryable";
  }

  async hide(id: string, ownerAccountId: string): Promise<boolean> {
    const updated = await this.db`
      UPDATE extraction_jobs
      SET hidden_at = COALESCE(hidden_at, NOW()),
          source_image_base64 = CASE WHEN status = 'failed' THEN NULL ELSE source_image_base64 END,
          updated_at = NOW()
      WHERE id = ${id}
        AND owner_account_id = ${ownerAccountId}
    `;
    return updated.count > 0;
  }

  async markSucceededWithPose(
    sql: SqlOrTx,
    id: string,
    lockToken: string,
    poseId: string
  ): Promise<void> {
    const result = await sql`
      UPDATE extraction_jobs
      SET status = 'succeeded',
          pose_id = ${poseId},
          source_image_base64 = NULL,
          result_image_base64 = NULL,
          error_code = NULL,
          error_message = NULL,
          lock_token = NULL,
          locked_at = NULL,
          updated_at = NOW()
      WHERE id = ${id} AND lock_token = ${lockToken}
    `;

    if (result.count !== 1) {
      throw new StaleLockError(`Failed to finalize job ${id}: lock token is stale or job does not exist`);
    }
  }

  async claimNext(lockToken: string, staleLockSeconds: number): Promise<ExtractionJob | null> {
    return this.db.begin(async (sql) => {
      const candidateRows = (await sql`
        SELECT id
        FROM extraction_jobs
        WHERE (
          status = 'queued'
          OR (
            status = 'processing'
            AND locked_at IS NOT NULL
            AND locked_at <= NOW() - (${staleLockSeconds} * interval '1 second')
          )
        )
        AND attempts < max_attempts
        ORDER BY created_at ASC
        FOR UPDATE SKIP LOCKED
        LIMIT 1
      `) as Array<{ id: string }>;

      const candidate = candidateRows[0];
      if (!candidate) {
        return null;
      }

      const updated = await sql`
        UPDATE extraction_jobs
        SET status = 'processing',
            attempts = attempts + 1,
            lock_token = ${lockToken},
            locked_at = NOW(),
            updated_at = NOW()
        WHERE id = ${candidate.id}
          AND (status = 'queued' OR status = 'processing')
      `;

      if (updated.count === 0) {
        return null;
      }

      const rows = (await sql`SELECT * FROM extraction_jobs WHERE id = ${candidate.id}`) as ExtractionJobRow[];
      const row = rows[0];
      return row ? this.toJob(row) : null;
    });
  }

  async markSucceeded(
    id: string,
    lockToken: string,
    resultImageBase64: string,
    resultMimeType: string
  ): Promise<void> {
    await this.db`
      UPDATE extraction_jobs
      SET status = 'succeeded',
          result_image_base64 = ${resultImageBase64},
          result_mime_type = ${resultMimeType},
          error_code = NULL,
          error_message = NULL,
          lock_token = NULL,
          locked_at = NULL,
          updated_at = NOW()
      WHERE id = ${id} AND lock_token = ${lockToken}
    `;
  }

  async markFailedOrRequeue(
    id: string,
    lockToken: string,
    errorCode: string,
    errorMessage: string
  ): Promise<void> {
    await this.db`
      UPDATE extraction_jobs
      SET status = CASE WHEN attempts >= max_attempts THEN 'failed' ELSE 'queued' END,
          error_code = ${errorCode},
          error_message = ${errorMessage},
          lock_token = NULL,
          locked_at = NULL,
          updated_at = NOW()
      WHERE id = ${id} AND lock_token = ${lockToken}
    `;
  }

  private toJob(row: ExtractionJobRow): ExtractionJob {
    let poseDraft: PoseDraft | null = null;
    if (row.pose_draft) {
      poseDraft = typeof row.pose_draft === "string" ? JSON.parse(row.pose_draft) : (row.pose_draft as PoseDraft);
    }
    return {
      id: row.id,
      status: row.status,
      sourceImageBase64: row.source_image_base64,
      sourceMimeType: row.source_mime_type,
      resultImageBase64: row.result_image_base64,
      resultMimeType: row.result_mime_type,
      errorCode: row.error_code,
      errorMessage: row.error_message,
      attempts: row.attempts,
      maxAttempts: row.max_attempts,
      lockedAt: pgTimestamp(row.locked_at),
      lockToken: row.lock_token,
      createdAt: pgTimestamp(row.created_at)!,
      updatedAt: pgTimestamp(row.updated_at)!,
      ownerAccountId: row.owner_account_id ?? null,
      poseDraft,
      poseId: row.pose_id ?? null,
      hiddenAt: pgTimestamp(row.hidden_at)
    };
  }

  private toListItem(row: ExtractionJobListItemRow): ExtractionJobListItem {
    return {
      ...this.toJob(row),
      thumbnailUrl: row.thumbnail_url ?? null
    };
  }
}
