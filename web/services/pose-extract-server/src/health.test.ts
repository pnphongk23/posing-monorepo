import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import request from "supertest";
import { afterEach, describe, expect, it, vi } from "vitest";

import { createApp } from "./app";
import { resetProviderAuthHealthMemory, type ProviderAuthHealth } from "./services/providerAuthHealth";
import { providerAuthStatePathFor, recordProviderAuthFailure } from "./services/providerAuthStateFile";

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
  resetProviderAuthHealthMemory();
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
        lastAuthError: null,
        lastSuccessAt: null
      }
    });
    expect(response.body.uptime).toBeGreaterThanOrEqual(0);
  });

  it("reports ok when the credential is healthy", async () => {
    const app = createApp({
      version: "1.2.3",
      providerAuthHealth: healthStub({
        enabled: true,
        state: "ok",
        expiresInSec: 90000,
        lastAuthError: null,
        lastSuccessAt: null
      })
    });

    const response = await request(app).get("/api/health");

    expect(response.status).toBe(200);
    expect(response.body.status).toBe("ok");
    expect(response.body.provider).toMatchObject({ state: "ok", expiresInSec: 90000 });
  });

  it("stays ok while the 24h access token is about to expire, because the CLI refreshes it", async () => {
    const app = createApp({
      version: "1.2.3",
      providerAuthHealth: healthStub({
        enabled: true,
        state: "expiring_soon",
        expiresInSec: 3600,
        lastAuthError: null,
        lastSuccessAt: null
      })
    });

    const response = await request(app).get("/api/health");

    expect(response.status).toBe(200);
    expect(response.body.status).toBe("ok");
  });

  it("warns without 503 once the token has been expired for more than 48 hours", async () => {
    const app = createApp({
      providerAuthHealth: healthStub({
        enabled: true,
        state: "expired",
        expiresInSec: -49 * 3600,
        lastAuthError: null,
        lastSuccessAt: null
      })
    });

    const health = await request(app).get("/api/health");
    const provider = await request(app).get("/api/health/provider");

    expect(health.body.status).toBe("warn");
    expect(health.status).toBe(200);
    expect(provider.status).toBe(200);
  });

  it.each(["missing", "invalid"] as const)(
    "reports degraded but keeps HTTP 200 when the credential is %s",
    async (state) => {
      const app = createApp({
        version: "1.2.3",
        providerAuthHealth: healthStub({
          enabled: true,
          state,
          expiresInSec: null,
          lastAuthError: null,
          lastSuccessAt: null
        })
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
        lastAuthError: { at: "2026-11-04T10:00:00.000Z", code: "PROVIDER_AUTH_REQUIRED" },
        lastSuccessAt: null
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

describe("GET /api/health across processes", () => {
  it("reflects an auth failure the worker recorded in the shared state file", async () => {
    const dir = await makeEmptyHome();
    const credentialsPath = path.join(dir, "credentials.json");
    await fs.writeFile(
      credentialsPath,
      JSON.stringify({
        access_token: "secret-access",
        refresh_token: "secret-refresh",
        expires_at: Math.floor(Date.now() / 1000) + 86400 * 3
      }),
      { mode: 0o600 }
    );
    vi.stubEnv("HIGGSFIELD_CREDENTIALS_PATH", credentialsPath);
    // The worker process wrote this; the API only has the file.
    await recordProviderAuthFailure({ statePath: providerAuthStatePathFor(credentialsPath), code: "PROVIDER_AUTH_REQUIRED" });

    const response = await request(createApp({ version: "1.2.3" })).get("/api/health");

    expect(response.status).toBe(200);
    expect(response.body.status).toBe("degraded");
    expect(response.body.provider.lastAuthError.code).toBe("PROVIDER_AUTH_REQUIRED");
  });
});

describe("GET /api/health/provider", () => {
  it("answers 200 while healthy or merely expiring soon", async () => {
    const healthy = createApp({
      providerAuthHealth: healthStub({
        enabled: true,
        state: "ok",
        expiresInSec: 90000,
        lastAuthError: null,
        lastSuccessAt: null
      })
    });
    const warning = createApp({
      providerAuthHealth: healthStub({
        enabled: true,
        state: "expiring_soon",
        expiresInSec: 60,
        lastAuthError: null,
        lastSuccessAt: null
      })
    });

    expect((await request(healthy).get("/api/health/provider")).status).toBe(200);
    expect((await request(warning).get("/api/health/provider")).status).toBe(200);
  });

  it("answers 503 when degraded so an external uptime monitor can alert", async () => {
    const app = createApp({
      providerAuthHealth: healthStub({
        enabled: true,
        state: "missing",
        expiresInSec: null,
        lastAuthError: null,
        lastSuccessAt: null
      })
    });

    const response = await request(app).get("/api/health/provider");

    expect(response.status).toBe(503);
    expect(response.body).toMatchObject({ status: "degraded", provider: { state: "missing" } });
  });

  it("answers 200 when no provider credential is configured at all", async () => {
    vi.stubEnv("HIGGSFIELD_CREDENTIALS_PATH", "");
    vi.stubEnv("HOME", await makeEmptyHome());
    const app = createApp({});

    expect((await request(app).get("/api/health/provider")).status).toBe(200);
  });
});
