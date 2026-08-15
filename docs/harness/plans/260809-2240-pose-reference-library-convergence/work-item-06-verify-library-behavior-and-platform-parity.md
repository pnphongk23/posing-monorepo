---
work_item: 6
title: Verify iOS library behavior and deferred boundaries
status: completed
priority: P1
effort: M
dependencies:
  - 5
decision_dependencies: []
---

# Work Item 6: Verify iOS library behavior and deferred boundaries

**Kind:** verification

## Tasks

- Run all new coordinator, transport, repository/storage, Compose, navigation,
  and backend contract suites from a cleanly identified baseline.
- Execute deterministic offline/online transitions for initial load, page 2
  failure/retry, refresh failure/success, detail missing/error, and deletion
  failure while proving visible-content retention.
- Validate the approved prototype parity matrix across named screen states and
  accessibility semantics, not only happy-path screenshots.
- Build/install the iOS app and collect simulator plus real-iPhone evidence for
  gestures, local file deletion, retry banner, and crash-free navigation using
  the existing iPhone Mobile MCP Plan where applicable.
- Record Android and the production community-search server adapter as deferred
  boundaries. Do not add Android target actuals or a server endpoint in this Plan
  and do not count either as exercised acceptance evidence.
- Run Harness validation/workflow checks and publish a Report linking exact
  commands, artifacts, failures, and residual gaps.

## Scope and affected files

- Test source sets/fixtures, approved platform actuals, Mobile MCP evidence, and
  Harness Report/status artifacts. No unrelated cleanup.

## Success criteria

- Every library-owned FEAT-003 acceptance row has reproducible evidence or an
  explicit blocking result; no silent skip counts as pass.
- Real-device, platform, and adapter claims match the devices and implementations
  actually exercised; mock-backed search is labeled non-production.

## Risks

- Simulator evidence cannot prove physical gesture/storage/device behavior.
- Existing dirty/generated files must be separated from test-created artifacts.

## Required evidence

- Command transcript, test reports, screenshots/accessibility snapshots, crash
  delta, file/database proof, explicit Android/server-search deferral, and linked
  Harness Report with successful workflow check.
