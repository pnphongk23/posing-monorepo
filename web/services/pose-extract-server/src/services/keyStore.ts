import { randomUUID } from "node:crypto";

import type { Sql } from "../db/connection";
import { pgIntId, pgTimestamp } from "../db/pgTypes";

export type ApiKeyStatus = "active" | "disabled" | "exhausted";

export interface ApiKeyRecord {
  id: string;
  name: string;
  apiKey: string;
  status: ApiKeyStatus;
  requestsToday: number;
  createdAt: string;
  lastUsedAt: string | null;
}

export interface RequestLogRecord {
  id: number;
  keyId: string | null;
  timestamp: string;
  processingTimeMs: number | null;
  success: boolean;
  errorCode: string | null;
}

interface CreateApiKeyInput {
  name: string;
  apiKey: string;
}

interface ApiKeyRow {
  id: string;
  name: string;
  api_key: string;
  status: ApiKeyStatus;
  requests_today: number;
  created_at: Date | string;
  last_used_at: Date | string | null;
}

interface RequestLogRow {
  id: string | number;
  key_id: string | null;
  timestamp: Date | string;
  processing_time_ms: number | null;
  success: boolean;
  error_code: string | null;
}

interface LogRequestInput {
  keyId: string | null;
  processingTimeMs: number | null;
  success: boolean;
  errorCode: string | null;
}

export class KeyStore {
  constructor(private readonly db: Sql) {}

  async listKeys(): Promise<ApiKeyRecord[]> {
    const rows = (await this.db`
      SELECT id, name, api_key, status, requests_today, created_at, last_used_at
      FROM api_keys
      ORDER BY created_at ASC
    `) as ApiKeyRow[];

    return rows.map((row) => this.toRecord(row));
  }

  async createKey(input: CreateApiKeyInput): Promise<ApiKeyRecord> {
    const id = randomUUID();
    await this.db`
      INSERT INTO api_keys (id, name, api_key, status, requests_today)
      VALUES (${id}, ${input.name}, ${input.apiKey}, 'active', 0)
    `;

    const created = await this.getKeyById(id);
    if (!created) {
      throw new Error("Failed to create API key");
    }
    return created;
  }

  async updateKeyStatus(id: string, status: ApiKeyStatus): Promise<ApiKeyRecord | null> {
    const result = await this.db`UPDATE api_keys SET status = ${status} WHERE id = ${id}`;
    if (result.count === 0) {
      return null;
    }
    return this.getKeyById(id);
  }

  async deleteKey(id: string): Promise<boolean> {
    const result = await this.db`DELETE FROM api_keys WHERE id = ${id}`;
    return result.count > 0;
  }

  async incrementRequestsToday(id: string): Promise<void> {
    await this.db`
      UPDATE api_keys
      SET requests_today = requests_today + 1, last_used_at = NOW()
      WHERE id = ${id}
    `;
  }

  async resetDailyCounters(): Promise<number> {
    const result = await this.db`
      UPDATE api_keys
      SET requests_today = 0,
          status = CASE
            WHEN status = 'exhausted' THEN 'active'
            ELSE status
          END
    `;

    return result.count;
  }

  async logRequest(input: LogRequestInput): Promise<RequestLogRecord> {
    const rows = (await this.db`
      INSERT INTO request_logs (key_id, processing_time_ms, success, error_code)
      VALUES (${input.keyId}, ${input.processingTimeMs}, ${input.success}, ${input.errorCode})
      RETURNING id, key_id, timestamp, processing_time_ms, success, error_code
    `) as RequestLogRow[];

    const created = rows[0];
    if (!created) {
      throw new Error("Failed to log request");
    }

    return this.toRequestLogRecord(created);
  }

  async listRequestLogs(): Promise<RequestLogRecord[]> {
    const rows = (await this.db`
      SELECT id, key_id, timestamp, processing_time_ms, success, error_code
      FROM request_logs
      ORDER BY id ASC
    `) as RequestLogRow[];

    return rows.map((row) => this.toRequestLogRecord(row));
  }

  private async getKeyById(id: string): Promise<ApiKeyRecord | null> {
    const rows = (await this.db`
      SELECT id, name, api_key, status, requests_today, created_at, last_used_at
      FROM api_keys
      WHERE id = ${id}
    `) as ApiKeyRow[];

    const row = rows[0];
    return row ? this.toRecord(row) : null;
  }

  private toRecord(row: ApiKeyRow): ApiKeyRecord {
    return {
      id: row.id,
      name: row.name,
      apiKey: row.api_key,
      status: row.status,
      requestsToday: row.requests_today,
      createdAt: pgTimestamp(row.created_at)!,
      lastUsedAt: pgTimestamp(row.last_used_at)
    };
  }

  private toRequestLogRecord(row: RequestLogRow): RequestLogRecord {
    return {
      id: pgIntId(row.id),
      keyId: row.key_id,
      timestamp: pgTimestamp(row.timestamp)!,
      processingTimeMs: row.processing_time_ms,
      success: row.success,
      errorCode: row.error_code
    };
  }
}
