import { describe, expect, it, vi } from "vitest";

import {
  createRevenueCatClient,
  RevenueCatRequestError,
  toEntitlement
} from "./revenueCatClient";

const RECEIVED_AT = new Date("2026-02-01T00:00:00.000Z");
const RECEIVED_AT_MS = RECEIVED_AT.getTime();
const DAY_MS = 24 * 60 * 60 * 1000;

function iso(offsetMs: number): string {
  return new Date(RECEIVED_AT_MS + offsetMs).toISOString();
}

interface SubscriberInput {
  entitlementProductId?: string;
  expiresDate?: string | null;
  gracePeriodExpiresDate?: string | null;
  isSandbox?: boolean;
  subscriptions?: Record<string, unknown>;
  omitEntitlement?: boolean;
  rawExpiresDate?: unknown;
}

function subscriberPayload(input: SubscriberInput = {}): Record<string, unknown> {
  const productId = input.entitlementProductId ?? "com.example.premium.monthly";
  const expiresDate = input.expiresDate === undefined ? iso(30 * DAY_MS) : input.expiresDate;
  const entitlement: Record<string, unknown> = { product_identifier: productId };
  if (!input.omitEntitlement) {
    entitlement.expires_date = input.rawExpiresDate !== undefined ? input.rawExpiresDate : expiresDate;
    entitlement.grace_period_expires_date = input.gracePeriodExpiresDate ?? null;
  }
  const subscriptions = input.subscriptions ?? {
    [productId]: {
      purchase_date: iso(-30 * DAY_MS),
      expires_date: expiresDate,
      grace_period_expires_date: input.gracePeriodExpiresDate ?? null,
      is_sandbox: input.isSandbox ?? false,
      store: "app_store"
    }
  };

  return {
    request_date: RECEIVED_AT.toISOString(),
    request_date_ms: RECEIVED_AT_MS,
    subscriber: {
      entitlements: input.omitEntitlement ? {} : { premium: entitlement },
      subscriptions
    }
  };
}

