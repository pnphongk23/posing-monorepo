import { Router } from "express";
import { z } from "zod";

import { createAdminAuthMiddleware } from "../middleware/adminAuth";
import { createAdminRateLimitMiddleware } from "../middleware/adminRateLimit";
import type { ApiKeyRecord, KeyStore } from "../services/keyStore";

const createKeySchema = z.object({
  name: z.string().trim().min(1),
  apiKey: z.string().trim().min(1)
});

const updateKeyStatusSchema = z.object({
  status: z.enum(["active", "disabled", "exhausted"])
});

function badRequest(message: string) {
  return {
    error: {
      code: "BAD_REQUEST",
      message
    }
  };
}

function notFound(message: string) {
  return {
    error: {
      code: "NOT_FOUND",
      message
    }
  };
}

interface CreateAdminRoutesOptions {
  adminSecret: string;
  keyStore: KeyStore;
  rateLimitWindowMs?: number;
  rateLimitMaxRequests?: number;
}

function toPublicKeyRecord(record: ApiKeyRecord) {
  return {
    id: record.id,
    name: record.name,
    status: record.status,
    requestsToday: record.requestsToday,
    createdAt: record.createdAt,
    lastUsedAt: record.lastUsedAt
  };
}

export function createAdminRoutes(options: CreateAdminRoutesOptions): Router {
  const router = Router();
  const auth = createAdminAuthMiddleware(options.adminSecret);
  const rateLimit = createAdminRateLimitMiddleware({
    windowMs: options.rateLimitWindowMs,
    maxRequests: options.rateLimitMaxRequests
  });

  router.use(rateLimit);
  router.use(auth);

  router.get("/keys", async (_req, res) => {
    const keys = await options.keyStore.listKeys();
    res.json({ data: keys.map(toPublicKeyRecord) });
  });

  router.post("/keys", async (req, res) => {
    const parsed = createKeySchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json(badRequest("Invalid key payload"));
      return;
    }

    const created = await options.keyStore.createKey(parsed.data);
    res.status(201).json({ data: toPublicKeyRecord(created) });
  });

  router.patch("/keys/:id", async (req, res) => {
    const parsed = updateKeyStatusSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json(badRequest("Invalid status payload"));
      return;
    }

    const updated = await options.keyStore.updateKeyStatus(req.params.id, parsed.data.status);
    if (!updated) {
      res.status(404).json(notFound("API key not found"));
      return;
    }

    res.json({ data: toPublicKeyRecord(updated) });
  });

  router.delete("/keys/:id", async (req, res) => {
    const deleted = await options.keyStore.deleteKey(req.params.id);
    if (!deleted) {
      res.status(404).json(notFound("API key not found"));
      return;
    }

    res.status(204).send();
  });

  router.post("/keys/reset", async (_req, res) => {
    const updated = await options.keyStore.resetDailyCounters();
    res.json({ data: { updated } });
  });

  return router;
}
