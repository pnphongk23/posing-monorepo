---
work_item: 5
title: Verify cross-account sync, backend enforcement, and rollout
status: pending
priority: P1
effort: M
dependencies:
  - 4
decision_dependencies: []
---

# Work Item 5: Verify cross-account sync, backend enforcement, and rollout

## Tasks

- Re-read FEAT-011, the companion UI plan, this plan, and all five WIs. Sweep for contradictions about one `premium`, `default`, Account identity, login/logout ordering, webhook authority, backend enforcement phase, public route access, and out-of-scope architecture.
- Run the repository's structural and consistency checks: feature/plan validation, workflow status/check, index/graph checks, and `git diff --check`. Capture actual output rather than marking a check from static inspection.
- When implementation exists, run `npm --prefix web/services/pose-extract-server test`, lint, build, database migration/replay tests, authenticated endpoint tests, and the repository's relevant KMP/mobile tests. Run an iOS compile/typecheck only with the RevenueCat module available.
- Execute or document a Sandbox matrix: Account A login/purchase/restore/re-entry, A logout, Account B login, duplicate/invalid/out-of-order provider events, A/B entitlement reads, the explicitly designated premium route, and fail-closed cases.
- Audit logs/configuration/tests for provider secrets, receipts, access tokens, raw webhook bodies, client account selectors, and stale callbacks. Verify existing public routes remain unchanged while paid-route scope is unresolved.
- Preserve unrelated worktree changes, including the existing `.tmp/` path, and report every external/native/auth blocker with the exact command or evidence that demonstrates it.

## Scope and affected files

This is a verification and rollout work item. It may update plan/feature evidence and verification notes; it must not broaden product scope or silently modify unrelated application code. Evidence should cover:

- FEAT-011 and `docs/harness/plans/260905-1135-feat-011-revenuecat-account-sync-and-entitlement-enforcement/`
- Companion plan `docs/harness/plans/260826-0003-integrate-revenuecat-paid-access-and-iap-for-feat-011/`
- Mobile RevenueCat adapter/bridge and the real auth/session seam
- Backend schema, webhook, auth, entitlement endpoint, and enforcement tests
- API conventions/OpenAPI and repository harness/index/graph outputs

## Success criteria

- The evidence ledger distinguishes `Verified`, `Failed`, and `Unresolved` claims and includes the account-isolation matrix and provider idempotency result.
- Documentation validation, workflow checks, index/graph checks, and `git diff --check` pass, or each failure is recorded with its exact cause and owner/blocker.
- The end-to-end matrix demonstrates that Account A cannot receive B's customer or entitlement and that logout/account switch cannot leak the old identity.
- Backend enforcement is verified only for an explicitly designated premium route; missing/invalid/stale/unavailable state fails closed, and current public routes are not reclassified by assumption.
- External RevenueCat/App Store/Sandbox and native module limitations are reported honestly; no unavailable runtime is presented as verified.
- The plan remains pending until required implementation evidence and repository-maintainer approval exist. The Lead does not issue formal approval.

## Risks

- Sandbox configuration, webhook delivery, auth runtime, and native dependency availability may prevent full end-to-end verification.
- Existing unrelated worktree state can be mistaken for task output if the final diff is not reviewed carefully.
- A green client purchase test does not prove server Account isolation; backend replay and cross-account tests are mandatory.

## Required evidence

- Command outputs for harness validation/workflow/index/graph and backend/mobile checks actually run.
- A/B lifecycle and entitlement matrix, duplicate/invalid/out-of-order webhook results, and fail-closed enforcement results.
- OpenAPI/conventions consistency review and a no-forbidden-architecture audit.
- Final `git status --short --branch` and `git diff --stat`/`git diff --check` showing only intended documentation changes plus the pre-existing unrelated `.tmp/` state.
