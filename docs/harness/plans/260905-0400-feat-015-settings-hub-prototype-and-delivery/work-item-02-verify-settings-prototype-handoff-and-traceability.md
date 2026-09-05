---
work_item: 2
title: Implement Settings common state, UI, and navigation seam
status: pending
priority: P2
effort: M
dependencies:
  - 1
decision_dependencies:
  - PA-015-01
---

# Work Item 2: Implement Settings common state, UI, and navigation seam

## Kind

`story` / `technical`

## Goal

Implement the common Settings state/controller and Compose surface once Work Item
1 completes the behavior contract freeze (**Work Item 1: `status: completed`**
for authority/route/prototype-boundary evidence only — not formal approval, Cook,
or `READY_FOR_WORK`). Integrate the Voyager push seam from Account (`PA-015-01`,
resolved 2026-09-05) without claiming an existing production route.

## Authority reference

**Canonical record:** [FEAT-015 Feature](../../features/FEAT-015-manage-app-settings-and-preferences.md)
→ Product Authority decision matrix. Primary entry seam for this Work Item:
`PA-015-01`.

## Prototype handoff traceability

The interactive Settings prototype in this lane is the visual reference for IA and
accepted v1 row behavior. Verified behaviors:

| Row / control | Expected prototype behavior |
| --- | --- |
| Back | Returns to Account (`account.html`) |
| Account / Saved / Premium | Navigate to owner prototype surfaces |
| Camera access | Shows `Allowed` (green badge); tap opens simulated iOS Settings dialog |
| Terms of Service | Opens `https://aipose.app/terms` externally |
| Privacy Policy | Opens `https://aipose.app/privacy` externally |
| Support & feedback | Opens `https://forms.gle/sample-aipose-feedback` externally |
| About | Shows Snap Pose `v1.0.0 (Build 42)`; opens About bottom sheet with logo, slogan, © 2026, credits; Close/backdrop/Escape |
| Camera configuration | Absent (Grid, Timer, Flash, Pose Overlay remain Camera-owned) |
| Unavailable placeholders | Absent from prototype copy and badges |

Per-file SHA-256 for the three prototype paths is recorded read-only in the Plan
prototype ledger (reconciled 2026-09-05; `settings.html`
`53b5425ff011d7bf3bd6fd561fb429d53265bdc0939835a73fb9170f63a72aa1`). Candidate
identity: `b59cca2a291c8557469970f955e81c5448c73f4476c94f46d9a55ec5d62430b3`.
Prototype files are not owned edits in this lane.

## Tasks

- Add planned `com.aipose.settings` package when Cook starts; not present today.
- Push `SettingsScreen` from Account per `PA-015-01`; repository evidence shows no
  route in `App.kt`/`Navigation.kt` yet.
- Map prototype rows to `SettingsRowId` and typed owner/platform callbacks
  (`openSupport()`, legal, iOS settings) returning `Opened`/`NotConfigured`/`Failed`.
- Preserve session-generation stale-result rejection and re-entry refresh from the
  planned contract; omit v1 preference store (`PA-015-02`).

## Acceptance and evidence

- Navigation tests prove one push from Account and one Back after implementation.
- Prototype literal checks: zero `Unavailable` matches; required URLs and strings
  present (see Plan checks).
- No raw URL constants in common UI beyond host-injected configuration.
- Compose UI tests remain gated on verified runner; gap recorded honestly.

## Required evidence

State reducer tests, navigation diff evidence, prototype hash ledger (read-only),
accessibility matrix. This lane edits only the five-file Markdown write-set
(Feature, Plan, Work Items 1–3).
