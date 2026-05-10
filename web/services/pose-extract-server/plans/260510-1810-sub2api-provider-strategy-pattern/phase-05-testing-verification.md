---
phase: 5
title: "Testing & Verification"
status: pending
priority: P1
effort: "3h"
dependencies: [3, 4]
---

# Phase 5: Testing & Verification

## Overview

Write unit tests for new components (`Sub2ApiProvider`, `imageResponseParser`, `GeminiNativeProvider`, `providerFactory`), verify existing tests still pass, and perform live integration test against Sub2API gateway.

## Requirements

- Functional: Unit tests for all new modules with mocked fetch.
- Functional: Existing test suite passes without modification (zero regression).
- Functional: Live integration test proves end-to-end flow works with Sub2API.
- Non-functional: Test coverage for image parser covers all 3 format variants.

## Related Code Files

- Create: `src/services/sub2ApiProvider.test.ts`
- Create: `src/services/imageResponseParser.test.ts`
- Create: `src/services/geminiNativeProvider.test.ts`
- Create: `src/services/providerFactory.test.ts`
- Verify: `src/services/geminiService.test.ts` (must still pass)
- Verify: `src/extractPose.test.ts` (may need updates if route interface changed)
- Verify: `src/admin.test.ts` (must still pass)

## Implementation Steps

1. **`imageResponseParser.test.ts`** — Pure function, easiest to test:
   ```typescript
   describe("parseImageFromContent", () => {
     it("extracts base64 data URI");
     it("extracts markdown image URL");
     it("extracts raw image URL");
     it("returns null when no image found");
     it("prefers data URI over markdown URL when both present");
     it("handles multiline text with image embedded");
   });
   ```

2. **`sub2ApiProvider.test.ts`** — Mock `fetchImpl`:
   ```typescript
   describe("Sub2ApiProvider", () => {
     it("sends OpenAI Vision format request");
     it("parses structured image response");
     it("parses text response with base64 data URI");
     it("parses text response with markdown image URL and fetches it");
     it("throws ProviderError on non-200 response");
     it("throws ProviderQuotaError on 429 response");
     it("throws ProviderError when no image found in response");
   });
   ```

3. **`geminiNativeProvider.test.ts`** — Mock GeminiService + KeyPoolManager:
   ```typescript
   describe("GeminiNativeProvider", () => {
     it("delegates to GeminiService with key from pool");
     it("retries with next key on quota exhaustion");
     it("throws AllKeysExhaustedError when all keys exhausted");
     it("logs requests via KeyStore");
   });
   ```

4. **`providerFactory.test.ts`**:
   ```typescript
   describe("createProvider", () => {
     it("returns GeminiNativeProvider when ACTIVE_AI_PROVIDER=gemini");
     it("returns Sub2ApiProvider when ACTIVE_AI_PROVIDER=sub2api");
   });
   ```

5. **Run existing test suite:**
   ```bash
   cd web/services/pose-extract-server && npx vitest run
   ```
   All existing tests in `geminiService.test.ts`, `extractPose.test.ts`, `admin.test.ts`, `health.test.ts` must pass.

6. **Update `extractPose.test.ts`** if needed:
   The current test may construct `GeminiServiceLike` directly. If the route interface changed (Phase 3), update test to provide `PoseExtractorProvider` instead.

7. **Live integration test** (manual, post-deploy):
   ```bash
   # With ACTIVE_AI_PROVIDER=sub2api configured
   curl -X POST https://pose-extract-server-production.up.railway.app/api/extract-pose \
     -F "image=@test-image.jpg" \
     -H "Content-Type: multipart/form-data"
   ```
   Verify response contains `success: true` with valid `imageBase64` and `mimeType`.

## Success Criteria

- [ ] `imageResponseParser.test.ts` — all format variants covered
- [ ] `sub2ApiProvider.test.ts` — request format, response parsing, error mapping
- [ ] `geminiNativeProvider.test.ts` — retry loop, key rotation, logging
- [ ] `providerFactory.test.ts` — correct provider returned per env
- [ ] `npx vitest run` passes with 0 failures (existing + new tests)
- [ ] Live curl test with Sub2API provider returns extracted image

## Risk Assessment

- **Risk:** `extractPose.test.ts` tightly coupled to old interface (directly mocking `GeminiServiceLike` + `KeyPoolManager`). **Mitigation:** Update test to mock `PoseExtractorProvider` instead — simpler mock since retry logic is now inside provider.
- **Risk:** Live integration test depends on Sub2API gateway uptime and configured channels. **Mitigation:** Ensure Sub2API has active channel with working OpenAI account (configured in prior session).
