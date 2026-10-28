import { timingSafeEqual } from "node:crypto";

import { Router } from "express";
import { z } from "zod";

import { isForeignKeyViolation, type EntitlementStore } from "../db/entitlementStore";
import type { EntitlementSnapshot } from "../db/entitlementStore";
import type { RevenueCatClient } from "../services/revenueCatClient";

/** Identities the platform generates for an unauthenticated install. Never an Account. */
export const ANONYMOUS_APP_USER_ID_PREFIX = "$RCAnonymousID:";

/**
 * Event types whose payload names account candidates. Anything else (including the platform's
 * own TEST event) is acknowledged and ignored, so an unknown type never causes retries.
 */
const ACCOUNT_EVENT_TYPES = [
  "INITIAL_PURCHASE",
  "RENEWAL",
  "CANCELLATION",
  "UNCANCELLATION",
  "NON_RENEWING_PURCHASE",
  "SUBSCRIPTION_PAUSED",
  "EXPIRATION",
  "BILLING_ISSUE",
  "PRODUCT_CHANGE",
  "SUBSCRIPTION_EXTENDED",
  "REFUND_REVERSED",
  "TEMPORARY_ENTITLEMENT_GRANT"
] as const;

export const SUPPORTED_WEBHOOK_EVENT_TYPES: ReadonlySet<string> = new Set([...ACCOUNT_EVENT_TYPES, "TRANSFER"]);

const accountEventSchema = z.object({
  id: z.string().min(1).optional(),
  type: z.enum(ACCOUNT_EVENT_TYPES),
  app_user_id: z.string().min(1),
  original_app_user_id: z.string().min(1).optional(),
  aliases: z.array(z.string().min(1)).optional(),
  environment: z.string().min(1).optional()
});

const transferEventSchema = z.object({
  id: z.string().min(1).optional(),
  type: z.literal("TRANSFER"),
  transferred_from: z.array(z.string().min(1)).min(1),
  transferred_to: z.array(z.string().min(1)).min(1),
  environment: z.string().min(1).optional()
});

/** The event object, sent either bare or wrapped as `{ event, api_version }`. */
const bodySchema = z.union([transferEventSchema, accountEventSchema]);

type WebhookEvent = z.infer<typeof bodySchema>;

export interface RevenueCatWebhookOptions {
  accountStore: { getById(id: string): Promise<unknown | null> };
  entitlementStore: EntitlementStore;
  client: RevenueCatClient;
  webhookAuth: string;
}

function isAuthorized(header: string | undefined, expected: string): boolean {
  const provided = Buffer.from(header ?? "", "utf8");
  const wanted = Buffer.from(expected, "utf8");
  // Length first: timingSafeEqual throws on a length mismatch, and the lengths are not a secret.
  if (provided.length !== wanted.length) {
    return false;
  }
  return timingSafeEqual(provided, wanted);
}

function unwrapEvent(body: unknown): unknown {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return body;
  }
  const wrapper = body as Record<string, unknown>;
  return typeof wrapper.event === "object" && wrapper.event !== null ? wrapper.event : body;
}

/** Account candidates named by the event, anonymous installs and duplicates removed. */
export function accountCandidates(event: WebhookEvent): string[] {
  const raw =
    event.type === "TRANSFER"
      ? [...event.transferred_from, ...event.transferred_to]
      : [event.app_user_id, ...(event.original_app_user_id ? [event.original_app_user_id] : []), ...(event.aliases ?? [])];

  const unique = new Set<string>();
  for (const candidate of raw) {
    if (candidate.startsWith(ANONYMOUS_APP_USER_ID_PREFIX)) {
      continue;
    }
    unique.add(candidate);
  }
  return [...unique];
}

/**
 * The webhook is a trigger, never a source of truth: the payload only names accounts to
 * re-read from the subscription platform. It answers 401/400/503 or 200, and a 2xx is only
 * sent once every named account has been read or deliberately skipped.
 */
export function createRevenueCatWebhookRoutes(options: RevenueCatWebhookOptions): Router {
  const router = Router();
  const expectedAuthorization = `Bearer ${options.webhookAuth}`;

  router.post("/", async (req, res) => {
    if (!isAuthorized(req.header("authorization"), expectedAuthorization)) {
      res.status(401).json({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
      return;
    }

    const unwrapped = unwrapEvent(req.body);
    const rawType = typeof unwrapped === "object" && unwrapped !== null ? (unwrapped as { type?: unknown }).type : undefined;
    if (typeof rawType !== "string" || !SUPPORTED_WEBHOOK_EVENT_TYPES.has(rawType)) {
      if (typeof rawType === "string") {
        // A known-platform but unsupported event must not be retried forever.
        res.json({ ignored: true });
        return;
      }
      res.status(400).json({ error: { code: "BAD_REQUEST", message: "Malformed webhook payload" } });
      return;
    }

    const parsed = bodySchema.safeParse(unwrapped);
    if (!parsed.success) {
      res.status(400).json({ error: { code: "BAD_REQUEST", message: "Malformed webhook payload" } });
      return;
    }

    const known: string[] = [];
    for (const candidate of accountCandidates(parsed.data)) {
      if (await options.accountStore.getById(candidate)) {
        known.push(candidate);
      }
    }
    if (known.length === 0) {
      res.json({ ignored: true });
      return;
    }

    // Read every named account before writing any of them, so an upstream failure leaves the
    // stored rows untouched and the platform's retry is a clean replay.
    const reads: Array<{ accountId: string; snapshot: EntitlementSnapshot }> = [];
    try {
      for (const accountId of known) {
        reads.push({ accountId, snapshot: await options.client.readEntitlement(accountId) });
      }
    } catch {
      res.status(503).json({
        error: { code: "ENTITLEMENT_UNAVAILABLE", message: "Entitlement service is temporarily unavailable" }
      });
      return;
    }

    let processed = 0;
    for (const { accountId, snapshot } of reads) {
      try {
        await options.entitlementStore.upsert(accountId, snapshot);
        processed += 1;
      } catch (error) {
        if (!isForeignKeyViolation(error)) {
          throw error;
        }
        // The account was purged mid-flight: there is nothing left to store for it.
      }
    }

    res.json({ processed });
  });

  return router;
}
