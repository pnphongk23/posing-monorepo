---
work_item: 2
title: Land PoseExtractorProvider factory for Gemini and Higgsfield CLI
status: completed
priority: P2
effort: M
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 2: Land PoseExtractorProvider factory for Gemini and Higgsfield CLI

**Kind:** technical

## Tasks

- Create `src/services/poseExtractorProvider.ts` with `PoseExtractorProvider`
  interface and `ExtractedImage` re-export per [design.md](./design.md).
- Implement `GeminiNativeProvider` wrapping existing `GeminiService` +
  `KeyPoolManager` / `KeyStore` (no `apiKey` on public interface).
- Implement `HiggsfieldCliProvider` skeleton: temp file write, `child_process.spawn`
  for `higgsfield generate create gpt_image_2 --image <path> --wait --json`,
  stdout parse hook, result URL fetch → base64 (full parse in WI-3).
- Add `ProviderSettingsStore` + SQLite `app_settings` migration for
  `extraction_provider` (`gemini_native` | `higgsfield_cli`, default
  `gemini_native`).
- Implement `createPoseExtractorProvider(deps)` factory reading settings.
- Add unit tests: factory selection, `GeminiNativeProvider` with mocked
  `GeminiService`, `HiggsfieldCliProvider` with mocked spawn/fetch.
- Map provider errors to `PROVIDER_*` codes per design error table.

## Scope and affected files

- `web/services/pose-extract-server/src/services/poseExtractorProvider.ts` (new)
- `web/services/pose-extract-server/src/services/geminiNativeProvider.ts` (new)
- `web/services/pose-extract-server/src/services/higgsfieldCliProvider.ts` (new)
- `web/services/pose-extract-server/src/db/providerSettingsStore.ts` (new)
- `web/services/pose-extract-server/src/db/schema.sql`
- `web/services/pose-extract-server/src/services/geminiService.ts` (consume only)
- `web/services/pose-extract-server/src/services/keyPoolManager.ts` (consume only)
- `web/services/pose-extract-server/src/services/types.ts`

## Success criteria

- `PoseExtractorProvider` interface matches design; no `apiKey` parameter.
- Factory returns correct provider for each settings value.
- `GeminiNativeProvider` passes existing `extractPose.test.ts` behavior when wired.
- `HiggsfieldCliProvider` unit tests cover spawn command, timeout, and fetch mock.
- `app_settings` seed defaults to `gemini_native`.
- No route or worker wiring yet (WI-3).

## Risks

- Higgsfield npm package name may differ from `@higgsfield/cli`; verify at install (WI-5).
- Key-pool semantics inside `GeminiNativeProvider` must preserve BR-EXTRACT-001–003.
- Duplicated `GeminiServiceLike` interfaces in routes should be consolidated in WI-3.

## Required evidence

- `npm run backend:test` — new provider unit tests green.
- `npm run backend:build` — TypeScript compile clean.
- Test output showing factory matrix (`gemini_native`, `higgsfield_cli`).