describe("toEntitlement", () => {
  it("reads an active subscription with a future expiry", () => {
    const snapshot = toEntitlement(subscriberPayload(), "premium", RECEIVED_AT);

    expect(snapshot).toEqual({
      entitlementId: "premium",
      isActive: true,
      expiresAt: new Date(iso(30 * DAY_MS)),
      productId: "com.example.premium.monthly",
      store: "app_store",
      environment: "PRODUCTION",
      upstreamAt: RECEIVED_AT,
      syncedAt: RECEIVED_AT
    });
  });

  it("reads an expired subscription as inactive", () => {
    const snapshot = toEntitlement(subscriberPayload({ expiresDate: iso(-DAY_MS) }), "premium", RECEIVED_AT);

    expect(snapshot.isActive).toBe(false);
    expect(snapshot.expiresAt).toEqual(new Date(iso(-DAY_MS)));
  });

  it("treats a missing expiry as a lifetime entitlement", () => {
    const snapshot = toEntitlement(subscriberPayload({ expiresDate: null }), "premium", RECEIVED_AT);

    expect(snapshot).toMatchObject({ isActive: true, expiresAt: null });
  });

  it("fails closed when the expiry is present but unreadable", () => {
    const snapshot = toEntitlement(
      subscriberPayload({ rawExpiresDate: "not-a-date", gracePeriodExpiresDate: iso(10 * DAY_MS) }),
      "premium",
      RECEIVED_AT
    );

    expect(snapshot).toMatchObject({ isActive: false, expiresAt: null });
  });

  it("is inactive when the configured entitlement is absent", () => {
    const snapshot = toEntitlement(subscriberPayload({ omitEntitlement: true }), "premium", RECEIVED_AT);

    expect(snapshot).toMatchObject({
      entitlementId: "premium",
      isActive: false,
      expiresAt: null,
      productId: null,
      store: null,
      environment: null,
      upstreamAt: RECEIVED_AT
    });
  });

  it("is inactive when the payload only carries a different entitlement", () => {
    const snapshot = toEntitlement(subscriberPayload(), "plus", RECEIVED_AT);

    expect(snapshot).toMatchObject({ entitlementId: "plus", isActive: false, environment: null });
  });

  it("keeps a subscription that is inside its billing grace period active", () => {
    const expiry = iso(-DAY_MS);
    const graceExpiry = iso(5 * DAY_MS);
    const snapshot = toEntitlement(
      subscriberPayload({ expiresDate: expiry, gracePeriodExpiresDate: graceExpiry }),
      "premium",
      RECEIVED_AT
    );

    expect(snapshot).toMatchObject({ isActive: true, expiresAt: new Date(graceExpiry) });
  });

  it("is inactive once both the expiry and the grace period have passed", () => {
    const snapshot = toEntitlement(
      subscriberPayload({ expiresDate: iso(-3 * DAY_MS), gracePeriodExpiresDate: iso(-DAY_MS) }),
      "premium",
      RECEIVED_AT
    );

    expect(snapshot.isActive).toBe(false);
    expect(snapshot.expiresAt).toEqual(new Date(iso(-DAY_MS)));
  });

  it("is inactive exactly at the expiry boundary", () => {
    const snapshot = toEntitlement(
      subscriberPayload({ expiresDate: RECEIVED_AT.toISOString() }),
      "premium",
      RECEIVED_AT
    );

    expect(snapshot.isActive).toBe(false);
  });

  it("reads the sandbox environment from the subscribing product", () => {
    const sandbox = toEntitlement(subscriberPayload({ isSandbox: true }), "premium", RECEIVED_AT);
    expect(sandbox.environment).toBe("SANDBOX");
  });

  it("reads the environment of the entitlement's own product, not of another product", () => {
    const payload = subscriberPayload({
      isSandbox: true,
      subscriptions: {
        "com.example.premium.monthly": {
          purchase_date: iso(-30 * DAY_MS),
          expires_date: iso(30 * DAY_MS),
          is_sandbox: true,
          store: "app_store"
        },
        "com.example.other.yearly": {
          purchase_date: iso(-30 * DAY_MS),
          expires_date: iso(30 * DAY_MS),
          is_sandbox: false,
          store: "app_store"
        }
      }
    });

    expect(toEntitlement(payload, "premium", RECEIVED_AT).environment).toBe("SANDBOX");
  });

  it("treats an entitlement whose product has no purchase evidence as absent", () => {
    const payload = subscriberPayload({ subscriptions: {} });

    expect(toEntitlement(payload, "premium", RECEIVED_AT)).toMatchObject({
      isActive: false,
      expiresAt: null,
      productId: null,
      store: null,
      environment: null
    });
  });

  it("is inactive for an entitlement object with no product and no expiry", () => {
    const payload = {
      request_date_ms: RECEIVED_AT_MS,
      subscriber: { entitlements: { premium: {} }, subscriptions: {} }
    };

    expect(toEntitlement(payload, "premium", RECEIVED_AT)).toMatchObject({
      isActive: false,
      expiresAt: null,
      productId: null,
      environment: null
    });
  });

  it("requires purchase evidence for a lifetime entitlement", () => {
    const withoutPurchase = {
      request_date_ms: RECEIVED_AT_MS,
      subscriber: {
        entitlements: { premium: { expires_date: null, product_identifier: "com.example.premium.lifetime" } },
        subscriptions: {},
        non_subscriptions: {}
      }
    };
    expect(toEntitlement(withoutPurchase, "premium", RECEIVED_AT)).toMatchObject({
      isActive: false,
      expiresAt: null,
      productId: null
    });

    const withPurchase = {
      request_date_ms: RECEIVED_AT_MS,
      subscriber: {
        entitlements: { premium: { expires_date: null, product_identifier: "com.example.premium.lifetime" } },
        subscriptions: {},
        non_subscriptions: {
          "com.example.premium.lifetime": [
            { id: "tx-1", purchase_date: iso(-60 * DAY_MS), store: "app_store", is_sandbox: false }
          ]
        }
      }
    };
    expect(toEntitlement(withPurchase, "premium", RECEIVED_AT)).toMatchObject({
      isActive: true,
      expiresAt: null,
      productId: "com.example.premium.lifetime",
      store: "app_store",
      environment: "PRODUCTION"
    });
  });

  it("does not treat a dated entitlement backed only by a non-subscription purchase as active", () => {
    const payload = {
      request_date_ms: RECEIVED_AT_MS,
      subscriber: {
        entitlements: {
          premium: { expires_date: iso(30 * DAY_MS), product_identifier: "com.example.coins" }
        },
        subscriptions: {},
        non_subscriptions: { "com.example.coins": [{ id: "tx-1", purchase_date: iso(-DAY_MS), is_sandbox: false }] }
      }
    };

    expect(toEntitlement(payload, "premium", RECEIVED_AT).isActive).toBe(false);
  });

  it("does not accept an empty purchase object as evidence", () => {
    const emptyPurchase = {
      request_date_ms: RECEIVED_AT_MS,
      subscriber: {
        entitlements: { premium: { expires_date: null, product_identifier: "p" } },
        subscriptions: {},
        non_subscriptions: { p: [{}] }
      }
    };

    expect(toEntitlement(emptyPurchase, "premium", RECEIVED_AT)).toMatchObject({
      isActive: false,
      expiresAt: null,
      productId: null,
      store: null,
      environment: null
    });
  });

  it("does not accept a purchase without a parseable purchase date as evidence", () => {
    for (const entry of [{ id: "tx-1" }, { id: "tx-1", purchase_date: "not-a-date" }, { id: "tx-1", purchase_date: 42 }]) {
      const payload = {
        request_date_ms: RECEIVED_AT_MS,
        subscriber: {
          entitlements: { premium: { expires_date: null, product_identifier: "p" } },
          subscriptions: {},
          non_subscriptions: { p: [entry] }
        }
      };
      expect(toEntitlement(payload, "premium", RECEIVED_AT).isActive).toBe(false);
    }
  });

  it("does not accept a subscription with an omitted expiry as lifetime evidence", () => {
    const payload = {
      request_date_ms: RECEIVED_AT_MS,
      subscriber: {
        entitlements: { premium: { expires_date: null, product_identifier: "p" } },
        subscriptions: { p: { purchase_date: iso(-30 * DAY_MS), is_sandbox: false } },
        non_subscriptions: {}
      }
    };

    expect(toEntitlement(payload, "premium", RECEIVED_AT)).toMatchObject({ isActive: false, expiresAt: null });
  });

  it("does not accept a subscription with an unreadable expiry as evidence", () => {
    const payload = {
      request_date_ms: RECEIVED_AT_MS,
      subscriber: {
        entitlements: { premium: { expires_date: null, product_identifier: "p" } },
        subscriptions: { p: { purchase_date: iso(-30 * DAY_MS), expires_date: "not-a-date" } },
        non_subscriptions: {}
      }
    };

    expect(toEntitlement(payload, "premium", RECEIVED_AT)).toMatchObject({ isActive: false, expiresAt: null });
  });

  it("takes the snapshot time from the upstream response", () => {
    const payload = { ...subscriberPayload(), request_date_ms: RECEIVED_AT_MS - 60_000 };

    const snapshot = toEntitlement(payload, "premium", RECEIVED_AT);

    expect(snapshot.upstreamAt).toEqual(new Date(RECEIVED_AT_MS - 60_000));
    expect(snapshot.syncedAt).toEqual(RECEIVED_AT);
  });

  it("treats an absent subscriber as an inactive row stamped with the receive clock", () => {
    expect(toEntitlement(null, "premium", RECEIVED_AT)).toEqual({
      entitlementId: "premium",
      isActive: false,
      expiresAt: null,
      productId: null,
      store: null,
      environment: null,
      upstreamAt: RECEIVED_AT,
      syncedAt: RECEIVED_AT
    });
  });

  it("treats an empty subscriber as an inactive row", () => {
    const snapshot = toEntitlement({ subscriber: { entitlements: {}, subscriptions: {} } }, "premium", RECEIVED_AT);

    expect(snapshot).toMatchObject({ isActive: false, environment: null, upstreamAt: RECEIVED_AT });
  });
});

