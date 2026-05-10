---
phase: 3
title: "Route Refactor & Provider Wiring"
status: pending
priority: P1
effort: "3h"
dependencies: [1, 2]
---

# Phase 3: Route Refactor & Provider Wiring

## Overview

Refactor `extractPoseRoutes.ts`, `app.ts`, and `createCommunityExtractPoseImage()` to depend on `PoseExtractorProvider` interface instead of hardcoded `GeminiService` + `KeyPoolManager`. Create `GeminiNativeProvider` wrapper to preserve existing behavior. Modify route handler to become provider-agnostic.

## Requirements

- Functional: Routes accept any `PoseExtractorProvider`, not specific service implementations.
- Functional: `GeminiNativeProvider` wraps `GeminiService` + `KeyPoolManager` + `KeyStore` — encapsulates the retry-on-quota-exhaustion loop internally.
- Non-functional: Zero regression — when `GeminiNativeProvider` is used, behavior is byte-identical to current system.

## Architecture

### Before (current):
```
index.ts
  → new GeminiService()
  → new KeyPoolManager(keyStore)
  → createApp({ geminiService, keyPoolManager, keyStore })
    → extractPoseRoutes receives all 3 dependencies
      → route handler contains retry loop with markKeyExhausted()
```

### After:
```
index.ts
  → providerFactory(env) returns PoseExtractorProvider
    ├── "gemini" → new GeminiNativeProvider(geminiService, keyPoolManager, keyStore)
    └── "sub2api" → new Sub2ApiProvider(config)
  → createApp({ provider })
    → extractPoseRoutes receives only provider
      → route handler calls provider.extractPoseImage() — no retry logic here
```

### Key Refactor: Moving retry loop INTO GeminiNativeProvider

Currently in `extractPoseRoutes.ts` (L92-156):
```typescript
while (true) {
  const key = await options.keyPoolManager.getNextActiveKey()...
  try {
    const extracted = await options.geminiService.extractPoseImage({ apiKey: key.apiKey, ... });
    // success: log, respond
  } catch (error) {
    if (error instanceof GeminiQuotaExceededError) {
      await options.keyPoolManager.markKeyExhausted(key.id);
      continue; // retry with next key
    }
    // other errors: throw
  }
}
```

This entire loop moves into `GeminiNativeProvider.extractPoseImage()`. The route becomes:
```typescript
const extracted = await provider.extractPoseImage({ sourceImageBase64, sourceMimeType });
// success: respond with extracted data
```

## Related Code Files

- Create: `src/services/geminiNativeProvider.ts`
- Modify: `src/routes/extractPoseRoutes.ts` (remove retry loop, accept `PoseExtractorProvider`)
- Modify: `src/app.ts` (remove `GeminiServiceLike` interface, accept `PoseExtractorProvider`)
- Modify: `src/app.ts` function `createCommunityExtractPoseImage()` (use provider instead of 3 deps)
- Reference: `src/services/poseExtractorProvider.ts` (interface)

## Implementation Steps

1. **Create `geminiNativeProvider.ts`:**
   ```typescript
   export class GeminiNativeProvider implements PoseExtractorProvider {
     constructor(
       private readonly geminiService: GeminiService,
       private readonly keyPoolManager: KeyPoolManager,
       private readonly keyStore: KeyStore,
     ) {}
   
     async extractPoseImage(input): Promise<ExtractedImage> {
       // Move the retry loop from extractPoseRoutes here
       while (true) {
         const key = await this.keyPoolManager.getNextActiveKey();
         try {
           const result = await this.geminiService.extractPoseImage({
             apiKey: key.apiKey,
             sourceImageBase64: input.sourceImageBase64,
             sourceMimeType: input.sourceMimeType,
           });
           this.keyStore.incrementRequestsToday(key.id);
           this.keyStore.logRequest({ keyId: key.id, ... success: true });
           return result;
         } catch (error) {
           if (error instanceof GeminiQuotaExceededError) {
             await this.keyPoolManager.markKeyExhausted(key.id);
             this.keyStore.logRequest({ keyId: key.id, ... success: false });
             continue;
           }
           this.keyStore.logRequest({ keyId: key.id, ... success: false });
           throw error;
         }
       }
     }
   }
   ```

2. **Simplify `extractPoseRoutes.ts`:**
   - Replace `GeminiServiceLike` + `KeyStore` + `KeyPoolManager` with single `PoseExtractorProvider`.
   - Route handler becomes linear: validate image → call `provider.extractPoseImage()` → respond.
   - Remove the `while(true)` retry loop (now inside provider).
   - Remove `estimateQuotaRemaining()` helper (provider-internal concern).
   - Keep rate limiting middleware unchanged.

3. **Simplify `app.ts`:**
   - Remove duplicate `GeminiServiceLike` interface (L18-24).
   - Replace `geminiService?: GeminiServiceLike` + `keyStore` + `keyPoolManager` with `provider?: PoseExtractorProvider` in `CreateAppOptions`.
   - Simplify `createCommunityExtractPoseImage()` — just delegate to `provider.extractPoseImage()`.
   - Guard: `if (options.provider)` instead of `if (options.keyStore && options.keyPoolManager && options.geminiService)`.

4. **Preserve response metadata:**
   - Current response includes `meta.keyUsed` and `meta.quotaRemaining`.
   - Option A: Drop these fields (they're Gemini-specific).
   - Option B: Extend `ExtractedImage` with optional `meta?: Record<string, unknown>`.
   - **Decision:** Option A for now. These are admin diagnostics, not client-facing. Can add provider-specific metadata later if needed.

## Success Criteria

- [ ] `GeminiNativeProvider` wraps retry loop + key management internally
- [ ] `extractPoseRoutes.ts` depends only on `PoseExtractorProvider` — no direct Gemini/Key imports
- [ ] `app.ts` `CreateAppOptions` uses `provider?: PoseExtractorProvider`
- [ ] `createCommunityExtractPoseImage()` simplified to delegate to provider
- [ ] Duplicate `GeminiServiceLike` interfaces removed from both files
- [ ] With `GeminiNativeProvider` wired in, system behavior is identical to current

## Risk Assessment

- **Risk:** Moving retry loop into provider changes error propagation for `AllKeysExhaustedError`. **Mitigation:** `GeminiNativeProvider` re-throws `AllKeysExhaustedError` as-is — route error handler already catches it (L142-144 in current code).
- **Risk:** `meta.keyUsed` / `meta.quotaRemaining` removal may break existing clients. **Mitigation:** These fields were only used in curl testing, not by any frontend consumer. Verify with grep before removing.
