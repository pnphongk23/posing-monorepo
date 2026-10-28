import type { EntitlementEnvironment, EntitlementSnapshot } from "../db/entitlementStore";

/** RevenueCat REST v1. The API version is part of the path, not of our public surface. */
export const REVENUECAT_API_BASE_URL = "https://api.revenuecat.com";
export const REVENUECAT_REQUEST_TIMEOUT_MS = 5_000;
/**
 * A subscriber document grows with the purchase history (each consumable is one entry), so the
 * cap is generous; it still bounds what the process will read from one response.
 */
export const REVENUECAT_MAX_BODY_BYTES = 16 * 1024 * 1024;

/** The upstream read failed. Callers retry later; they never fall back to a cached "active". */
export class RevenueCatRequestError extends Error {
  constructor(message = "Subscription service request failed") {
    super(message);
    this.name = "RevenueCatRequestError";
  }
}

export interface RevenueCatClientOptions {
  apiKey: string;
  entitlementId: string;
  fetchImpl?: typeof fetch;
  /** Server clock, sampled when the response is received. */
  now?: () => number;
  timeoutMs?: number;
  maxBodyBytes?: number;
  baseUrl?: string;
}

export interface RevenueCatClient {
  /** Reads the authoritative subscriber state. Throws on transport or upstream failure. */
  readEntitlement(appUserId: string): Promise<EntitlementSnapshot>;
}

type JsonObject = Record<string, unknown>;

function asObject(value: unknown): JsonObject | null {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? (value as JsonObject) : null;
}

function asNonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}

/**
 * Evidence rules. A purchase entry only proves a purchase when it carries a readable purchase
 * date, and a subscription entry must also state its expiry explicitly: a date for a
 * subscription or null for a lifetime purchase. An entry that fails these rules is ignored,
 * which leaves the entitlement in the inactive absent-subscriber row rather than failing the
 * whole read (the surrounding document is still well formed).
 */
function isPurchaseDateReadable(entry: JsonObject): boolean {
  return asDate(entry.purchase_date) !== null;
}

function isSubscriptionEntry(entry: JsonObject | null): entry is JsonObject {
  if (!entry || !isPurchaseDateReadable(entry)) {
    return false;
  }
  const expiresAt = entry.expires_date;
  return expiresAt === null || asDate(expiresAt) !== null;
}

/** The first non-subscription purchase recorded for a product that names when it happened. */
function firstNonSubscriptionPurchase(value: unknown, productId: string): JsonObject | null {
  const purchases = asObject(value);
  if (!purchases) {
    return null;
  }
  const entries = purchases[productId];
  if (!Array.isArray(entries)) {
    return null;
  }
  for (const entry of entries) {
    const purchase = asObject(entry);
    if (purchase && isPurchaseDateReadable(purchase)) {
      return purchase;
    }
  }
  return null;
}

/**
 * A 200 that is not a subscriber document is a REST failure, not an inactive subscriber:
 * only an explicit 404 or a well-formed document may be read as "no subscription".
 */
function isSubscriberPayload(value: unknown): boolean {
  const root = asObject(value);
  if (!root) {
    return false;
  }
  const subscriber = asObject(root.subscriber);
  if (!subscriber) {
    return false;
  }
  for (const field of ["entitlements", "subscriptions", "non_subscriptions"]) {
    const section = subscriber[field];
    if (section !== undefined && section !== null && asObject(section) === null) {
      return false;
    }
  }
  return true;
}

const ISO_DATETIME = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|[+-]\d{2}:\d{2})$/;

function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

/**
 * Dates on a subscriber document are strict ISO-8601 datetimes. `Date.parse` alone would accept
 * "0" (a 1999 instant) or roll 2026-02-30 over into March, so the shape and the calendar are both
 * checked before the value is trusted.
 */
function asDate(value: unknown): Date | null {
  const raw = asNonEmptyString(value);
  if (!raw) {
    return null;
  }
  const match = ISO_DATETIME.exec(raw);
  if (!match) {
    return null;
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);
  if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) {
    return null;
  }
  if (hour > 23 || minute > 59 || second > 59) {
    return null;
  }
  if (match[7] !== "Z") {
    const offsetHours = Number(match[7].slice(1, 3));
    const offsetMinutes = Number(match[7].slice(4, 6));
    if (offsetHours > 23 || offsetMinutes > 59) {
      return null;
    }
  }
  const ms = Date.parse(raw);
  return Number.isFinite(ms) ? new Date(ms) : null;
}

/** The upstream snapshot time, or the moment the response was received when it is absent. */
function readUpstreamAt(payload: JsonObject | null, receivedAt: Date): Date {
  const requestDateMs = payload?.request_date_ms;
  if (typeof requestDateMs === "number" && Number.isFinite(requestDateMs) && requestDateMs > 0) {
    return new Date(requestDateMs);
  }
  return receivedAt;
}

function absentSnapshot(entitlementId: string, receivedAt: Date): EntitlementSnapshot {
  return {
    entitlementId,
    isActive: false,
    expiresAt: null,
    productId: null,
    store: null,
    environment: null,
    upstreamAt: receivedAt,
    syncedAt: receivedAt
  };
}

/**
 * Pure mapping from a subscriber payload to the row we store. Unknown shapes fail closed:
 * anything that cannot be read as an active, unexpired entitlement is inactive.
 *
 * @param payload the `/v1/subscribers/{id}` body, or null when the subscriber is absent
 * @param receivedAt the server clock at response receipt; also the fallback snapshot time
 */
