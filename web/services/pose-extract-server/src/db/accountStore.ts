import type { Sql, SqlOrTx } from "./connection";
import {
  ObjectDeletionOutbox,
  drainPendingObjectDeletions,
  type DrainObjectDeletionsResult
} from "./objectDeletionOutbox";
import { logger } from "../utils/logger";

export interface AccountRecord {
  id: string;
  displayName: string;
  createdAt: string;
}

interface AccountRow {
  id: string;
  display_name: string;
  created_at: Date | string;
}

function toAccount(row: AccountRow): AccountRecord {
  return {
    id: row.id,
    displayName: row.display_name,
    createdAt: row.created_at instanceof Date ? row.created_at.toISOString() : String(row.created_at)
  };
}

/** Turns a stored media locator into the object key the storage client expects. */
export function objectKeyFromLocator(locator: string, r2PublicUrl?: string): string {
  if (!r2PublicUrl) return locator;
  try {
    const locatorUrl = new URL(locator);
    const publicUrl = new URL(r2PublicUrl);
    if (locatorUrl.origin !== publicUrl.origin) return locator;
    const prefix = r2PublicUrl.replace(/\/$/, "");
    if (!locator.startsWith(prefix)) return locator;
    return locator.slice(prefix.length).replace(/^\/+/, "");
  } catch {
    return locator;
  }
}

export interface PurgeAccountOptions {
  /** Maps a stored locator to a storage key. Defaults to the locator itself. */
  resolveObjectKey?: (locator: string) => string;
  /** Observation point: runs while the account and job rows are locked, before media keys are collected. */
  onRowsLocked?: (transaction: SqlOrTx) => void | Promise<void>;
}

export interface SweepStaleAccountPurgesOptions {
  accountStore: AccountStore;
  outbox: ObjectDeletionOutbox;
  deleteObject: (key: string) => Promise<void>;
  /** An intent younger than this is left alone so the request that wrote it can finish. */
  olderThanSeconds?: number;
  drainLimit?: number;
  resolveObjectKey?: (locator: string) => string;
}

export interface SweepStaleAccountPurgesResult {
  purgedAccounts: string[];
  failedAccounts: string[];
  drain: DrainObjectDeletionsResult;
}

const DEFAULT_PURGE_GRACE_SECONDS = 300;

export class AccountStore {
  readonly objectDeletions: ObjectDeletionOutbox;

  constructor(private readonly db: Sql) {
    this.objectDeletions = new ObjectDeletionOutbox(db);
  }

  async upsert(input: { id: string; displayName: string }): Promise<AccountRecord> {
    const rows = (await this.db`
      INSERT INTO accounts (id, display_name)
      VALUES (${input.id}, ${input.displayName})
      ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name
      RETURNING id, display_name, created_at
    `) as AccountRow[];
    if (!rows[0]) throw new Error("Failed to upsert account");
    return toAccount(rows[0]);
  }

  async getById(id: string): Promise<AccountRecord | null> {
    const rows = (await this.db`
      SELECT id, display_name, created_at FROM accounts WHERE id = ${id}
    `) as AccountRow[];
    return rows[0] ? toAccount(rows[0]) : null;
  }

  async getOwnedMediaLocators(accountId: string): Promise<string[]> {
    const rows = (await this.db`
      SELECT media_assets.locator
      FROM media_assets
      JOIN poses ON poses.pose_id = media_assets.pose_id
      WHERE poses.owner_account_id = ${accountId}
    `) as Array<{ locator: string }>;
    return rows.map((row) => row.locator);
  }

  /**
   * Records that the identity provider already confirmed the user is gone. Only then is
   * the row data purged, so an interrupted deletion can be resumed by the sweeper.
   */
  async recordPurgeIntent(accountId: string): Promise<void> {
    await this.db`
      INSERT INTO pending_account_purges (account_id)
      VALUES (${accountId})
      ON CONFLICT (account_id) DO NOTHING
    `;
  }

