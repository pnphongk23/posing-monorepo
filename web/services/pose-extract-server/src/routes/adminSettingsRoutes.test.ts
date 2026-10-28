import request from "supertest";
import { describe, expect, it } from "vitest";

import { createApp } from "../app";
import { setupTestDatabase } from "../db/testDb";
import { ProviderSettingsStore } from "../db/providerSettingsStore";
import { KeyStore } from "../services/keyStore";

const ADMIN_SECRET = "super-secret-token";

async function createSettingsApp() {
  const sql = await setupTestDatabase();
  const keyStore = new KeyStore(sql);
  const providerSettingsStore = new ProviderSettingsStore(sql);
  const app = createApp({
    version: "1.0.0-test",
    adminSecret: ADMIN_SECRET,
    keyStore,
    providerSettingsStore
  });

  return { app, providerSettingsStore };
}

describe("Admin extraction-provider settings", () => {
  it("returns higgsfield_cli by default", async () => {
    const { app } = await createSettingsApp();

    const response = await request(app)
      .get("/api/admin/settings/extraction-provider")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`);

    expect(response.status).toBe(200);
    expect(response.body.data.provider).toBe("higgsfield_cli");
  });

  it("persists supported provider changes", async () => {
    const { app } = await createSettingsApp();

    const putResponse = await request(app)
      .put("/api/admin/settings/extraction-provider")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send({ provider: "higgsfield_cli" });

    expect(putResponse.status).toBe(200);
    expect(putResponse.body.data.provider).toBe("higgsfield_cli");

    const getResponse = await request(app)
      .get("/api/admin/settings/extraction-provider")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`);

    expect(getResponse.status).toBe(200);
    expect(getResponse.body.data.provider).toBe("higgsfield_cli");
  });

  it("rejects unsupported provider without changing stored value", async () => {
    const { app, providerSettingsStore } = await createSettingsApp();
    await providerSettingsStore.setProvider("gemini_native");

    const response = await request(app)
      .put("/api/admin/settings/extraction-provider")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send({ provider: "unknown_provider" });

    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe("BAD_REQUEST");
    expect(await providerSettingsStore.getActiveProvider()).toBe("gemini_native");
  });

  it("rejects missing provider payload", async () => {
    const { app } = await createSettingsApp();

    const response = await request(app)
      .put("/api/admin/settings/extraction-provider")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send({});

    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe("BAD_REQUEST");
  });

  it("requires admin auth", async () => {
    const { app } = await createSettingsApp();

    const response = await request(app).get("/api/admin/settings/extraction-provider");

    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("UNAUTHORIZED");
  });
});
