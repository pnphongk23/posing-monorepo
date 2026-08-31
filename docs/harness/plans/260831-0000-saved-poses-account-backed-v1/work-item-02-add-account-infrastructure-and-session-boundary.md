---
work_item: 2
title: Add Account infrastructure and session boundary
status: pending
priority: P2
effort: M
dependencies: [1]
decision_dependencies: []
---

# Work Item 2: Add Account infrastructure and session boundary

## Tasks

- Implement or verify Supabase Google session verification and Account persistence.
- Add mobile token/session store and refresh/clear lifecycle using existing conventions.
- Ensure protected requests return 401 without cross-account leakage and signed-out actions are gated.
- Do not invent a concrete SDK/dependency without repository evidence.

## Scope and affected files

Auth middleware/verifier, Account persistence, mobile session boundary and tests discovered during execution; excludes Albums, ownership/publish, FEAT-012 and camera changes.

## Success criteria

Valid identity maps to one Account; invalid session cannot read another collection; refresh/clear returns user to sign-in.

## Risks

Provider SDK/config runtime path is currently Unresolved and may require Maintainer evidence.

## Required evidence

Exact paths/symbols, dependency/config paths, valid/expired-token tests, 401 test, backend/mobile commands and ckh validate.