  async hasPurgeIntent(accountId: string): Promise<boolean> {
    const rows = (await this.db`
      SELECT 1 AS present FROM pending_account_purges WHERE account_id = ${accountId}
    `) as Array<{ present: number }>;
    return rows.length > 0;
  }

  async listStalePurgeIntents(olderThanSeconds: number): Promise<string[]> {
    const rows = (await this.db`
      SELECT account_id
      FROM pending_account_purges
      WHERE requested_at <= NOW() - (${olderThanSeconds}::int * interval '1 second')
      ORDER BY requested_at ASC
    `) as Array<{ account_id: string }>;
    return rows.map((row) => row.account_id);
  }

  /**
   * Removes every row an account owns in one transaction and hands the media object keys
   * to the deletion outbox. The account row is locked first, so an upload admitted
   * afterwards waits and then finds no account, while a finalize that already holds a job
   * row is awaited and its committed pose is collected here.
   */
  async purgeAccountData(accountId: string, options: PurgeAccountOptions = {}): Promise<string[]> {
    const resolveObjectKey = options.resolveObjectKey ?? ((locator: string) => locator);

    return this.db.begin(async (transaction) => {
      await transaction`SELECT 1 FROM accounts WHERE id = ${accountId} FOR UPDATE`;
      await transaction`SELECT id FROM extraction_jobs WHERE owner_account_id = ${accountId} FOR UPDATE`;

      if (options.onRowsLocked) {
        await options.onRowsLocked(transaction);
      }

      const mediaRows = (await transaction`
        SELECT media_assets.locator
        FROM media_assets
        JOIN poses ON poses.pose_id = media_assets.pose_id
        WHERE poses.owner_account_id = ${accountId}
      `) as Array<{ locator: string }>;

      const objectKeys = [...new Set(mediaRows.map((row) => resolveObjectKey(row.locator)))];
      for (const key of objectKeys) {
        await transaction`
          INSERT INTO pending_object_deletions (key)
          VALUES (${key})
          ON CONFLICT (key) DO NOTHING
        `;
      }

      await transaction`DELETE FROM extraction_jobs WHERE owner_account_id = ${accountId}`;
      await transaction`DELETE FROM saved_entries WHERE account_id = ${accountId}`;
      await transaction`DELETE FROM poses WHERE owner_account_id = ${accountId}`;
      await transaction`DELETE FROM accounts WHERE id = ${accountId}`;
      await transaction`DELETE FROM pending_account_purges WHERE account_id = ${accountId}`;

      return objectKeys;
    });
  }

  async drainObjectDeletions(
    deleteObject: (key: string) => Promise<void>,
    limit?: number
  ): Promise<DrainObjectDeletionsResult> {
    return drainPendingObjectDeletions({ outbox: this.objectDeletions, deleteObject, limit });
  }
}

/**
 * Resumes purges whose request died between the identity deletion and the row purge, and
 * retries object keys that storage refused earlier.
 */
export async function sweepStaleAccountPurges(
  options: SweepStaleAccountPurgesOptions
): Promise<SweepStaleAccountPurgesResult> {
  const olderThanSeconds = options.olderThanSeconds ?? DEFAULT_PURGE_GRACE_SECONDS;
  const accountIds = await options.accountStore.listStalePurgeIntents(olderThanSeconds);
  const purgedAccounts: string[] = [];
  const failedAccounts: string[] = [];

  for (const accountId of accountIds) {
    try {
      await options.accountStore.purgeAccountData(accountId, {
        resolveObjectKey: options.resolveObjectKey
      });
      purgedAccounts.push(accountId);
    } catch (error) {
      failedAccounts.push(accountId);
      logger.error({ accountId }, "account_purge_failed");
    }
  }

  const drain = await drainPendingObjectDeletions({
    outbox: options.outbox,
    deleteObject: options.deleteObject,
    limit: options.drainLimit
  });

  return { purgedAccounts, failedAccounts, drain };
}
