import express from "express";
import request from "supertest";
import { describe, expect, it } from "vitest";

import { createAccountOrAdminAuth } from "./accountOrAdminAuth";
import type { AccountRecord } from "../db/accountStore";

describe("createAccountOrAdminAuth middleware", () => {
  const adminSecret = "super-secret-admin-key";
  const dummyAccount: AccountRecord = {
    id: "account-uuid-1",
    displayName: "Test User",
    createdAt: "2026-01-01T00:00:00.000Z"
  };

  const mockAccountAuth: express.RequestHandler = (req, res, next) => {
    const authHeader = req.header("authorization");
    if (authHeader === "Bearer valid-account-jwt") {
      req.account = dummyAccount;
      next();
      return;
    }
    res.status(401).json({ error: { code: "UNAUTHORIZED", message: "Unauthorized" } });
  };

  function createApp(options = { adminSecret, accountAuth: mockAccountAuth }) {
    const app = express();
    const auth = createAccountOrAdminAuth(options);
    app.get("/test", auth, (req, res) => {
      res.json({
        ok: true,
        isAdmin: Boolean(req.isAdmin),
        account: req.account ?? null
      });
    });
    return app;
  }

  it("authenticates valid admin bearer and sets req.isAdmin", async () => {
    const app = createApp();
    const res = await request(app)
      .get("/test")
      .set("Authorization", `Bearer ${adminSecret}`);

    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      ok: true,
      isAdmin: true,
      account: null
    });
  });

  it("authenticates valid account bearer and sets req.account", async () => {
    const app = createApp();
    const res = await request(app)
      .get("/test")
      .set("Authorization", "Bearer valid-account-jwt");

    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      ok: true,
      isAdmin: false,
      account: dummyAccount
    });
  });

  it("returns 401 UNAUTHORIZED when no authorization header is provided", async () => {
    const app = createApp();
    const res = await request(app).get("/test");

    expect(res.status).toBe(401);
    expect(res.body).toEqual({
      error: { code: "UNAUTHORIZED", message: "Unauthorized" }
    });
  });

  it("falls through to account auth and gets 401 when wrong bearer is provided", async () => {
    const app = createApp();
    const res = await request(app)
      .get("/test")
      .set("Authorization", "Bearer invalid-token");

    expect(res.status).toBe(401);
    expect(res.body).toEqual({
      error: { code: "UNAUTHORIZED", message: "Unauthorized" }
    });
  });

  it("returns 401 when neither admin secret nor account auth is configured", async () => {
    const app = createApp({});
    const res = await request(app)
      .get("/test")
      .set("Authorization", "Bearer any-token");

    expect(res.status).toBe(401);
    expect(res.body).toEqual({
      error: { code: "UNAUTHORIZED", message: "Unauthorized" }
    });
  });
});
