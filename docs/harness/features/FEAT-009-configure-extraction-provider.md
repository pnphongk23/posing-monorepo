---
schema_version: 1
title: Configure Extraction Provider
relationships:
  specs:
    - "[[product-feature-inventory]]"
    - "[[technical-architecture]]"
    - "[[api-catalogue]]"
  decisions:
    - "[[DEC-001-extraction-provider-selection-policy|DEC-001]]"
  plans:
    - "[[260816-2240-higgsfield-cli-parallel-extract-provider/plan|260816-2240]]"
  reports: []
  rules: []
  features:
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-007-operate-pose-content-from-admin-web|FEAT-007]]"
  source_paths:
    - web/admin-ui/src/app/admin/keys/page.js
    - web/admin-ui/src/lib/poseExtractAdminServer.js
    - web/services/pose-extract-server/src/routes/adminRoutes.ts
type: feature
id: FEAT-009
status: approved
created: 2026-08-16
approved: 2026-08-16
approved_by: Product Authority
---

# FEAT-009: Configure Extraction Provider

## Introduction

**Purpose:** Let an Admin operator select which extraction engine (Gemini native
or Higgsfield CLI) the system uses globally for extract jobs, with a persisted
setting that the pose extract service applies when processing newly claimed jobs
according to the product policy in
[DEC-001](../decisions/DEC-001-extraction-provider-selection-policy.md) (axes
A–D; normative approved policy).

**In scope:** Reading the current global extraction engine, changing it through
the Admin Web operating surface, rejecting invalid engine values, persisting the
choice across service restarts, and declaring that extract jobs are processed by
the active engine per the approved product policy in
[DEC-001](../decisions/DEC-001-extraction-provider-selection-policy.md) (timing,
default, and credential-failure handling are owned by DEC-001).

**Out of scope:** Mobile provider picker; Higgsfield credential upload or CLI
login UI; factory, Docker, CLI spawn, S1/S3 probe implementation design;
redefining the FEAT-004 extract result contract; redefining FEAT-007 as the
owner of general Admin Web operations (FEAT-007 invokes this Feature; it does not
own provider configuration).

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Admin operator | Business role | Choose the global extraction engine | Read and set the active engine through Admin Web |
| Railway operator | External ops role | Keep Higgsfield credentials available on the deployment | Mount or refresh credentials outside Admin Web; no upload UI in this Feature |
| Pose extract service | System | Apply the configured engine to extract jobs | Persist the global setting and use the active engine when claiming extract jobs per DEC-001 |

### User needs

- The Admin operator needs one authoritative, persisted global choice between
  supported extraction engines without exposing secrets to the browser.
- The Admin operator needs clear confirmation when a change is saved or rejected.

### Preconditions

- Admin Web can reach the pose extract service with a valid admin authorization
  configuration.
- At least one supported extraction engine identifier is defined by product policy
  and implementation (currently Gemini native and Higgsfield CLI).
- On fresh deploy with no prior persisted setting, the global extraction engine
  defaults to **`gemini_native`** per DEC-001 axis C (C1).

### Trigger

The Admin operator opens the provider configuration control in Admin Web or
submits a change to the global extraction engine.

### Main flow

1. **Actor:** The Admin operator opens the provider configuration. **System:** The
   pose extract service returns the current global extraction engine.
2. **Actor:** The Admin operator selects a supported engine and saves. **System:**
   The service validates the value, persists the global setting, and confirms the
   saved engine.
3. **System:** When the pose extract service claims a new extract job, it uses
   the active global extraction engine per DEC-001 axis B (B1): the engine in
   effect at claim time applies to that job. In-flight jobs already claimed
   continue on the engine active when they were claimed; a newly saved global
   engine applies only from the next claim onward.

### Alternative flows

- **A1 — Refresh current setting.** Source step: 1. Condition: the operator
  reloads the page or requests current data. Behavior: the system returns the
  persisted global engine without changing it. Resume at step: 1.

### Exception flows

- **E1 — Invalid engine value.** Source step: 2. Failure: the submitted engine
  is not a supported identifier. Handling: reject the change with a structured
  error; retain the last confirmed global engine. Prohibited: persisting or
  reporting success for an invalid value.
- **E2 — Upstream or proxy failure.** Source step: 1 or 2. Failure: Admin Web
  cannot reach the pose extract service. Handling: show proxy or upstream failure;
  retain the last confirmed UI state. Prohibited: exposing admin secrets or
  claiming a saved change without upstream confirmation.
- **E3 — Extract job failure under selected engine.** Source step: 3. Failure:
  the active engine cannot complete a job (for example missing or expired external
  credentials). Handling: per DEC-001 axis D (D2), the Admin operator may select
  Higgsfield CLI even when credentials are missing or expired; affected jobs fail
  with explicit provider errors (for example `PROVIDER_AUTH_REQUIRED`,
  `PROVIDER_CLI_FAILED`). Prohibited: silently switching to another engine
  (normative rejection of D3) or reporting success without operator action.

