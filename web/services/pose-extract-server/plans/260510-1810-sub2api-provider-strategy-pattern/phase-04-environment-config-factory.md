---
phase: 4
title: "Environment Config & Factory"
status: pending
priority: P1
effort: "2h"
dependencies: [2, 3]
---

# Phase 4: Environment Config & Factory

## Overview

Add Sub2API environment variables to the Zod schema, create a provider factory function, and wire everything together in `index.ts`. This is the final integration phase that makes the provider switch work via env var.

## Requirements

- Functional: `ACTIVE_AI_PROVIDER=gemini` creates `GeminiNativeProvider` (default).
- Functional: `ACTIVE_AI_PROVIDER=sub2api` creates `Sub2ApiProvider`.
- Functional: Sub2API config vars (`SUB2API_BASE_URL`, `SUB2API_API_KEY`, `SUB2API_MODEL`) required only when `sub2api` is active.
- Non-functional: Startup fails fast with clear error if sub2api is selected but config is missing.

## Architecture

```
env.ts (Zod schema)
  └── ACTIVE_AI_PROVIDER: "gemini" | "sub2api" (default: "gemini")
  └── SUB2API_BASE_URL: string (optional, required if sub2api)
  └── SUB2API_API_KEY: string (optional, required if sub2api)
  └── SUB2API_MODEL: string (optional, required if sub2api)
  └── SUB2API_PROMPT: string (optional, custom extraction prompt)

providerFactory.ts
  └── createProvider(env, deps) → PoseExtractorProvider

index.ts
  └── const provider = createProvider(env, { geminiService, keyPoolManager, keyStore })
  └── createApp({ provider, ... })
```

## Related Code Files

- Create: `src/services/providerFactory.ts`
- Modify: `src/config/env.ts` (add new env vars to Zod schema)
- Modify: `src/index.ts` (use factory, pass provider to createApp)
- Modify: `.env.example` (document new variables)

## Implementation Steps

1. **Extend `env.ts` Zod schema:**
   ```typescript
   // Add to envSchema:
   ACTIVE_AI_PROVIDER: z.enum(["gemini", "sub2api"]).default("gemini"),
   SUB2API_BASE_URL: z.string().url().optional(),
   SUB2API_API_KEY: z.string().min(1).optional(),
   SUB2API_MODEL: z.string().min(1).optional(),
   SUB2API_PROMPT: z.string().optional(),
   ```
   Add `.refine()` for conditional validation:
   ```typescript
   .refine((data) => {
     if (data.ACTIVE_AI_PROVIDER === "sub2api") {
       return !!data.SUB2API_BASE_URL && !!data.SUB2API_API_KEY && !!data.SUB2API_MODEL;
     }
     return true;
   }, { message: "SUB2API_BASE_URL, SUB2API_API_KEY, SUB2API_MODEL required when ACTIVE_AI_PROVIDER=sub2api" })
   ```

2. **Create `providerFactory.ts`:**
   ```typescript
   import type { PoseExtractorProvider } from "./poseExtractorProvider";
   import { GeminiNativeProvider } from "./geminiNativeProvider";
   import { Sub2ApiProvider } from "./sub2ApiProvider";
   
   interface ProviderDeps {
     geminiService: GeminiService;
     keyPoolManager: KeyPoolManager;
     keyStore: KeyStore;
   }
   
   export function createProvider(env: AppEnv, deps: ProviderDeps): PoseExtractorProvider {
     switch (env.ACTIVE_AI_PROVIDER) {
       case "sub2api":
         return new Sub2ApiProvider({
           baseUrl: env.SUB2API_BASE_URL!,
           apiKey: env.SUB2API_API_KEY!,
           model: env.SUB2API_MODEL!,
           prompt: env.SUB2API_PROMPT,
         });
       case "gemini":
       default:
         return new GeminiNativeProvider(deps.geminiService, deps.keyPoolManager, deps.keyStore);
     }
   }
   ```

3. **Update `index.ts`:**
   ```typescript
   // Replace:
   //   const geminiService = new GeminiService();
   //   createApp({ geminiService, keyPoolManager, keyStore, ... })
   // With:
   const geminiService = new GeminiService();
   const provider = createProvider(env, { geminiService, keyPoolManager, keyStore });
   logger.info({ provider: env.ACTIVE_AI_PROVIDER }, "AI provider initialized");
   const app = createApp({ provider, ... });
   ```

4. **Update `.env.example`:**
   ```env
   # AI Provider Configuration
   # Options: "gemini" (default) or "sub2api"
   ACTIVE_AI_PROVIDER=gemini
   
   # Sub2API Configuration (required only when ACTIVE_AI_PROVIDER=sub2api)
   # SUB2API_BASE_URL=https://sub2api-gateway-production.up.railway.app/v1
   # SUB2API_API_KEY=sk-your-sub2api-token
   # SUB2API_MODEL=gpt-5.4
   # SUB2API_PROMPT=Extract a clean human pose cutout from this image
   ```

5. **Update Railway env vars for pose-extract-server** (when ready to switch):
   ```bash
   railway variable set \
     ACTIVE_AI_PROVIDER=sub2api \
     SUB2API_BASE_URL=https://sub2api-gateway-production.up.railway.app/v1 \
     SUB2API_API_KEY=<token> \
     SUB2API_MODEL=<model> \
     --service pose-extract-server
   ```

## Success Criteria

- [ ] Zod schema validates Sub2API vars conditionally
- [ ] `createProvider()` factory returns correct provider based on env
- [ ] `index.ts` uses factory — no direct provider construction
- [ ] `.env.example` documents all new variables
- [ ] Server starts with `ACTIVE_AI_PROVIDER=gemini` without Sub2API vars (backward compatible)
- [ ] Server fails fast with clear error if `sub2api` selected but vars missing

## Risk Assessment

- **Risk:** Existing Railway deployment uses current env vars — adding new required vars could break redeploy. **Mitigation:** `ACTIVE_AI_PROVIDER` defaults to `gemini`; Sub2API vars are only validated when provider is `sub2api`. Zero impact on current deployment.
