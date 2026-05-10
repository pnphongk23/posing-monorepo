---
phase: 1
title: "Research & Interface Design"
status: pending
priority: P1
effort: "2h"
dependencies: []
---

# Phase 1: Research & Interface Design

## Overview

Define the `PoseExtractorProvider` interface and verify Sub2API response format by calling the live gateway. This phase produces the contract that all subsequent phases build on.

## Requirements

- Functional: Interface must abstract away all provider-specific details (credentials, retry logic, response parsing).
- Non-functional: Interface must be minimal — only what routes actually need.

## Architecture

Current coupling map (what we're breaking apart):

```
extractPoseRoutes.ts
  ├── GeminiServiceLike (interface with apiKey param)
  ├── KeyPoolManager (round-robin key selection)
  └── KeyStore (quota tracking)

app.ts
  ├── GeminiServiceLike (duplicated interface)
  └── createCommunityExtractPoseImage() (hardcoded GeminiService + KeyPool)

job-processor.ts
  └── GeminiBrowserClient (Playwright browser automation)
```

Target contract:

```typescript
// src/services/poseExtractorProvider.ts
export interface PoseExtractorProvider {
  extractPoseImage(input: {
    sourceImageBase64: string;
    sourceMimeType: string;
  }): Promise<ExtractedImage>;
}
```

Key difference from `GeminiServiceLike`: **no `apiKey` param**. Each provider manages its own credentials.

## Related Code Files

- Create: `src/services/poseExtractorProvider.ts` (interface + type exports)
- Analyze: `src/services/geminiService.ts` (current API, L140 `extractPoseImage` signature)
- Analyze: `src/services/types.ts` (existing `ExtractedImage` type — reuse as-is)
- Analyze: `src/routes/extractPoseRoutes.ts` (L9-15 `GeminiServiceLike` — will be replaced)
- Analyze: `src/app.ts` (L18-24 duplicate `GeminiServiceLike` — will be replaced)

## Implementation Steps

1. **Probe Sub2API response format** — `curl` the live gateway with a test image to confirm how image data comes back:
   ```bash
   curl https://sub2api-gateway-production.up.railway.app/v1/chat/completions \
     -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     -d '{"model":"<model>","messages":[{"role":"user","content":[{"type":"text","text":"Extract pose"},{"type":"image_url","image_url":{"url":"data:image/png;base64,..."}}]}]}'
   ```
   Document the response structure (text with URL? base64 data URI? structured image field?).

2. **Create `poseExtractorProvider.ts`** — Define interface + re-export `ExtractedImage` from `types.ts`.

3. **Verify `ExtractedImage` compatibility** — Confirm the type in `types.ts` (L22-25) covers all needed fields:
   ```typescript
   // Already exists and is sufficient:
   export interface ExtractedImage {
     imageBase64: string;
     mimeType: "image/png" | "image/jpeg" | "image/webp";
   }
   ```

4. **Document Sub2API response format** — Record findings in this phase file for Phase 2 to consume.

## Success Criteria

- [ ] `PoseExtractorProvider` interface created in `src/services/poseExtractorProvider.ts`
- [ ] Sub2API response format documented (text, URL, base64, or structured)
- [ ] Existing `ExtractedImage` type confirmed compatible with both providers
- [ ] No existing code modified in this phase (research only)

## Risk Assessment

- **Risk:** Sub2API may not support Vision input format (image_url with base64 data URI). **Mitigation:** Test with actual curl before coding.
- **Risk:** Response format may vary by model. **Mitigation:** Document format per model in phase notes; build parser for multiple formats in Phase 2.
