---
schema_version: 1
type: decision
id: DEC-001
title: Extraction provider selection policy
status: approved
created: 2026-08-16
approved: 2026-08-17
approved_by: Product Authority
relationships:
  specs:
    - "[[product-feature-inventory]]"
    - "[[technical-architecture]]"
  decisions: []
  plans:
    - "[[260816-2240-higgsfield-cli-parallel-extract-provider/plan|260816-2240]]"
  reports: []
  rules: []
  features:
    - "[[FEAT-009-configure-extraction-provider|FEAT-009]]"
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-007-operate-pose-content-from-admin-web|FEAT-007]]"
  source_paths:
    - docs/harness/plans/260816-2240-higgsfield-cli-parallel-extract-provider/design.md
    - docs/harness/plans/260816-2240-higgsfield-cli-parallel-extract-provider/plan.md
    - docs/harness/plans/260816-2240-higgsfield-cli-parallel-extract-provider/work-item-04-add-admin-provider-toggle-only.md
    - web/services/pose-extract-server/src/routes/adminRoutes.ts
    - web/admin-ui/src/app/admin/keys/page.js
---

# DEC-001: Extraction provider selection policy

## Context

Pose extraction will run two parallel engines (Gemini native REST and Higgsfield
CLI) behind one factory, with canonical extract jobs processed asynchronously by
a worker. [FEAT-009](../features/FEAT-009-configure-extraction-provider.md)
defines the observable Admin behavior for choosing the global extraction engine.
[Plan 260816-2240](../plans/260816-2240-higgsfield-cli-parallel-extract-provider/plan.md)
implements factory wiring, worker routing, admin toggle, and operations; locked
implementation mechanics remain in Plan/design and are not restated here.

This Decision records durable **product policy** for who selects the engine, when
a selection change takes effect, the default on fresh deploy, and behavior when
Higgsfield credentials are missing or expired. Axes B, C, and D are **Product
Authority–confirmed selected outcomes** (recorded 2026-08-16). This Decision
is **approved** (2026-08-17 by Product Authority).

## Decision

### Selected — Axis A: Who selects

**Admin-only global provider selection** is the selected outcome.

An authorized Admin operator sets one global extraction engine (Gemini native or
Higgsfield CLI) through Admin Web. The pose extract service persists that choice
and applies it to extract job processing per the confirmed B/C/D policies below.
Mobile clients, per-request callers, and environment-only deploy configuration
without Admin control are rejected alternatives.

### Selected — Axis B: When a change applies

**Next claimed job only (B1)** is the selected outcome.

A new global extraction engine applies starting with the **next claimed extract
job** only. Jobs already in progress complete on the engine active at claim
time. Queued jobs are not re-routed immediately (B4 rejected); in-flight jobs
are not cancelled on switch (B2 rejected).

### Selected — Axis C: Default when unset

**`gemini_native` on fresh deploy (C1)** is the selected outcome.

On fresh deploy, the global extraction engine defaults to **`gemini_native`**
until an operator explicitly selects Higgsfield CLI. Fail-closed until configured
(C3) and Higgsfield-first default (C2) are rejected.

### Selected — Axis D: Missing or expired Higgsfield credentials

**Allow toggle + fail jobs explicitly (D2)** is the selected outcome.

An Admin operator **may** select Higgsfield CLI even when credentials are missing
or expired. Affected extract jobs **fail** with explicit provider error codes
(for example `PROVIDER_AUTH_REQUIRED`, `PROVIDER_CLI_FAILED`). Silent fallback to
Gemini (D3) is **normatively rejected**. Blocking the toggle until credentials
pass a probe (D1/D4) is rejected.

## Alternatives

### Axis A — Who selects

| ID | Alternative | Benefits | Costs / risks | Reversibility |
| --- | --- | --- | --- | --- |
| A1 | **Admin global (selected)** | Single source of truth; matches FEAT-009 and FEAT-007 operating model; no mobile contract change | Operator must use Admin Web | Easy — save prior engine |
| A2 | Env-only at deploy | Simple ops config | No runtime operator control; conflicts with FEAT-009 | Requires redeploy |
| A3 | Per-job / admin intake parameter | Flexible A/B per job | Complex audit; second selection surface | Hard — API surface |
| A4 | Per-request mobile picker | User choice | Violates Product Authority lock; splits engines by client | Rejected |

