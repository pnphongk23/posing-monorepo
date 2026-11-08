import { afterEach, describe, expect, it, vi } from "vitest";

import { dispatchProviderAuthAlert, resetProviderAlertState } from "./providerAlert";

const NOW_MS = 1_800_000_000_000;

afterEach(() => {
  resetProviderAlertState();
});

describe("dispatchProviderAuthAlert", () => {
  it("does nothing when ALERT_WEBHOOK_URL is not set", async () => {
    const fetchImpl = vi.fn();

    const sent = await dispatchProviderAuthAlert(
      { event: "provider_auth", status: "degraded", state: "expired", expiresInSec: -60 },
      { env: {}, fetchImpl: fetchImpl as unknown as typeof fetch, now: () => NOW_MS }
    );

    expect(sent).toBe(false);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("posts a short JSON body without secrets when the URL is configured", async () => {
    const fetchImpl = vi.fn().mockResolvedValue({ ok: true, status: 204 });

    const sent = await dispatchProviderAuthAlert(
      { event: "provider_auth", status: "degraded", state: "expired", expiresInSec: -60 },
      {
        env: { ALERT_WEBHOOK_URL: "https://hooks.example.com/abc" },
        fetchImpl: fetchImpl as unknown as typeof fetch,
        now: () => NOW_MS
      }
    );

    expect(sent).toBe(true);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const [url, init] = fetchImpl.mock.calls[0] as [string, RequestInit];
    expect(url).toBe("https://hooks.example.com/abc");
    expect(init.method).toBe("POST");
    expect(init.headers).toMatchObject({ "content-type": "application/json" });
    const body = JSON.parse(String(init.body)) as Record<string, unknown>;
    expect(body).toEqual({
      event: "provider_auth",
      status: "degraded",
      state: "expired",
      expiresInSec: -60,
      at: new Date(NOW_MS).toISOString()
    });
    expect(String(init.body)).not.toMatch(/access_token|refresh_token|secret/i);
  });

  it("debounces repeated alerts for the same transition", async () => {
    const fetchImpl = vi.fn().mockResolvedValue({ ok: true, status: 204 });
    const deps = {
      env: { ALERT_WEBHOOK_URL: "https://hooks.example.com/abc" },
      fetchImpl: fetchImpl as unknown as typeof fetch,
      now: () => NOW_MS
    };
    const payload = { event: "provider_auth", status: "degraded", state: "expired", expiresInSec: -60 } as const;

    expect(await dispatchProviderAuthAlert(payload, deps)).toBe(true);
    expect(await dispatchProviderAuthAlert(payload, deps)).toBe(false);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it("sends again after the debounce window", async () => {
    const fetchImpl = vi.fn().mockResolvedValue({ ok: true, status: 204 });
    const payload = { event: "provider_auth", status: "degraded", state: "expired", expiresInSec: -60 } as const;
    const baseDeps = { env: { ALERT_WEBHOOK_URL: "https://hooks.example.com/abc" }, fetchImpl: fetchImpl as unknown as typeof fetch };

    await dispatchProviderAuthAlert(payload, { ...baseDeps, now: () => NOW_MS });
    await dispatchProviderAuthAlert(payload, { ...baseDeps, now: () => NOW_MS + 7 * 60 * 60 * 1000 });

    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });

  it("never throws when the webhook fails", async () => {
    const fetchImpl = vi.fn().mockRejectedValue(new Error("network down"));

    await expect(
      dispatchProviderAuthAlert(
        { event: "provider_auth", status: "degraded", state: "missing", expiresInSec: null },
        {
          env: { ALERT_WEBHOOK_URL: "https://hooks.example.com/abc" },
          fetchImpl: fetchImpl as unknown as typeof fetch,
          now: () => NOW_MS
        }
      )
    ).resolves.toBe(false);
  });
});
