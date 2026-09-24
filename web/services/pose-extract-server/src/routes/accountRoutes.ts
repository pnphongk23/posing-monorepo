import { Router } from "express";
import type { AccountStore } from "../db/accountStore";
import { deleteObject as defaultDeleteObject } from "../services/r2Storage";
import { logger } from "../utils/logger";

const PENDING_VALIDATION = {
  error: {
    code: "AUTH_PENDING_VALIDATION",
    message: "Account deletion is pending runtime validation"
  }
};

type DeleteObject = (fileKey: string) => Promise<void>;

export interface AccountRoutesOptions {
  supabaseUrl: string;
  serviceRoleKey?: string;
  r2PublicUrl?: string;
  accountStore: AccountStore;
  fetchImpl?: typeof fetch;
  deleteObject?: DeleteObject;
}

function objectKey(locator: string, r2PublicUrl?: string): string {
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

    try {
      const response = await fetchImpl(`${supabaseUrl}/auth/v1/admin/users/${encodeURIComponent(accountId)}`, {
        method: "DELETE",
        headers: {
          apikey: options.serviceRoleKey,
          Authorization: `Bearer ${options.serviceRoleKey}`
        }
      });
      if (response.status !== 404 && !response.ok) {
        res.status(503).json(PENDING_VALIDATION);
        return;
      }

      const locators = await options.accountStore.getOwnedMediaLocators(accountId);
      for (const locator of locators) {
        const key = objectKey(locator, options.r2PublicUrl);
        try {
          await deleteObject(key);
        } catch {
          logger.warn({ key }, "Failed to delete account media object");
        }
      }

      await options.accountStore.purgeAccountData(accountId);
      res.status(204).send();
    } catch {
      res.status(503).json(PENDING_VALIDATION);
    }
  });

  return router;
}