export function toEntitlement(payload: unknown, entitlementId: string, receivedAt: Date): EntitlementSnapshot {
  const root = asObject(payload);
  const subscriber = root ? asObject(root.subscriber) : null;
  if (!subscriber) {
    return absentSnapshot(entitlementId, receivedAt);
  }

  const entitlements = asObject(subscriber.entitlements);
  const entitlement = entitlements ? asObject(entitlements[entitlementId]) : null;
  if (!entitlement) {
    return { ...absentSnapshot(entitlementId, receivedAt), upstreamAt: readUpstreamAt(root, receivedAt) };
  }

  const productId = asNonEmptyString(entitlement.product_identifier);
  const subscriptions = asObject(subscriber.subscriptions);
  const subscriptionEntry = productId && subscriptions ? asObject(subscriptions[productId]) : null;
  const subscription = isSubscriptionEntry(subscriptionEntry) ? subscriptionEntry : null;
  const purchase = productId && !subscription ? firstNonSubscriptionPurchase(subscriber.non_subscriptions, productId) : null;

  // Without a purchase of this product there is no entitlement to be active on, whatever the
  // entitlement object claims. This is the absent-subscriber row.
  if (!subscription && !purchase) {
    return { ...absentSnapshot(entitlementId, receivedAt), upstreamAt: readUpstreamAt(root, receivedAt) };
  }

  const evidence = subscription ?? purchase!;
  const rawExpiresAt = entitlement.expires_date;
  const graceExpiresAt = asDate(entitlement.grace_period_expires_date);

  let expiresAt: Date | null = null;
  let isActive: boolean;
  if (rawExpiresAt === null || rawExpiresAt === undefined) {
    // A lifetime purchase carries no expiry, so its only evidence is the purchase found above.
    isActive = true;
  } else {
    const expiresDate = asDate(rawExpiresAt);
    if (!expiresDate || !subscription) {
      // An unreadable expiry must never be mistaken for a lifetime purchase, and a dated
      // entitlement without a subscription is not an active subscription entitlement.
      isActive = false;
    } else {
      // A subscription in its billing grace period is still entitled; RevenueCat reports the
      // grace period in a separate date, so the later of the two is the effective expiry.
      expiresAt = graceExpiresAt && graceExpiresAt.getTime() > expiresDate.getTime() ? graceExpiresAt : expiresDate;
      isActive = expiresAt.getTime() > receivedAt.getTime();
    }
  }

  const isSandbox = evidence.is_sandbox;
  const environment: EntitlementEnvironment | null =
    typeof isSandbox === "boolean" ? (isSandbox ? "SANDBOX" : "PRODUCTION") : null;

  return {
    entitlementId,
    isActive,
    expiresAt,
    productId,
    store: asNonEmptyString(evidence.store),
    environment,
    upstreamAt: readUpstreamAt(root, receivedAt),
    syncedAt: receivedAt
  };
}

/** Reads at most `maxBytes` of the response body; an oversized or unreadable body is a failure. */
async function readCappedText(response: Response, maxBytes: number): Promise<string> {
  const declaredLength = Number(response.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > maxBytes) {
    throw new RevenueCatRequestError();
  }
  if (!response.body) {
    return "";
  }

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let received = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }
    if (!value) {
      continue;
    }
    received += value.byteLength;
    if (received > maxBytes) {
      await reader.cancel().catch(() => undefined);
      throw new RevenueCatRequestError();
    }
    chunks.push(value);
  }
  return Buffer.concat(chunks).toString("utf8");
}

export function createRevenueCatClient(options: RevenueCatClientOptions): RevenueCatClient {
  const fetchImpl = options.fetchImpl ?? fetch;
  const now = options.now ?? Date.now;
  const baseUrl = (options.baseUrl ?? REVENUECAT_API_BASE_URL).replace(/\/$/, "");
  const timeoutMs = options.timeoutMs ?? REVENUECAT_REQUEST_TIMEOUT_MS;
  const maxBodyBytes = options.maxBodyBytes ?? REVENUECAT_MAX_BODY_BYTES;

  return {
    async readEntitlement(appUserId: string): Promise<EntitlementSnapshot> {
      let response: Response;
      try {
        response = await fetchImpl(`${baseUrl}/v1/subscribers/${encodeURIComponent(appUserId)}`, {
          method: "GET",
          headers: {
            Authorization: `Bearer ${options.apiKey}`,
            Accept: "application/json"
          },
          signal: AbortSignal.timeout(timeoutMs)
        });
      } catch {
        // Never surface the upstream error: it can carry the request URL and headers.
        throw new RevenueCatRequestError();
      }

      const receivedAt = new Date(now());

      // A subscriber the platform has never seen is a valid "no subscription", not a failure.
      if (response.status === 404) {
        return absentSnapshot(options.entitlementId, receivedAt);
      }
      if (!response.ok) {
        throw new RevenueCatRequestError();
      }

      let payload: unknown;
      try {
        const text = await readCappedText(response, maxBodyBytes);
        payload = JSON.parse(text);
      } catch {
        // A body we cannot read or parse is a failed read, never an inactive subscriber:
        // treating it as "absent" would silently write an inactive row.
        throw new RevenueCatRequestError();
      }
      if (!isSubscriberPayload(payload)) {
        throw new RevenueCatRequestError();
      }
      return toEntitlement(payload, options.entitlementId, receivedAt);
    }
  };
}
