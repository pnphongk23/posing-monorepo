---
title: "sub2api-provider-strategy-pattern"
description: "Refactor pose extraction to Strategy Pattern with pluggable providers (Gemini Native + Sub2API), replacing hardcoded GeminiService and Browser Worker with a unified PoseExtractorProvider interface"
status: pending
priority: P1
branch: "develop"
tags: [provider, strategy-pattern, sub2api, refactor]
blockedBy: []
blocks: []
created: "2026-05-10T11:10:14.381Z"
createdBy: "ck:plan"
source: skill
---

# Sub2API Provider — Strategy Pattern

## Overview

Refactor the pose-extract-server from hardcoded `GeminiService` + `GeminiBrowserClient` into a **Strategy Pattern** with a unified `PoseExtractorProvider` interface. Two concrete providers:

1. **`GeminiNativeProvider`** — Wraps existing `GeminiService` + `KeyPoolManager` (zero regression).
2. **`Sub2ApiProvider`** — Calls Sub2API gateway (`https://sub2api-gateway-production.up.railway.app/v1`) using OpenAI-compatible Vision API. Parses image from structured response or text content (URL/Base64).

Provider selection via `ACTIVE_AI_PROVIDER` env var. When `sub2api` is active, Browser Worker pipeline becomes unnecessary — direct API call replaces Playwright automation.

## Key Design Decisions

- **Interface removes `apiKey` param** — Each provider manages credentials internally. `GeminiNativeProvider` uses `KeyPoolManager`; `Sub2ApiProvider` uses a single token from env.
- **Routes receive provider, not service** — `extractPoseRoutes.ts` and `app.ts` depend on `PoseExtractorProvider` interface, not concrete classes.
- **KeyPoolManager stays inside GeminiNativeProvider** — The retry-on-quota-exhaustion loop moves from route-level into the provider. Routes become provider-agnostic.
- **Sub2ApiProvider has a Universal Image Parser** — Handles multiple response formats: OpenAI structured `message.content` with image data, Markdown image links, raw URLs, or Base64 Data URIs embedded in text.

## Scope

- **In scope:** Interface definition, both providers, route refactor, env config, factory wiring, unit tests for Sub2ApiProvider.
- **Out of scope:** Removing Browser Worker code (keep for potential fallback), Admin UI changes, multi-provider simultaneous usage, Sub2API gateway configuration.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Research & Interface Design](./phase-01-research-interface-design.md) | Pending |
| 2 | [Sub2ApiProvider Implementation](./phase-02-sub2apiprovider-implementation.md) | Pending |
| 3 | [Route Refactor & Provider Wiring](./phase-03-route-refactor-provider-wiring.md) | Pending |
| 4 | [Environment Config & Factory](./phase-04-environment-config-factory.md) | Pending |
| 5 | [Testing & Verification](./phase-05-testing-verification.md) | Pending |

## Dependencies

- Sub2API gateway deployed at `https://sub2api-gateway-production.up.railway.app` (completed in prior session).
- Prior plan `260505-1121-provider-approach-2-railway-docker` is `completed` — no blocking relationship.

## Success Definition

- `ACTIVE_AI_PROVIDER=gemini` → System works exactly as before (zero regression).
- `ACTIVE_AI_PROVIDER=sub2api` → `POST /api/extract-pose` calls Sub2API, returns extracted image.
- Provider switch requires only env var change + restart — no code changes.
- All existing tests pass. New tests cover Sub2ApiProvider response parsing.