### Postconditions

- **Success:** The global extraction engine is persisted and returned on subsequent
  reads; newly claimed extract jobs follow DEC-001 policy for engine application.
- **Failure:** The last confirmed global engine remains in effect; no unverified
  success is shown.

### Current evidence

- **Observed:** Admin Keys page and Express admin routes manage API keys only;
  no extraction-provider settings exist today
  (`web/admin-ui/src/app/admin/keys/page.js`,
  `web/services/pose-extract-server/src/routes/adminRoutes.ts`).
- **Observed:** Admin community intake already enqueues async extract jobs
  processed by a worker (`web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts`
  L148–166; `job-processor.ts` hardcodes Playwright today).
- **Observed:** Next.js admin proxy injects Bearer secret server-side
  (`web/admin-ui/src/lib/poseExtractAdminServer.js` L39–60).
- **Planned:** [Plan 260816-2240](../plans/260816-2240-higgsfield-cli-parallel-extract-provider/plan.md)
  and [DEC-001](../decisions/DEC-001-extraction-provider-selection-policy.md)
  define admin toggle API, persistence, and confirmed policy axes B1, C1, D2.

## Requirements

- **FR-001:** The system shall expose the current global extraction engine to an
  authorized Admin operator through Admin Web.
- **FR-002:** The system shall allow an authorized Admin operator to change the
  global extraction engine to a supported identifier (Gemini native or Higgsfield
  CLI).
- **FR-003:** The system shall persist the global extraction engine across pose
  extract service restarts.
- **FR-004:** The system shall reject unsupported or invalid engine identifiers
  without altering the last confirmed global engine.
- **FR-005:** The pose extract service shall process newly claimed extract jobs
  using the active global extraction engine per DEC-001 confirmed product policy:
  next-claimed-job timing (B1), fresh-deploy default `gemini_native` (C1), and
  allow-toggle with explicit job failures, no silent Gemini fallback (D2).
- **BR-001:** Only an Admin operator (via protected Admin Web and upstream admin
  authorization) may change the global extraction engine; mobile clients and
  per-request callers must not select the engine.
- **BR-002:** A failed or unverified provider configuration change must not be
  reported as saved.
- **BR-003:** Changing the global extraction engine must not silently redefine
  the FEAT-004 extract result contract or introduce a second extraction model in
  Admin Web.

## Acceptance

- [ ] An authorized Admin operator can read the current global extraction engine.
- [ ] Saving a supported engine persists and is returned on reload.
- [ ] Submitting an invalid engine identifier is rejected; the prior confirmed
  engine remains active.
- [ ] Admin secrets are not exposed to the browser client.
- [ ] Newly claimed extract jobs use the active global engine per DEC-001 axis A
  (Admin global selection).
- [ ] **B1:** After an Admin changes the global engine, only jobs claimed after
  the save use the new engine; in-flight jobs finish on the engine active at
  claim time.
- [ ] **C1:** On fresh deploy with no prior persisted setting, the global
  extraction engine defaults to `gemini_native`.
- [ ] **D2:** An Admin may toggle to Higgsfield CLI when credentials are missing
  or expired; affected extract jobs fail with explicit provider errors and the
  system does not silently fall back to Gemini.

**Scenario: read and save supported engine**
Given an authorized Admin operator and a supported target engine
When the operator saves the global extraction engine
Then the system confirms the saved engine and returns the same value on reload.

**Scenario: reject invalid engine**
Given an authorized Admin operator
When the operator submits an unsupported engine identifier
Then the change is rejected and the last confirmed engine remains active.

**Scenario: worker uses active engine on new claims (B1)**
Given a persisted global extraction engine and pending extract jobs
When the pose extract service claims a new extract job
Then the job is processed with the active global engine at claim time per DEC-001
B1; in-flight jobs already claimed are not re-routed to a newly saved engine.

## Relationships

- Policy: [DEC-001 Extraction provider selection policy](../decisions/DEC-001-extraction-provider-selection-policy.md)
- Invokes / consumed by: [FEAT-004 Extract Reusable Pose Images](FEAT-004-extract-reusable-pose-images.md) (extract jobs use configured engine; contract unchanged)
- Operating surface: [FEAT-007 Operate Pose Content from Admin Web](FEAT-007-operate-pose-content-from-admin-web.md) (Admin Web invokes this Feature; FEAT-007 does not own provider configuration)
- Plan: [260816-2240 Higgsfield CLI parallel extract provider](../plans/260816-2240-higgsfield-cli-parallel-extract-provider/plan.md)
- Inventory: [[product-feature-inventory]]
- Specs: [[technical-architecture]], [[api-catalogue]]
