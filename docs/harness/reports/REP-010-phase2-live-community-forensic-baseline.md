---
schema_version: 1
title: Phase 2 live Community forensic baseline
id: REP-010
status: completed
delivered: 2026-08-24
type: report
relationships:
  specs: []
  decisions: []
  plans: []
  reports: []
  rules: []
  features: []
---

# Phase 2 forensic baseline ledger

- Lane: iOS-only Phase 2 live Community catalogue/search/detail/Try Pose handoff.
- Workspace: `/Users/phamnhuphong/Git/ai-pose` (direct workspace; no worktree).
- Timestamp: 2026-08-24 (local session).
- RTK.md: **MIA** at pre-flight; no file was created.
- Baseline status count: 133 porcelain entries; 108 tracked paths in `git diff --name-only`; 133 total entries including untracked/deleted paths.
- Baseline status capture: `/tmp/ai-pose-status-baseline.txt`.

## Owned paths (only paths this lane may change)
- `mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt` — baseline sha256 `958bf3ab371b8da97c6b74464950d640e77a3957503eaa9d97823914d23a786c`; pre-existing dirty: yes
- `mobile/shared/src/commonMain/kotlin/com/aipose/data/CommunitySearchRepository.kt` — baseline sha256 `beb5ce8a1ecba660658997be8e94dfeb55f62ac4e534a604721abdcaac41db03`; pre-existing dirty: yes
- `mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseServiceLocator.kt` — baseline sha256 `2e7b8ca84494887af1161506b9a8fa04aceb7b38e14997458affa7aa86275e99`; pre-existing dirty: yes
- `mobile/shared/src/iosSimulatorArm64Test/kotlin/com/aipose/data/remote/PoseApiServiceTest.kt` — baseline sha256 `a4fb20e22120362b14e60d06a84cc55221b37bcbce13283c29a76b251d411d98`; pre-existing dirty: yes
- `mobile/shared/src/iosSimulatorArm64Test/kotlin/com/aipose/data/CommunitySearchRepositoryTest.kt` — baseline sha256 `05a02bc805d42270ac48f01891bc29b11917116e3bca9fd19c239ae3b88f5019`; pre-existing dirty: yes

## Separation rule

All other dirty paths/hunks are pre-existing and explicitly not owned. No reset,
checkout, clean, reformat, or overwrite of unrelated hunks is permitted. Existing
owned-path hunks are preserved; edits must target only exact new local regions or
minimal additions around the existing Phase 2 code. This ledger is written before
implementation edits; later diff review compares the owned paths against this
baseline and labels only newly added hunks as this lane's delivery.
