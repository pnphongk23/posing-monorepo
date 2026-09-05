---
work_item: 1
title: Freeze Google Supabase Account session authority
status: completed
priority: P2
effort: S
dependencies: []
decision_dependencies: []
---

# Work Item 1: Freeze Google Supabase Account session authority

## Tasks

- Record frozen policy: Supabase Auth with Google as the only enabled provider for v1;
  email/password, magic link, anonymous, Apple, GitHub and all other providers are
  OFF/out of scope; preserve Account/session, signed-out Save/Saved/Try Pose gate,
  and Guest cannot Try Pose.
- Reference the Feature’s `proposed — needs Product Authority approval` table for
  identity mapping, token lifecycle/sign-out, minimal scopes/privacy, provider guard,
  deletion/relink, callback/deep-link, App Store 4.8, config/JWT, and boundary proposals.
- Record 401 isolation and refresh/clear, removal persistence, published/usable filtering, stale detail/use message, offline read-only/no queue.
- Preserve FEAT-008 as predecessor/boundary; do not create an Album variant or WI-06.

## Scope and affected files

Authority and policy documentation only. This slice does not edit
`docs/harness/specs/data-contract.md#account`, `docs/harness/specs/api-contract.md#conventions`,
`docs/harness/specs/api-contract.md#saved`, `openapi.yaml`, or
`docs/harness/specs/technical-architecture.md`.

## Success criteria

FR-001, FR-002, FR-006 and FR-010 have explicit policy rows; Feature proposed and Plan pending.

## Risks

Provider runtime integration may not exist; label it Unresolved, never shipped or verified.

## Required evidence

Owned policy paths only: Feature, Plan, design.md and roadmap Auth rows; ckh
validate and ckh workflow check.
