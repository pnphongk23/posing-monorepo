---
work_item: 3
title: Verify Firebase fallback, observability, and iOS build
status: completed
priority: P2
effort: TBD
dependencies:
  - 2
decision_dependencies:
  - "[[DEC-006-remote-config-api-baseurl-policy|DEC-006]]"
  - "[[DEC-007-ios-sdk-integration-architecture|DEC-007]]"
---

# Work Item 3: Verify Firebase fallback, observability, and iOS build

## Tasks

- Run the approved KMP tests and existing unsigned iosApp.xcworkspace build.
- Exercise valid fetch, activated cache, offline, timeout, empty, malformed, and
  dead-endpoint recovery; confirm no Firebase/API circular dependency.
- Verify sanitized Analytics/Crashlytics behavior and dSYM target/runbook.
- Audit secrets, Android target absence, dependency churn, and the two conflict
  files; preserve all unrelated dirty worktree changes.

## Scope and affected files

Approved Firebase implementation files, test sources, runbook/evidence, and the
existing workspace only. No new workspace, archive, upload, keychain repair,
commit, push, or application feature work.

## Success criteria

- Required tests/build pass with exact output recorded, or the concrete blocker
  is recorded as: Tôi không thể xác minh điều này hoạt động vì...
- Every fallback/observability failure mode is truthful and recoverable.

## Risks

- Existing dirty worktree can obscure attribution; only approved files may be
  considered in the final audit.

## Required evidence

Exact commands/status, fallback matrix, sanitized event checks, dependency and
secret audit, and final consistency sweep.
