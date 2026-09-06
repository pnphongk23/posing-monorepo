---
work_item: 1
title: Close FEAT-004, FEAT-009, and FEAT-007 authority for parallel provider and async extract jobs
status: completed
priority: P2
effort: M
dependencies: []
decision_dependencies: []
---

# Work Item 1: Close FEAT-004, FEAT-009, and FEAT-007 authority for parallel provider and async extract jobs

**Kind:** decision/authority gate

## Ownership model (locked)

| Concern | Owner | Notes |
| --- | --- | --- |
| Global extraction engine selection (Admin toggle, persistence, policy axes) | **FEAT-009** | Product policy in [DEC-001](../../decisions/DEC-001-extraction-provider-selection-policy.md) (**approved** 2026-08-17) |
| Dual-engine **processing** + async `ExtractionJob` contract | **FEAT-004** | Uses the engine configured per FEAT-009/DEC-001; does **not** own which-engine selection |
| Admin Web operating surface (keys, community, proxies) | **FEAT-007** | **Invokes** FEAT-009 for engine configuration; must **not** document or own the admin provider toggle |

Implementation intent: [Plan 260816-2240](./plan.md).

## Tasks

- Record locked architecture decisions in [design.md](./design.md) and confirm
  they match Lead's ten locked items (factory, async jobs, FEAT-009 admin toggle
  surface, Docker CLI, S1/S3, provider-neutral errors).
- Update draft **FEAT-004** to document: (a) dual-provider **processing**
  (`gemini_native`, `higgsfield_cli`) behind `PoseExtractorProvider`, (b) phase-1
  async canonical extract via `ExtractionJob` enqueue + poll, (c) processing uses
  the globally configured engine per [FEAT-009](../../features/FEAT-009-configure-extraction-provider.md)
  and [DEC-001](../../decisions/DEC-001-extraction-provider-selection-policy.md)
  (FEAT-004 does not own engine selection), (d) link this Plan in
  `relationships.plans`.
- Confirm **FEAT-009** (approved) linkage to this Plan and DEC-001 in frontmatter
  `relationships`; read-only review unless intro/requirements still carry stale
  pending-approval text.
- Update draft **FEAT-007** to: (a) add FEAT-009 to `relationships.features`,
  (b) state that Admin Web **invokes** FEAT-009 for extraction-engine
  configuration (FEAT-007 does not own provider configuration), (c) link this Plan
  in `relationships.plans`. **Do not** add provider-toggle requirements or
  acceptance criteria to FEAT-007.
- Cross-check **FEAT-005** job-queue flow remains accurate; add Plan link only
  if intake/worker coupling is not already traceable.
- Revise `docs/harness/specs/api-contract.md#extract-pose` draft section for async `202`
  response shape and provider-neutral error codes (`PROVIDER_*`); keep
  `GEMINI_*` documented as deprecated aliases until clients migrate.
- Build requirement-to-implementation parity matrix: FEAT-004 FR/BR, FEAT-009
  FR/BR, FEAT-007 FR/BR (invocation only), extract-pose API module, and
  technical-architecture worker section.
- Confirm no blocking unresolved Decision exists; list any Maintainer choices
  still required before Feature approval (public poll route naming, mobile scope
  exclusion).
- **Do not** run `ckh feature approve` or `ckh plan approve`.

## Scope and affected files

- `docs/harness/features/FEAT-004-extract-reusable-pose-images.md`
- `docs/harness/features/FEAT-009-configure-extraction-provider.md`
- `docs/harness/features/FEAT-007-operate-pose-content-from-admin-web.md`
- `docs/harness/features/FEAT-005-manage-a-pose-guide.md` (linkage only)
- `docs/harness/decisions/DEC-001-extraction-provider-selection-policy.md` (approved; Peer may edit for approval workflow)
- `docs/harness/specs/api-contract.md#extract-pose`
- `docs/harness/plans/260816-2240-higgsfield-cli-parallel-extract-provider/plan.md`
- `docs/harness/plans/260816-2240-higgsfield-cli-parallel-extract-provider/design.md`

## Success criteria

- Locked architecture is encoded in design.md with zero contradictions to plan.md.
- FEAT-004 draft text reflects async dual-provider **processing** intent, defers
  engine selection to FEAT-009/DEC-001, and links this Plan; FEAT-004 and
  FEAT-007 remain `draft` until Maintainer approves separately.
- FEAT-009 (approved) owns provider configuration and links Plan + DEC-001.
- FEAT-007 draft text invokes FEAT-009 without owning provider toggle behavior.
- extract-pose API spec lists provider-neutral error codes and async phase-1
  contract without claiming mobile client is in scope.
- Parity matrix covers every in-scope FR/BR with a Work Item mapping.
- Plan verification ledger Unresolved items are explicitly owned by WI-3/6/7.

## Risks

- Approving Features prematurely would violate Harness authority gate; WI-1 must
  only prepare draft linkage.
- API spec changes without Feature approval may drift; keep edits minimal and
  traceable to locked architecture.
- Mobile sync contract change documented server-side may confuse readers unless
  explicitly marked out-of-scope.
- Re-documenting provider toggle under FEAT-007 would contradict FEAT-009 ownership.

## Required evidence

- Updated FEAT-004/FEAT-009/FEAT-007 markdown with Plan `relationships.plans`
  link and FEAT-009↔FEAT-007 cross-links.
- Parity matrix artifact (section in WI-1 PR or plan.md appendix).
- `ckh validate docs/harness/plans/260816-2240-higgsfield-cli-parallel-extract-provider --all`
- `ckh graph related FEAT-004` / `FEAT-009` / `FEAT-007` output showing Plan
  linkage (when graph fresh).