describe("createRevenueCatClient", () => {
  const options = {
    apiKey: "rc-secret-key-for-tests",
    entitlementId: "premium",
    now: () => RECEIVED_AT_MS,
    baseUrl: "https://api.revenuecat.com"
  };

  it("reads the subscriber through the REST v1 endpoint with bearer auth", async () => {
    const fetchImpl = vi.fn(async () => new Response(JSON.stringify(subscriberPayload({ isSandbox: true })), { status: 200 }));
    const client = createRevenueCatClient({ ...options, fetchImpl });

    const snapshot = await client.readEntitlement("account-a");

    expect(snapshot).toMatchObject({ isActive: true, environment: "SANDBOX" });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe("https://api.revenuecat.com/v1/subscribers/account-a");
    expect((init.headers as Record<string, string>).Authorization).toBe(`Bearer ${options.apiKey}`);
  });

  it("reads a 404 as an absent subscriber stamped with the receive clock", async () => {
    const client = createRevenueCatClient({ ...options, fetchImpl: vi.fn(async () => new Response(null, { status: 404 })) });

    const snapshot = await client.readEntitlement("account-a");

    expect(snapshot).toMatchObject({
      isActive: false,
      expiresAt: null,
      environment: null,
      upstreamAt: RECEIVED_AT,
      syncedAt: RECEIVED_AT
    });
  });

  it("throws when a 200 body cannot be parsed", async () => {
    const client = createRevenueCatClient({ ...options, fetchImpl: vi.fn(async () => new Response("{ nope", { status: 200 })) });

    await expect(client.readEntitlement("account-a")).rejects.toBeInstanceOf(RevenueCatRequestError);
  });

  it("throws when a 200 body is not a subscriber payload", async () => {
    for (const body of ["null", "[]", "{}", JSON.stringify({ subscriber: "nope" }), JSON.stringify({ subscriber: { subscriptions: 3 } })]) {
      const client = createRevenueCatClient({ ...options, fetchImpl: vi.fn(async () => new Response(body, { status: 200 })) });
      await expect(client.readEntitlement("account-a")).rejects.toBeInstanceOf(RevenueCatRequestError);
    }
  });

  it("throws when the body read aborts after the response headers", async () => {
    const fetchImpl = vi.fn(async () => {
      const stream = new ReadableStream({
        start(controller) {
          controller.error(Object.assign(new Error("aborted"), { name: "AbortError" }));
        }
      });
      return new Response(stream, { status: 200, headers: { "content-type": "application/json" } });
    });
    const client = createRevenueCatClient({ ...options, fetchImpl });

    await expect(client.readEntitlement("account-a")).rejects.toBeInstanceOf(RevenueCatRequestError);
  });

  it("maps a large but bounded document of many consumable purchases to active", async () => {
    const purchases = Array.from({ length: 13_000 }, (_, index) => ({
      id: `tx-${index}`,
      purchase_date: iso(-30 * DAY_MS),
      store: "app_store",
      is_sandbox: false
    }));
    const body = JSON.stringify({
      request_date_ms: RECEIVED_AT_MS,
      subscriber: {
        entitlements: { premium: { expires_date: null, product_identifier: "p" } },
        subscriptions: {},
        non_subscriptions: { p: purchases }
      }
    });
    expect(Buffer.byteLength(body)).toBeGreaterThan(1_200_000);

    const client = createRevenueCatClient({ ...options, fetchImpl: vi.fn(async () => new Response(body, { status: 200 })) });

    expect(await client.readEntitlement("account-a")).toMatchObject({
      isActive: true,
      expiresAt: null,
      productId: "p",
      store: "app_store"
    });
  });

  it("throws when the body exceeds the size cap", async () => {
    const oversized = JSON.stringify({ subscriber: { entitlements: {}, subscriptions: {} } }).padEnd(16 * 1024 * 1024 + 1024, " ");
    const client = createRevenueCatClient({ ...options, fetchImpl: vi.fn(async () => new Response(oversized, { status: 200 })) });

    await expect(client.readEntitlement("account-a")).rejects.toBeInstanceOf(RevenueCatRequestError);
  });

  it("throws on a server error without leaking the key", async () => {
    const client = createRevenueCatClient({ ...options, fetchImpl: vi.fn(async () => new Response(null, { status: 500 })) });

    const error = await client.readEntitlement("account-a").catch((caught: unknown) => caught);

    expect(error).toBeInstanceOf(RevenueCatRequestError);
    expect((error as Error).message).not.toContain(options.apiKey);
  });

  it("throws when the request times out", async () => {
    const fetchImpl = vi.fn(async () => {
      throw Object.assign(new Error("The operation was aborted"), { name: "AbortError" });
    });
    const client = createRevenueCatClient({ ...options, fetchImpl });

    await expect(client.readEntitlement("account-a")).rejects.toBeInstanceOf(RevenueCatRequestError);
  });
});
