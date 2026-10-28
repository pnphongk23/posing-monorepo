import { Router } from "express";
import { objectKeyFromLocator, type AccountStore } from "../db/accountStore";
import { deleteObject as defaultDeleteObject } from "../services/r2Storage";
import { logger } from "../utils/logger";

const PENDING_VALIDATION = {
  error: {
    code: "AUTH_PENDING_VALIDATION",
    message: "Account deletion is pending runtime validation"
  }
};

const OBJECT_DRAIN_LIMIT = 200;

type DeleteObject = (fileKey: string) => Promise<void>;

export interface AccountRoutesOptions {
  supabaseUrl: string;
  serviceRoleKey?: string;
  r2PublicUrl?: string;
  accountStore: AccountStore;
  fetchImpl?: typeof fetch;
  deleteObject?: DeleteObject;
}

export function createAccountRoutes(options: AccountRoutesOptions): Router {
  const router = Router();
  const supabaseUrl = options.supabaseUrl.replace(/\/$/, "");
  const fetchImpl = options.fetchImpl ?? fetch;
  const deleteObject = options.deleteObject ?? defaultDeleteObject;

  router.delete(["/", "/api/account"], async (req, res) => {
    if (!options.serviceRoleKey) {
      res.status(503).json(PENDING_VALIDATION);
      return;
    }

    const accountId = req.account?.id;
    if (!accountId) {
      res.status(401).json({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
      return;
    }

    // The identity must be confirmed gone before any local deletion is recorded or runs.
    // A cancelled, rejected, or failed upstream call leaves the account fully intact.
    let identityDeleted = false;
    try {
      const response = await fetchImpl(`${supabaseUrl}/auth/v1/admin/users/${encodeURIComponent(accountId)}`, {
        method: "DELETE",
        headers: {
          apikey: options.serviceRoleKey,
          Authorization: `Bearer ${options.serviceRoleKey}`
        }
      });
      identityDeleted = response.status === 404 || response.ok;
    } catch {
      identityDeleted = false;
    }

    if (!identityDeleted) {
      res.status(503).json(PENDING_VALIDATION);
      return;
    }

    try {
      await options.accountStore.recordPurgeIntent(accountId);
    } catch {
      logger.error({ accountId }, "account_purge_failed");
      res.status(503).json(PENDING_VALIDATION);
      return;
    }

    let objectKeys: string[] = [];
    try {
      objectKeys = await options.accountStore.purgeAccountData(accountId, {
        resolveObjectKey: (locator) => objectKeyFromLocator(locator, options.r2PublicUrl)
      });
    } catch {
      logger.error({ accountId }, "account_purge_failed");
      res.status(503).json(PENDING_VALIDATION);
      return;
    }

    try {
      await options.accountStore.drainObjectDeletions(deleteObject, OBJECT_DRAIN_LIMIT);
    } catch {
      logger.warn({ accountId, pendingKeys: objectKeys.length }, "Failed to drain pending object deletions");
    }

    res.status(204).send();
  });

  return router;
}
