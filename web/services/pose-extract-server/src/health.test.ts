import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import request from "supertest";
import { afterEach, describe, expect, it, vi } from "vitest";

import { createApp } from "./app";
import type { ProviderAuthHealth } from "./services/providerAuthHealth";

const tempDirs: string[] = [];

async function makeEmptyHome(): Promise<string> {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "hf-health-app-"));
  tempDirs.push(dir);
  return dir;
}

function healthStub(health: ProviderAuthHealth) {
  return () => Promise.resolve(health);
}

afterEach(async () => {
  vi.unstubAllEnvs();
  await Promise.all(tempDirs.splice(0).map((dir) => fs.rm(dir, { recursive: true, force: true })));
});

describe("GET /api/health", () => {
  it("returns status, uptime, version and a not_configured provider section by default", async () => {
    vi.stubEnv("HIGGSFIELD_CREDENTIALS_PATH", "");
    vi.stubEnv("HOME", await makeEmptyHome());
    const app = createApp({ version: "1.2.3" });

    const response = await request(app).get("/api/health");

    expect(response.status).toBe(200);
    expect(response.body).toEqual({
      status: "ok",
      uptime: expect.any(Number),
      version: "1.2.3",
      provider: {
        enabled: false,
        state: "not_configured",
        expiresInSec: null,
        lastAuthError: null
      }
    });
    expect(response.body.uptime).toBeGreaterThanOrEqual(0);
  });

  it("reports ok when the credential is healthy", async () => {
    const app = createApp({
      version: "1.2.3",
      providerAuthHealth: healthStub({ enabled: true, state: "ok", expiresInSec: 90000, lastAuthError: null })
    });

    const response = await request(app).get("/api/health");

    expect(response.status).toBe(200);
    expect(response.body.status).toBe("ok");
    expect(response.body.provider).toMatchObject({ state: "ok", expiresInSec: 90000 });
  });

  it("warns but stays 200 when the credential expires within a day", async () => {
    const app = createApp({
      version: "1.2.3",
      providerAuthHealth: healthStub({ enabled: true, state: "expiring_soon", expiresInSec: 3600, lastAuthError: null })
    });

    const response = await request(app).get("/api/health");

    expect(response.status).toBe(200);
    expect(response.body.status).toBe("warn");
  });

  it.each(["expired", "missing", "invalid"] as const)(
    "reports degraded but keeps HTTP 200 when the credential is %s",
    async (state) => {
      const app = createApp({
        version: "1.2.3",
        providerAuthHealth: healthStub({ enabled: true, state, expiresInSec: null, lastAuthError: null })
      });

      const response = await request(app).get("/api/health");

      // Railway's healthcheck must never restart the container over provider auth: jobs fail
      // closed on their own, the API stays up.
      expect(response.status).toBe(200);
      expect(response.body.status).toBe("degraded");
      expect(response.body.provider.state).toBe(state);
    }
  );

  it("reports degraded when the last CLI call failed auth", async () => {
    const app = createApp({
      version: "1.2.3",
      providerAuthHealth: healthStub({
        enabled: true,
        state: "ok",
        expiresInSec: 90000,
        lastAuthError: { at: "2026-11-04T10:00:00.000Z", code: "PROVIDER_AUTH_REQUIRED" }
      })
    });

    const response = await request(app).get("/api/health");

    expect(response.status).toBe(200);
    expect(response.body.status).toBe("degraded");
    expect(response.body.provider.lastAuthError).toEqual({
      at: "2026-11-04T10:00:00.000Z",
      code: "PROVIDER_AUTH_REQUIRED"
    });
  });
});

describe("GET /api/health/provider", () => {
  it("answers 200 while healthy or merely expiring soon", async () => {
    const healthy = createApp({
      providerAuthHealth: healthStub({ enabled: true, state: "ok", expiresInSec: 90000, lastAuthError: null })
    });
    const warning = createApp({
      providerAuthHealth: healthStub({ enabled: true, state: "expiring_soon", expiresInSec: 60, lastAuthError: null })
    });

    expect((await request(healthy).get("/api/health/provider")).status).toBe(200);
    expect((await request(warning).get("/api/health/provider")).status).toBe(200);
  });

  it("answers 503 when degraded so an external uptime monitor can alert", async () => {
    const app = createApp({
      providerAuthHealth: healthStub({ enabled: true, state: "expired", expiresInSec: -60, lastAuthError: null })
    });

    const response = await request(app).get("/api/health/provider");

    expect(response.status).toBe(503);
    expect(response.body).toMatchObject({ status: "degraded", provider: { state: "expired" } });
  });

  it("answers 200 when no provider credential is configured at all", async () => {
    vi.stubEnv("HIGGSFIELD_CREDENTIALS_PATH", "");
    vi.stubEnv("HOME", await makeEmptyHome());
    const app = createApp({});

    expect((await request(app).get("/api/health/provider")).status).toBe(200);
  });
});
