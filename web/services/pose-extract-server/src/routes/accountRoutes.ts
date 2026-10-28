import { Router } from "express";
import { objectKeyFromLocator, type AccountStore } from "../db/accountStore";
import { deleteObject as defaultDeleteObject } from "../services/r2Storage";
import {
  AppleRevocationError,
  revokeAppleAuthorizationCode,
  type AppleRevocationResult,
  type AppleSignInConfig
} from "../services/appleRevocation";
import { logger } from "../utils/logger";

const PENDING_VALIDATION = {
  error: {
    code: "AUTH_PENDING_VALIDATION",
    message: "Account deletion is pending runtime validation"
  }
};

/** The account signs in with Apple too, so the deletion needs a fresh Apple confirmation. */
const APPLE_REAUTH_REQUIRED = {
  error: {
    code: "APPLE_REAUTH_REQUIRED",
    message: "Confirm with Apple before deleting this account"
  }
};

/** The code belongs to a different Apple account: revoking it would not revoke this account's grant. */
const APPLE_IDENTITY_MISMATCH = {
  error: {
    code: "APPLE_IDENTITY_MISMATCH",
    message: "The Apple credential does not match this account"
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
  /** Absent when the APPLE_* block is unset: an Apple account then fails closed instead of deleting. */
  apple?: AppleSignInConfig;
  appleFetchImpl?: typeof fetch;
}

/**
 * What Supabase's admin API says about the user's sign-in providers.
 * - `apple`: the account has an Apple identity and its `sub` is the one Apple binds tokens to.
 * - `other`: signed in some other way only.
 * - `gone`: verified 404, i.e. an earlier attempt already deleted the identity.
 * - `unknown`: any other failure, so nothing may be destroyed.
 */
type AdminUserState =
  | { kind: "apple"; appleSub: string }
  | { kind: "other" }
  | { kind: "gone" }
  | { kind: "unknown" };

interface AdminIdentity {
  provider?: unknown;
  provider_id?: unknown;
  identity_data?: { sub?: unknown } | null;
}

function appleSubFromIdentities(identities: unknown): string | null {
  if (!Array.isArray(identities)) return null;
  for (const raw of identities) {
    const identity = raw as AdminIdentity | null;
    if (!identity || identity.provider !== "apple") continue;
    const fromData = typeof identity.identity_data?.sub === "string" ? identity.identity_data.sub : null;
    const fromProviderId = typeof identity.provider_id === "string" ? identity.provider_id : null;
    const sub = fromData ?? fromProviderId;
    if (sub) return sub;
  }
  return null;
}

export function createAccountRoutes(options: AccountRoutesOptions): Router {
  const router = Router();
  const supabaseUrl = options.supabaseUrl.replace(/\/$/, "");
  const fetchImpl = options.fetchImpl ?? fetch;
  const deleteObject = options.deleteObject ?? defaultDeleteObject;

  const adminHeaders = {
    apikey: options.serviceRoleKey ?? "",
    Authorization: `Bearer ${options.serviceRoleKey ?? ""}`
  };

  /** Reads the authority on which providers this account has. Never inferred from a request. */
  async function readAdminUser(accountId: string): Promise<AdminUserState> {
    let response: Response;
    try {
      response = await fetchImpl(`${supabaseUrl}/auth/v1/admin/users/${encodeURIComponent(accountId)}`, {
        method: "GET",
        headers: adminHeaders
      });
    } catch {
      return { kind: "unknown" };
    }
    if (response.status === 404) return { kind: "gone" };
    if (response.status !== 200) return { kind: "unknown" };

    let body: { identities?: unknown } | null = null;
    try {
      body = (await response.json()) as { identities?: unknown };
    } catch {
      return { kind: "unknown" };
    }
    const appleSub = appleSubFromIdentities(body?.identities);
    return appleSub ? { kind: "apple", appleSub } : { kind: "other" };
  }

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

    const adminUser = await readAdminUser(accountId);
    if (adminUser.kind === "unknown") {
      // Nothing is known about the identity, so nothing is touched.
      res.status(503).json(PENDING_VALIDATION);
      return;
    }

    // A verified 404 means an earlier attempt already deleted the identity: no Apple step and no
    // second DELETE is possible, only the row purge that attempt never finished.
    if (adminUser.kind === "apple") {
      if (!options.apple) {
        res.status(503).json(PENDING_VALIDATION);
        return;
      }
      const code = typeof (req.body as { appleAuthorizationCode?: unknown } | undefined)?.appleAuthorizationCode === "string"
        ? ((req.body as { appleAuthorizationCode: string }).appleAuthorizationCode.trim())
        : "";
      if (!code) {
        res.status(409).json(APPLE_REAUTH_REQUIRED);
        return;
      }

      let revocation: AppleRevocationResult;
      try {
        revocation = await revokeAppleAuthorizationCode({
          authorizationCode: code,
          appleSub: adminUser.appleSub,
          config: options.apple,
          fetchImpl: options.appleFetchImpl ?? fetchImpl
        });
      } catch (error) {
        // Nothing is known about the tokens, so the account is not deleted.
        const stage = error instanceof AppleRevocationError ? error.stage : "unknown";
        logger.warn({ accountId, stage }, "apple_token_revocation_failed");
        res.status(503).json(PENDING_VALIDATION);
        return;
      }

      if (revocation.outcome === "identity_mismatch") {
        res.status(409).json(APPLE_IDENTITY_MISMATCH);
        return;
      }
      if (revocation.outcome === "reauth_required") {
        res.status(409).json(APPLE_REAUTH_REQUIRED);
        return;
      }
    }

    if (adminUser.kind !== "gone") {
      // The identity must be confirmed gone before any local deletion is recorded or runs.
      // A cancelled, rejected, or failed upstream call leaves the account fully intact.
      let identityDeleted = false;
      try {
        const response = await fetchImpl(`${supabaseUrl}/auth/v1/admin/users/${encodeURIComponent(accountId)}`, {
          method: "DELETE",
          headers: adminHeaders
        });
        identityDeleted = response.status === 404 || response.ok;
      } catch {
        identityDeleted = false;
      }

      if (!identityDeleted) {
        res.status(503).json(PENDING_VALIDATION);
        return;
      }
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
