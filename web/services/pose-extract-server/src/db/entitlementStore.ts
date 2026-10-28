import type { Sql, SqlOrTx } from "./connection";
import { pgTimestamp } from "./pgTypes";

export type EntitlementEnvironment = "SANDBOX" | "PRODUCTION";

/** A refresh of a row that has not been read upstream for this long. */
export const ENTITLEMENT_REFRESH_INTERVAL_MS = 24 * 60 * 60 * 1000;

/** One upstream read, normalised for storage. Times are absolute, never relative to the caller. */
export interface EntitlementSnapshot {
  entitlementId: string;
  isActive: boolean;
  /** The effective expiry: the grace period date when it is later than the expiry date. */
  expiresAt: Date | null;
  productId: string | null;
  store: string | null;
  environment: EntitlementEnvironment | null;
  /** Ordering key of the snapshot. An older snapshot never replaces a newer one. */
  upstreamAt: Date;
  /** When this snapshot was written. */
  syncedAt: Date;
}

export interface EntitlementRecord {
  accountId: string;
  entitlementId: string;
  isActive: boolean;
  expiresAt: string | null;
  productId: string | null;
  store: string | null;
  environment: EntitlementEnvironment | null;
  upstreamAt: string;
  syncedAt: string;
}

interface EntitlementRow {
  account_id: string;
  entitlement_id: string;
  is_active: boolean;
  expires_at: Date | string | null;
  product_id: string | null;
  store: string | null;
  environment: EntitlementEnvironment | null;
  upstream_at: Date | string;
  synced_at: Date | string;
}

function toRecord(row: EntitlementRow): EntitlementRecord {
  return {
    accountId: row.account_id,
    entitlementId: row.entitlement_id,
    isActive: row.is_active,
    expiresAt: pgTimestamp(row.expires_at),
    productId: row.product_id,
    store: row.store,
    environment: row.environment,
    upstreamAt: pgTimestamp(row.upstream_at) ?? new Date(0).toISOString(),
    syncedAt: pgTimestamp(row.synced_at) ?? new Date(0).toISOString()
  };
}

/** A write whose account disappeared between the account lookup and the insert. */
export function isForeignKeyViolation(error: unknown): boolean {
  if (typeof error !== "object" || error === null) {
    return false;
  }
  const code = (error as { code?: unknown }).code;
  return code === "23503";
}

/**
 * The single writer of `account_entitlements`. Every path (webhook, read refresh, explicit
 * reconcile) goes through `upsert`, so snapshot ordering is enforced in one statement.
 */
export class EntitlementStore {
  constructor(private readonly db: Sql) {}

  async get(accountId: string): Promise<EntitlementRecord | null> {
    const rows = (await this.db`
      SELECT account_id, entitlement_id, is_active, expires_at, product_id, store,
             environment, upstream_at, synced_at
      FROM account_entitlements
      WHERE account_id = ${accountId}
    `) as EntitlementRow[];
    return rows[0] ? toRecord(rows[0]) : null;
  }

  /**
   * Conditional upsert: the incoming snapshot replaces the stored one only when it is not
   * older. A delayed read that resolves late therefore loses to the newer one regardless of
   * which statement commits first.
   */
  async upsert(
    accountId: string,
    snapshot: EntitlementSnapshot,
    sql: SqlOrTx = this.db
  ): Promise<EntitlementRecord | null> {
    const rows = (await sql`
      INSERT INTO account_entitlements (
        account_id, entitlement_id, is_active, expires_at, product_id, store,
        environment, upstream_at, synced_at
      )
      VALUES (
        ${accountId}, ${snapshot.entitlementId}, ${snapshot.isActive}, ${snapshot.expiresAt},
        ${snapshot.productId}, ${snapshot.store}, ${snapshot.environment},
        ${snapshot.upstreamAt}, ${snapshot.syncedAt}
      )
      ON CONFLICT (account_id) DO UPDATE SET
        entitlement_id = EXCLUDED.entitlement_id,
        is_active = EXCLUDED.is_active,
        expires_at = EXCLUDED.expires_at,
        product_id = EXCLUDED.product_id,
        store = EXCLUDED.store,
        environment = EXCLUDED.environment,
        upstream_at = EXCLUDED.upstream_at,
        synced_at = EXCLUDED.synced_at
      WHERE account_entitlements.upstream_at <= EXCLUDED.upstream_at
      RETURNING account_id, entitlement_id, is_active, expires_at, product_id, store,
                environment, upstream_at, synced_at
    `) as EntitlementRow[];

    if (rows[0]) {
      return toRecord(rows[0]);
    }

    // The snapshot was older than the stored one: the caller still needs to see the truth.
    return this.get(accountId);
  }
}
