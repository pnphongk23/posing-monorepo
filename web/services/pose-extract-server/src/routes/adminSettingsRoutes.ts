import { Router } from "express";
import { z } from "zod";

import type { ProviderSettingsStore } from "../db/providerSettingsStore";
import { createAdminAuthMiddleware } from "../middleware/adminAuth";
import { createAdminRateLimitMiddleware } from "../middleware/adminRateLimit";
import { isExtractionProviderId } from "../services/poseExtractorProvider";

const setProviderSchema = z.object({
  provider: z.string().trim().min(1)
});

function badRequest(message: string) {
  return {
    error: {
      code: "BAD_REQUEST",
      message
    }
  };
}

interface CreateAdminSettingsRoutesOptions {
  adminSecret: string;
  providerSettingsStore: ProviderSettingsStore;
  rateLimitWindowMs?: number;
  rateLimitMaxRequests?: number;
}

export function createAdminSettingsRoutes(options: CreateAdminSettingsRoutesOptions): Router {
  const router = Router();
  const auth = createAdminAuthMiddleware(options.adminSecret);
  const rateLimit = createAdminRateLimitMiddleware({
    windowMs: options.rateLimitWindowMs,
    maxRequests: options.rateLimitMaxRequests
  });

  router.use(rateLimit);
  router.use(auth);

  router.get("/extraction-provider", async (_req, res) => {
    const provider = await options.providerSettingsStore.getActiveProvider();
    res.json({ data: { provider } });
  });

  router.put("/extraction-provider", async (req, res) => {
    const parsed = setProviderSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json(badRequest("Invalid provider payload"));
      return;
    }

    if (!isExtractionProviderId(parsed.data.provider)) {
      res.status(400).json(badRequest("Unsupported extraction provider"));
      return;
    }

    const provider = await options.providerSettingsStore.setProvider(parsed.data.provider);
    res.json({ data: { provider } });
  });

  return router;
}
