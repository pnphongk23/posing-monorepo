---
schema_version: 1
type: decision
id: DEC-005
title: Worker-to-R2 deferred to Phase 5
status: approved
created: 2026-08-23
approved: 2026-08-23
approved_by: Code Vương
relationships:
  specs: []
  decisions: []
  plans: []
  reports: []
  rules: []
  features: []
  source_paths: []
---

# DEC-005 — Worker-to-R2 Deferred to Phase 5

- **Decision:** `WORKER_TO_R2_DEFERRED_PHASE5`
- **Decision maker:** Code Vương
- **Date:** 2026-08-23
- **Scope:** MVP Phase 1/2 Community storage readiness

## Rationale

The MVP covers Phase 1/2 only. Extraction-job result schema and API migration belongs to future Phase 5/6 personal extraction/content-ingestion work.

## Current state

The extraction worker stores generated results as base64 in the database through `ExtractionJobStore.markSucceeded`. This mission does not reinterpret that field, dual-write it, or change the worker, schema, admin routes, or job API.

## Future prerequisite

Phase 5/6 must add a `result_image_url` column, update `markSucceeded`, and update the API response contract before worker output can become an R2 locator.

## Risk

**MEDIUM** — `ExtractionJobStore` has 12 direct callers according to GitNexus impact analysis.
