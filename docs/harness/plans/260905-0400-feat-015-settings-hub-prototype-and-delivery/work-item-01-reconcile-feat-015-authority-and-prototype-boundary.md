---
work_item: 1
title: Freeze FEAT-015 behavior contracts and owner seams
status: completed
priority: P2
effort: M
dependencies: []
decision_dependencies:
  - PA-015-01
  - PA-015-02
  - PA-015-03
  - PA-015-04
  - PA-015-05
  - PA-015-06
---

# Work Item 1: Freeze FEAT-015 behavior contracts and owner seams

## Kind

`story` / `technical`

## Goal

Turn the Product Authority answers recorded on 2026-09-05 into a small, testable
Settings contract without creating a second Account, Saved, Premium, Camera, auth,
legal, or permission owner.

## Authority reconciliation

**Canonical record:** [FEAT-015 Feature](../../features/FEAT-015-manage-app-settings-and-preferences.md)
→ Product Authority decision matrix (`PA-015-01`…`PA-015-06`, Closed
2026-09-05). This Work Item reconciles owned docs to that record; it does not
duplicate decision rows.

Reconciliation evidence:

- Feature matrix is the sole six-row Product Authority table in the write-set.
- Plan and Work Items cite `PA-015-*` IDs and link to the Feature record without
  restating Status/Authority/Date/Resolved-answer rows.
- No `Unresolved` wording for `PA-015-01`…`PA-015-06` remains in Plan or Work Items.

## Tasks

- Confirm Plan and Work Items reference the Feature canonical record without
  duplicating decision rows.
- Freeze a row/owner matrix aligned to the interactive Settings prototype: Account,
  Saved, Premium handoffs; camera access status; separate Terms and Privacy external
  rows; Support external row; About in-app surface; no Camera configuration rows;
  no v1 preference rows.
- Define the planned `SettingsContract.kt` ports: complete v1 `SettingsRowId`
  enum (Account, Saved, Premium, CameraAccess, TermsOfService, PrivacyPolicy,
  Support, About); `SettingsDestinationResult` (`Opened`/`NotConfigured`/`Failed`);
  `SettingsPlatformActions.openSupport()` plus legal and iOS-settings actions;
  session-generation stale-result rejection and re-entry refresh. Planned only —
  not in repository. No v1 `SettingsPreferenceStore`.
- Confirm `CameraController`/Camera snapshot state remains outside Settings except
  for the approved camera-access status row (`PA-015-06`).

## Acceptance and evidence

- Feature canonical matrix lists all six IDs as Closed with Product Authority and
  date 2026-09-05; Plan and Work Items contain no duplicated decision rows.
- Row matrix matches prototype behavior and resolved scope; no Camera settings rows.
- Contract defers v1 persistence per `PA-015-02`.
- Work Item 1 `status: completed` (see Completion section). Feature remains
  `draft`; Plan and Work Items 2–3 remain `pending`; no formal approval, Cook, or
  `READY_FOR_WORK` is inferred.

## Required evidence

Link to Feature canonical matrix; navigation citations; prototype SHA-256 ledger in
Plan (read-only); deterministic fake cases for destination and session branches. This
Work Item lane edits only the five-file Markdown write-set: Feature FEAT-015,
`plan.md`, and Work Items 1–3.

## Completion (2026-09-05)

Work Item 1 execution is **complete** for this planning lane. Completed scope:

- **Authority reconciliation:** Feature holds the sole six-row Product Authority
  matrix; Plan and Work Items reference it without duplicated decision rows.
- **Route boundary:** Plan documents no production Account/Settings route in
  `App.kt`/`Navigation.kt`; approved target is Voyager push from Account
  (`PA-015-01`).
- **Prototype boundary:** Row/owner matrix and planned `SettingsContract.kt` ports
  frozen; Camera capture config excluded except camera-access status (`PA-015-06`);
  v1 persistence deferred (`PA-015-02`).

**Pending (not WI-01 scope):** prototype-hash ledger reconciliation — **complete**
in Work Item 3 (2026-09-05). Prototype files were not edited.

**Not implied by this completion:** formal Feature approval, Plan approval, Cook,
`READY_FOR_WORK`, or production implementation. Feature remains `draft`; Plan remains
`pending`; Work Item 2 remains `pending`; Work Item 3 hash reconciliation is
complete while WI-3 stays `pending` for future Cook integration.