### Axis B — When a change applies

| ID | Alternative | Benefits | Costs / risks | Reversibility |
| --- | --- | --- | --- | --- |
| B1 | **Next claimed job only (selected)** | Predictable; no cancel/restart; matches design seq B | Operator wait for in-flight jobs to finish on old engine | Instant settings rollback |
| B2 | Cancel in-flight jobs on switch | Faster uniform engine | Lost progress; lock races | Risky |
| B3 | Dual-run both engines per job | Possible quality compare | Double cost; not "parallel providers" intent | Very costly |
| B4 | Re-route queued only immediately | Middle ground | Must define boundary with processing jobs | Moderate |

### Axis C — Default when unset

| ID | Alternative | Benefits | Costs / risks | Reversibility |
| --- | --- | --- | --- | --- |
| C1 | **`gemini_native` seed (selected)** | Preserves current production path | Higgsfield requires explicit opt-in | Safe rollback |
| C2 | `higgsfield_cli` default | Forces new engine | Breaks deploys without credentials | High risk |
| C3 | Fail-closed until configured | Safe against silent wrong engine | Blocks extract until Admin acts | Ops friction |

### Axis D — Missing or expired Higgsfield credentials

| ID | Alternative | Benefits | Costs / risks | Reversibility |
| --- | --- | --- | --- | --- |
| D1 | Block toggle to Higgsfield | Fail-fast at configuration | Requires health probe on PUT | Clear operator signal |
| D2 | **Allow toggle + fail jobs explicitly (selected)** | Matches S1 human re-login; honest job errors | Queue may fail until credentials restored | No silent engine switch |
| D3 | Auto-fallback to Gemini | Higher job success rate | Violates admin-selected engine; hides credential failure | Rejected |
| D4 | GET health + block PUT | Combines observability with D1 | Extra health endpoint | Moderate |

## Consequences

- **FEAT-009** (`status: approved` 2026-08-16 by Product Authority) references
  this Decision for all axes: Admin global selection (A), next-claimed-job timing (B1),
  fresh-deploy default `gemini_native` (C1), and allow-toggle with explicit job
  failures, no silent Gemini fallback (D2). FR-005 and acceptance criteria are
  aligned to these confirmed policies.
- **FEAT-004** extract result contract is unchanged; only the engine processing
  jobs changes under global policy.
- **FEAT-007** continues as Admin operating surface that invokes FEAT-009; it
  does not own provider-selection policy.
- **Plan 260816-2240** implements persistence, admin routes, worker factory wiring,
  and error codes; Cook must not reopen axis A without superseding this Decision.
- Implementation mechanics (factory, Docker, CLI install, S1/S3) remain Plan/design
  scope only.

## Evidence

- **Observed:** No extraction-provider settings in admin routes or Admin Keys UI
  today (`adminRoutes.ts`; `keys/page.js`).
- **Observed:** Async extract jobs and worker exist; worker currently hardcodes
  Playwright browser client (`job-processor.ts`, `worker-main.ts`).
- **Observed:** Product Authority locked parallel providers, admin-only selection,
  no mobile picker, no credential-upload UI (Phase 1 Lead packet).
- **Observed:** Plan/design align with B1, C1, D2 in locked architecture and
  WI-04 (`design.md`; `plan.md` L136; WI-04 L28–29).
- **Observed:** Product Authority confirmed axes B (B1), C (C1), and D (D2) on
  2026-08-16.
- **Inferred:** Auto-fallback Gemini (D3) contradicts admin-selected engine
  accountability and FEAT-009 BR-001; D3 is normatively rejected per axis D.

## Supersession

This decision supersedes no earlier decision.

Note: A separate approved
[DEC-002 under Plan 260809 pose-reference-library convergence](../plans/260809-2240-pose-reference-library-convergence/DEC-002-pose-reference-library-parity-matrix.md)
exists for FEAT-003 parity; this repository-level DEC-001 is a distinct artifact
allocated by Harness CLI for extraction provider policy.
