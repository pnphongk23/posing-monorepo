import { randomUUID } from "node:crypto";

import type { Sql } from "./connection";
import { pgTimestamp } from "./pgTypes";

export type ExtractionJobStatus = "queued" | "processing" | "succeeded" | "failed";

export interface ExtractionJob {
  id: string;
  status: ExtractionJobStatus;
  sourceImageBase64: string;
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
}

interface ExtractionJobRow {
  id: string;
  status: ExtractionJobStatus;
  source_image_base64: string;
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
}

export class ExtractionJobStore {
  constructor(private readonly db: Sql) {}

  async enqueue(input: {
    sourceImageBase64: string;
    sourceMimeType: string;
    maxAttempts?: number;
  }): Promise<ExtractionJob> {
    const id = randomUUID();
    const rows = (await this.db`
      INSERT INTO extraction_jobs (id, status, source_image_base64, source_mime_type, max_attempts)
      VALUES (${id}, 'queued', ${input.sourceImageBase64}, ${input.sourceMimeType}, ${input.maxAttempts ?? 3})
      RETURNING *
    `) as ExtractionJobRow[];

    const job = rows[0];
    if (!job) throw new Error("Failed to enqueue extraction job");
    return this.toJob(job);
  }

  async getById(id: string): Promise<ExtractionJob | null> {
    const rows = (await this.db`SELECT * FROM extraction_jobs WHERE id = ${id}`) as ExtractionJobRow[];
    const row = rows[0];
    return row ? this.toJob(row) : null;
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
      updatedAt: pgTimestamp(row.updated_at)!
    };
  }
}
