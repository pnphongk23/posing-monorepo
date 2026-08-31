---
work_item: 1
title: Freeze Google Supabase Account session authority
status: pending
priority: P2
effort: S
dependencies: []
decision_dependencies: []
---

# Work Item 1: Freeze Google Supabase Account session authority

## Tasks

- Record frozen policy: Google via Supabase, Account/session, signed-out Save/Saved/Try Pose gate, Guest cannot Try Pose.
- Record 401 isolation and refresh/clear, removal persistence, published/usable filtering, stale detail/use message, offline read-only/no queue.
- Preserve FEAT-008 as predecessor/boundary; do not create an Album variant or WI-06.

## Scope and affected files

Authority and contract documentation only; affected files are FEAT-013, this Plan, design.md and existing specs.

## Success criteria

FR-001, FR-002, FR-006 and FR-010 have explicit policy rows; Feature proposed and Plan pending.

## Risks

Provider runtime integration may not exist; label it Unresolved, never shipped.

## Required evidence

Exact Feature/spec paths, design.md, ckh validate and ckh workflow check.

