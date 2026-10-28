import { Router } from "express";
import type { Response } from "express";

import {
  ENTITLEMENT_REFRESH_INTERVAL_MS,
  isForeignKeyViolation,
  type EntitlementEnvironment,
  type EntitlementRecord,
  type EntitlementSnapshot,
  type EntitlementStore
} from "../db/entitlementStore";
import { createExtractRateLimitMiddleware } from "../middleware/extractRateLimit";
import type { RevenueCatClient } from "../services/revenueCatClient";

/** One explicit reconcile per minute per Account; the client calls it after sign-in and purchase. */
export const ENTITLEMENT_SYNC_RATE_LIMIT_WINDOW_MS = 60_000;
export const ENTITLEMENT_SYNC_RATE_LIMIT_MAX = 10;

export interface EntitlementView {
  entitlementId: string | null;
  isActive: boolean;
  expiresAt: string | null;
  productId: string | null;
  store: string | null;
  environment: EntitlementEnvironment | null;
  syncedAt: string | null;
  /** True when the stored row could not be refreshed upstream, so the client knows it is cached. */
  stale: boolean;
}

export interface EntitlementRoutesOptions {
  store?: EntitlementStore;
  client?: RevenueCatClient;
  entitlementId?: string;
  now?: () => number;
  syncRateLimitWindowMs?: number;
  syncRateLimitMaxRequests?: number;
}

function unavailable(res: Response): void {
  res.status(503).json({
    error: {
      code: "ENTITLEMENT_UNAVAILABLE",
      message: "Entitlement service is not configured"
    }
  });
}

/**
 * Fail-closed read model. The stored flag alone is not trusted: a row that says active but
 * has already expired is inactive, and a row this build cannot read is inactive.
 */
export function toEntitlementView(
  row: EntitlementRecord | null,
  entitlementId: string,
  nowMs: number,
  stale: boolean
): EntitlementView {
  // A row cached under a different entitlement never describes the configured one.
  if (!row || row.entitlementId !== entitlementId) {
    return {
      entitlementId,
      isActive: false,
      expiresAt: null,
      productId: null,
      store: null,
      environment: null,
      syncedAt: null,
      stale
    };
  }

  const expiryMs = row.expiresAt === null ? null : Date.parse(row.expiresAt);
  const unreadableExpiry = row.expiresAt !== null && !Number.isFinite(expiryMs as number);
  const isActive = row.isActive && !unreadableExpiry && (expiryMs === null || (expiryMs as number) > nowMs);

  if (!isActive) {
    return {
      entitlementId: row.entitlementId,
      isActive: false,
      expiresAt: null,
      productId: null,
      store: null,
      environment: null,
      syncedAt: row.syncedAt,
      stale
    };
  }

  return {
    entitlementId: row.entitlementId,
    isActive: true,
    expiresAt: row.expiresAt,
    productId: row.productId,
    store: row.store,
    environment: row.environment,
    syncedAt: row.syncedAt,
    stale
  };
}

/**
 * A missing, aging, already-expired, or differently-configured row has to be re-read upstream
 * before it is served.
 */
function needsRefresh(row: EntitlementRecord | null, nowMs: number, entitlementId: string): boolean {
  if (!row || row.entitlementId !== entitlementId) {
    return true;
  }
  const syncedMs = Date.parse(row.syncedAt);
  if (!Number.isFinite(syncedMs) || nowMs - syncedMs >= ENTITLEMENT_REFRESH_INTERVAL_MS) {
    return true;
  }
  if (row.isActive && row.expiresAt !== null) {
    const expiryMs = Date.parse(row.expiresAt);
    if (!Number.isFinite(expiryMs) || expiryMs <= nowMs) {
      return true;
    }
  }
  return false;
}

export function createEntitlementRoutes(options: EntitlementRoutesOptions): Router {
  const router = Router();
  const now = options.now ?? Date.now;
  const syncRateLimit = createExtractRateLimitMiddleware({
    windowMs: options.syncRateLimitWindowMs ?? ENTITLEMENT_SYNC_RATE_LIMIT_WINDOW_MS,
    maxRequests: options.syncRateLimitMaxRequests ?? ENTITLEMENT_SYNC_RATE_LIMIT_MAX,
    keyProvider: (req) => req.account?.id ?? req.ip ?? "unknown",
    message: "Too many entitlement sync requests"
  });
  const available = Boolean(options.store && options.client && options.entitlementId);

  const writeSnapshot = async (accountId: string, snapshot: EntitlementSnapshot): Promise<EntitlementRecord | null> => {
    try {
      return await options.store!.upsert(accountId, snapshot);
    } catch (error) {
      // The account vanished between the session check and the write; there is nothing to store.
      if (isForeignKeyViolation(error)) {
        return null;
      }
      throw error;
    }
  };

  router.get("/", async (req, res) => {
    if (!available) {
      unavailable(res);
      return;
    }

    // The account is the authenticated session only: no query parameter or header may name another.
    const accountId = req.account!.id;
    const nowMs = now();
    let row = await options.store!.get(accountId);
    let stale = false;

    if (needsRefresh(row, nowMs, options.entitlementId!)) {
      try {
        const snapshot = await options.client!.readEntitlement(accountId);
        row = (await writeSnapshot(accountId, snapshot)) ?? (await options.store!.get(accountId));
      } catch {
        // Keep serving the stored row, but never claim it is fresh or still entitled past expiry.
        stale = true;
      }
    }

    res.json({ data: toEntitlementView(row, options.entitlementId!, now(), stale) });
  });

  router.post("/sync", syncRateLimit, async (req, res) => {
    if (!available) {
      unavailable(res);
      return;
    }

    const accountId = req.account!.id;
    try {
      const snapshot = await options.client!.readEntitlement(accountId);
      const row = (await writeSnapshot(accountId, snapshot)) ?? (await options.store!.get(accountId));
      res.json({ data: toEntitlementView(row, options.entitlementId!, now(), false) });
    } catch {
      res.status(503).json({
        error: {
          code: "ENTITLEMENT_UNAVAILABLE",
          message: "Entitlement service is temporarily unavailable"
        }
      });
    }
  });

  return router;
}
