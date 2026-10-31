import express from "express";
import request from "supertest";
import { describe, expect, it, vi } from "vitest";

import { createApp } from "../app";
import type { AccountStore } from "../db/accountStore";
import type { SavedStore } from "../db/savedStore";
import { createAccountAuthMiddleware } from "../middleware/accountAuth";
import { createSavedRoutes } from "./savedRoutes";

const ACCOUNT = { id: "11111111-1111-4111-8111-111111111111", displayName: "User", createdAt: "2026-01-01T00:00:00.000Z" };
const POSE = { poseId: "22222222-2222-4222-8222-222222222222", name: "Pose", originalUrl: "original", skeletonUrl: "skeleton", thumbnailUrl: "thumbnail", tags: [], difficulty: null, description: null, bodyParts: [], status: "published" as const, createdAt: "2026-01-01T00:00:00.000Z", downloadCount: 0 };

function accountMiddleware() {
  return (_req: express.Request, _res: express.Response, next: express.NextFunction) => {
    _req.account = ACCOUNT;
    next();
  };
}

function routeApp(store: Partial<SavedStore>) {
  return express().use(express.json()).use("/api/me/saved", accountMiddleware(), createSavedRoutes(store as SavedStore));
}

describe("protected saved routes", () => {
  it("lists public projections with pagination and saves idempotently", async () => {
    const store = { list: vi.fn().mockResolvedValue({ poses: [POSE], total: 1 }), save: vi.fn().mockResolvedValue(POSE), remove: vi.fn() };
    const app = routeApp(store);

    const list = await request(app).get("/api/me/saved?page=2&limit=5").expect(200);
    const { createdAt, originalUrl, ...projectionPose } = POSE;
    expect(list.body).toEqual({ data: [{ ...projectionPose, thumbnailUrl: originalUrl, uploadedAt: createdAt }], pagination: { page: 2, limit: 5, total: 1 } });
    expect(list.body.data[0]).not.toHaveProperty("originalUrl");
    expect(list.body.data[0]).not.toHaveProperty("ownerAccountId");
    await request(app).put(`/api/me/saved/${POSE.poseId}`).expect(200);
    expect(store.save).toHaveBeenCalledWith(ACCOUNT.id, POSE.poseId);
  });

  it("returns 404 for invalid targets without creating an entry and deletes idempotently", async () => {
    const store = { list: vi.fn(), save: vi.fn().mockResolvedValue(null), remove: vi.fn().mockResolvedValue(undefined) };
    const app = routeApp(store);

    await request(app).put(`/api/me/saved/${POSE.poseId}`).expect(404).expect({ error: { code: "NOT_FOUND", message: "Pose not found" } });
    await request(app).delete(`/api/me/saved/${POSE.poseId}`).expect(204);
    await request(app).delete(`/api/me/saved/${POSE.poseId}`).expect(204);
    expect(store.remove).toHaveBeenCalledTimes(2);
  });

  it("scopes every verb to the authenticated account, ignoring caller-supplied account ids", async () => {
    const store = { list: vi.fn().mockResolvedValue({ poses: [], total: 0 }), save: vi.fn().mockResolvedValue(null), remove: vi.fn().mockResolvedValue(undefined) };
    const app = routeApp(store);
    const FOREIGN_ACCOUNT = "99999999-9999-4999-8999-999999999999";

    await request(app).get(`/api/me/saved?accountId=${FOREIGN_ACCOUNT}&account_id=${FOREIGN_ACCOUNT}`).expect(200);
    await request(app).put(`/api/me/saved/${POSE.poseId}?accountId=${FOREIGN_ACCOUNT}`).send({ accountId: FOREIGN_ACCOUNT }).expect(404);
    await request(app).delete(`/api/me/saved/${POSE.poseId}`).send({ accountId: FOREIGN_ACCOUNT }).expect(204);

    expect(store.list).toHaveBeenCalledWith(ACCOUNT.id, 1, 20);
    expect(store.save).toHaveBeenCalledWith(ACCOUNT.id, POSE.poseId);
    expect(store.remove).toHaveBeenCalledWith(ACCOUNT.id, POSE.poseId);
  });

  it("mounts through the existing Account auth boundary and returns its 401 envelope", async () => {
    const accountStore = { upsert: vi.fn(), getById: vi.fn() } as unknown as AccountStore;
    const savedStore = {} as SavedStore;
    const app = createApp({ version: "test", accountStore, supabaseUrl: "https://example.supabase.co", savedStore });

    await request(app).get("/api/me/saved").expect(401).expect({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
    await request(app).put(`/api/me/saved/${POSE.poseId}`).expect(401).expect({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
    await request(app).delete(`/api/me/saved/${POSE.poseId}`).expect(401).expect({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
  });
});
