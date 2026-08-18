import request from "supertest";
import { describe, expect, it } from "vitest";

import { createApp } from "./app";
import { setupTestDatabase } from "./db/testDb";
import { KeyStore } from "./services/keyStore";

const ADMIN_SECRET = "super-secret-token";

interface TestAdminAppOptions {
  adminRateLimitWindowMs?: number;
  adminRateLimitMaxRequests?: number;
}

async function createAdminApp(options: TestAdminAppOptions = {}) {
  const sql = await setupTestDatabase();
  const keyStore = new KeyStore(sql);
  const app = createApp({
    version: "1.0.0-test",
    adminSecret: ADMIN_SECRET,
    keyStore,
    adminRateLimitWindowMs: options.adminRateLimitWindowMs,
    adminRateLimitMaxRequests: options.adminRateLimitMaxRequests
  });

  return { app, keyStore };
}

describe("Admin auth middleware", () => {
  it("rejects missing bearer token", async () => {
    const { app } = await createAdminApp();

    const response = await request(app).get("/api/admin/keys");

    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("UNAUTHORIZED");
  });

  it("rejects invalid bearer token", async () => {
    const { app } = await createAdminApp();

    const response = await request(app)
      .get("/api/admin/keys")
      .set("Authorization", "Bearer wrong-token");

    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("UNAUTHORIZED");
  });

  it("accepts bearer scheme case-insensitively", async () => {
    const { app } = await createAdminApp();

    const response = await request(app)
      .get("/api/admin/keys")
      .set("Authorization", `bearer ${ADMIN_SECRET}`);

    expect(response.status).toBe(200);
    expect(response.body.data).toEqual([]);
  });

  it("rate limits brute-force attempts on admin routes", async () => {
    const { app } = await createAdminApp({
      adminRateLimitWindowMs: 60_000,
      adminRateLimitMaxRequests: 2
    });

    const first = await request(app).get("/api/admin/keys");
    const second = await request(app).get("/api/admin/keys");
    const third = await request(app).get("/api/admin/keys");

    expect(first.status).toBe(401);
    expect(second.status).toBe(401);
    expect(third.status).toBe(429);
    expect(third.body.error.code).toBe("RATE_LIMITED");
  });
});

describe("Admin key endpoints", () => {
  it("supports list/create/update/delete flow", async () => {
    const { app } = await createAdminApp();

    const createResponse = await request(app)
      .post("/api/admin/keys")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send({
        name: "Prod Key 1",
        apiKey: "AIza-123"
      });

    expect(createResponse.status).toBe(201);
    expect(createResponse.body.data.status).toBe("active");
    expect(createResponse.body.data.apiKey).toBeUndefined();

    const keyId: string = createResponse.body.data.id;
    const listResponse = await request(app)
      .get("/api/admin/keys")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`);
    expect(listResponse.status).toBe(200);
    expect(listResponse.body.data).toHaveLength(1);
    expect(listResponse.body.data[0].apiKey).toBeUndefined();

    const patchResponse = await request(app)
      .patch(`/api/admin/keys/${keyId}`)
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send({ status: "disabled" });
    expect(patchResponse.status).toBe(200);
    expect(patchResponse.body.data.status).toBe("disabled");
    expect(patchResponse.body.data.apiKey).toBeUndefined();

    const deleteResponse = await request(app)
      .delete(`/api/admin/keys/${keyId}`)
      .set("Authorization", `Bearer ${ADMIN_SECRET}`);
    expect(deleteResponse.status).toBe(204);

    const finalListResponse = await request(app)
      .get("/api/admin/keys")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`);
    expect(finalListResponse.body.data).toHaveLength(0);
  });

  it("trims payload fields and rejects whitespace-only inputs", async () => {
    const { app, keyStore } = await createAdminApp();

    const createTrimmed = await request(app)
      .post("/api/admin/keys")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send({
        name: "  Prod Key 2  ",
        apiKey: "  AIza-trimmed  "
      });

    expect(createTrimmed.status).toBe(201);
    expect(createTrimmed.body.data.name).toBe("Prod Key 2");
    expect(createTrimmed.body.data.apiKey).toBeUndefined();
    expect((await keyStore.listKeys())[0]?.apiKey).toBe("AIza-trimmed");

    const createWhitespaceOnly = await request(app)
      .post("/api/admin/keys")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send({
        name: "   ",
        apiKey: "\t"
      });

    expect(createWhitespaceOnly.status).toBe(400);
    expect(createWhitespaceOnly.body.error.code).toBe("BAD_REQUEST");
  });

  it("returns proper errors for invalid input and missing key IDs", async () => {
    const { app } = await createAdminApp();

    const invalidStatus = await request(app)
      .patch("/api/admin/keys/some-id")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send({ status: "unknown" });
    expect(invalidStatus.status).toBe(400);
    expect(invalidStatus.body.error.code).toBe("BAD_REQUEST");

    const patchNotFound = await request(app)
      .patch("/api/admin/keys/missing-id")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`)
      .send({ status: "disabled" });
    expect(patchNotFound.status).toBe(404);
    expect(patchNotFound.body.error.code).toBe("NOT_FOUND");

    const deleteNotFound = await request(app)
      .delete("/api/admin/keys/missing-id")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`);
    expect(deleteNotFound.status).toBe(404);
    expect(deleteNotFound.body.error.code).toBe("NOT_FOUND");
  });

  it("resets requests_today and reactivates exhausted keys only", async () => {
    const { app, keyStore } = await createAdminApp();
    const active = await keyStore.createKey({ name: "Active", apiKey: "key-active" });
    const exhausted = await keyStore.createKey({ name: "Exhausted", apiKey: "key-exhausted" });
    const disabled = await keyStore.createKey({ name: "Disabled", apiKey: "key-disabled" });
    await keyStore.incrementRequestsToday(active.id);
    await keyStore.incrementRequestsToday(exhausted.id);
    await keyStore.incrementRequestsToday(disabled.id);
    await keyStore.updateKeyStatus(exhausted.id, "exhausted");
    await keyStore.updateKeyStatus(disabled.id, "disabled");

    const resetResponse = await request(app)
      .post("/api/admin/keys/reset")
      .set("Authorization", `Bearer ${ADMIN_SECRET}`);

    expect(resetResponse.status).toBe(200);
    expect(resetResponse.body.data.updated).toBe(3);

    const keys = await keyStore.listKeys();
    const activeAfterReset = keys.find((item) => item.id === active.id);
    const exhaustedAfterReset = keys.find((item) => item.id === exhausted.id);
    const disabledAfterReset = keys.find((item) => item.id === disabled.id);

    expect(activeAfterReset?.requestsToday).toBe(0);
    expect(activeAfterReset?.status).toBe("active");
    expect(exhaustedAfterReset?.requestsToday).toBe(0);
    expect(exhaustedAfterReset?.status).toBe("active");
    expect(disabledAfterReset?.requestsToday).toBe(0);
    expect(disabledAfterReset?.status).toBe("disabled");
  });
});
