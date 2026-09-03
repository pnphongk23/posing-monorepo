---
work_item: 7
title: Verify job extract provider switch error mapping and S1 probe
status: completed
priority: P2
effort: M
dependencies:
  - 5
decision_dependencies: []
---

# Work Item 7: Verify job extract provider switch error mapping and S1 probe

**Kind:** verification

## Tasks

- Add/extend automated tests:
  - Job lifecycle: enqueue → worker → `succeeded` / `failed` / requeue.
  - Provider switch: set `higgsfield_cli`, process job; set `gemini_native`,
    process job; assert correct provider invoked (mock).
  - Error mapping: assert HTTP and job `error_code` match design table for
    quota, auth, timeout, CLI failure, invalid image.
- Verify `extract-pose.md` and OpenAPI reflect `PROVIDER_*` codes and async `202`.
- Run S1 probe against staging/production with valid credentials (exit 0) and
  simulate invalid credentials (exit non-zero, alert path documented).
- Run full backend test suite and build.
- Update Plan verification ledger: close Unresolved items or mark Failed with
  owner.
- Run Harness validation commands (below).

## Scope and affected files

- `web/services/pose-extract-server/src/extractPose.test.ts`
- `web/services/pose-extract-server/src/routes/jobStatusRoutes.test.ts` (new or extend)
- `web/services/pose-extract-server/src/worker/job-processor.test.ts` (new)
- `web/services/pose-extract-server/src/services/higgsfieldCliProvider.test.ts`
- `docs/harness/specs/api-contract.md#extract-pose`
- `docs/harness/plans/260816-2240-higgsfield-cli-parallel-extract-provider/plan.md` (ledger update)

## Success criteria

- All new and existing backend tests pass.
- Provider switch test proves worker reads SQLite setting per job claim.
- Error codes `PROVIDER_QUOTA_EXCEEDED`, `PROVIDER_ERROR`, `PROVIDER_AUTH_REQUIRED`,
  `PROVIDER_TIMEOUT`, `PROVIDER_CLI_FAILED` emitted in correct paths.
- S1 probe documented with at least one successful and one failure drill.
- `ckh workflow check` and `ckh validate --all` pass for this Plan directory.
- Plan verification ledger: 0 Failed; Unresolved only for S3 if WI-6 still running.

## Risks

- Integration tests flaky if CLI spawn not fully mocked.
- OpenAPI drift if `openapi.yaml` not updated alongside extract-pose.md.
- S1 failure drill may require coordinated credential revocation.

## Required evidence

- `npm run backend:test` and `npm run backend:build` output (pass).
- Test coverage summary for provider switch and error mapping cases.
- S1 probe drill log (redacted).
- `ckh workflow status docs/harness/plans/260816-2240-higgsfield-cli-parallel-extract-provider`
- `ckh workflow check docs/harness/plans/260816-2240-higgsfield-cli-parallel-extract-provider`
- `ckh validate docs/harness/plans/260816-2240-higgsfield-cli-parallel-extract-provider --all`
