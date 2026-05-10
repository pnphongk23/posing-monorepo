---
phase: 2
title: "Sub2ApiProvider Implementation"
status: pending
priority: P1
effort: "4h"
dependencies: [1]
---

# Phase 2: Sub2ApiProvider Implementation

## Overview

Implement `Sub2ApiProvider` class that calls Sub2API gateway using OpenAI-compatible Vision API format, parses the response to extract image data, and returns `ExtractedImage`.

## Requirements

- Functional: Send image+prompt via OpenAI Vision format, parse image from response.
- Functional: Handle multiple response formats (structured image data, Markdown image URL, raw URL, Base64 Data URI in text).
- Functional: Fetch remote image URLs and convert to Base64 when response contains links.
- Non-functional: Timeout configurable. Error handling maps to existing `AppError` hierarchy.

## Architecture

```
Sub2ApiProvider
  ├── constructor(config: { baseUrl, apiKey, model, prompt?, timeoutMs?, fetchImpl? })
  ├── extractPoseImage(input) → Promise<ExtractedImage>
  │   ├── buildOpenAIVisionRequest(input)
  │   ├── call POST /v1/chat/completions
  │   ├── parseImageFromResponse(responseBody)
  │   │   ├── tryStructuredImageData()   // response.choices[0].message.content[].image_url
  │   │   ├── tryBase64DataUri()         // regex: data:image/(png|jpeg|webp);base64,...
  │   │   ├── tryMarkdownImageUrl()      // regex: ![...](https://...)
  │   │   ├── tryRawImageUrl()           // regex: https://....(png|jpg|jpeg|webp)
  │   │   └── throw ProviderError if none found
  │   └── fetchImageFromUrl(url) → base64 (if URL detected)
  └── private error mapping → ProviderError / ProviderQuotaError
```

## Related Code Files

- Create: `src/services/sub2ApiProvider.ts`
- Create: `src/services/imageResponseParser.ts` (pure function, no side effects — easy to test)
- Reference: `src/services/poseExtractorProvider.ts` (from Phase 1)
- Reference: `src/services/errors.ts` (extend with `ProviderError`, `ProviderQuotaError`)

## Implementation Steps

1. **Add provider-agnostic errors to `errors.ts`:**
   ```typescript
   export class ProviderError extends AppError {
     constructor(message = "AI provider failed", public readonly provider: string) {
       super(message, 500, "PROVIDER_ERROR");
     }
   }
   
   export class ProviderQuotaError extends AppError {
     constructor(message = "AI provider quota exceeded", public readonly provider: string) {
       super(message, 429, "PROVIDER_QUOTA_EXCEEDED");
     }
   }
   ```

2. **Create `imageResponseParser.ts`** — Pure function module:
   ```typescript
   export interface ParsedImage {
     type: "base64" | "url";
     data: string;            // base64 string or URL
     mimeType?: string;       // known if from data URI
   }
   
   export function parseImageFromContent(content: string): ParsedImage | null {
     // Priority order:
     // 1. Base64 Data URI: data:image/png;base64,iVBOR...
     // 2. Markdown image: ![alt](https://example.com/image.png)
     // 3. Raw URL ending with image extension
     // Returns null if no image found
   }
   ```

3. **Create `Sub2ApiProvider`:**
   - Constructor takes `{ baseUrl, apiKey, model, prompt?, timeoutMs?, fetchImpl? }`.
   - `extractPoseImage()` builds OpenAI Vision request:
     ```typescript
     {
       model: this.model,
       messages: [{
         role: "user",
         content: [
           { type: "text", text: this.prompt },
           { type: "image_url", image_url: { url: `data:${input.sourceMimeType};base64,${input.sourceImageBase64}` } }
         ]
       }],
       max_tokens: 4096
     }
     ```
   - Parse response: check `choices[0].message.content` — could be string (text) or array (structured).
   - If string: run `parseImageFromContent()`.
   - If parsed image is URL: `fetch(url)` → Buffer → base64.
   - Map HTTP 429 / quota errors to `ProviderQuotaError`.

4. **Handle edge case: model returns structured image in content array:**
   Some OpenAI-compatible APIs return `content: [{ type: "image_url", image_url: { url: "data:..." } }]`. Check for this before falling back to text parsing.

## Success Criteria

- [ ] `Sub2ApiProvider` implements `PoseExtractorProvider` interface
- [ ] `imageResponseParser.ts` handles: Base64 Data URI, Markdown image URL, raw URL
- [ ] URL-type responses trigger automatic fetch + base64 conversion
- [ ] `ProviderError` and `ProviderQuotaError` added to error hierarchy
- [ ] Provider errors include `provider` field for debugging
- [ ] Constructor injection of `fetchImpl` enables testability without HTTP calls

## Risk Assessment

- **Risk:** Sub2API may return image URL that expires quickly. **Mitigation:** Fetch immediately, no caching of URLs.
- **Risk:** Large base64 strings in text response may be truncated by `max_tokens`. **Mitigation:** Set `max_tokens: 16384` for image-heavy responses; detect truncation by checking if base64 is valid.
- **Risk:** Different models return different formats. **Mitigation:** Parser checks multiple formats in priority order; logs which format matched for debugging.
