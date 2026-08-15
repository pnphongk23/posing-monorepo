---
schema_version: 1
title: Project Documentation and Harness Baseline
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[product-feature-inventory]]"
    - "[[ui-ux-system]]"
  decisions: []
  plans: []
  reports: []
  rules: []
  features:
    - "[[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]"
    - "[[FEAT-002-manage-a-local-photo-gallery|FEAT-002]]"
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
  source_paths:
    - README.md
    - docs/community-poses-api.md
    - docs/design-reference
    - docs/prototype
    - docs/superpowers
    - mobile
    - web
type: report
id: REP-001
status: completed
delivered: 2026-08-09
---

# REP-001: Project Documentation and Harness Baseline

## Delivered outcome

- Initialized CKH 0.1.0 without overwriting pre-existing workspace files.
- Established current-state Technical, Feature, and UI/UX specs backed by active code paths.
- Added five draft Feature contracts that distinguish delivered behavior from partial wiring.
- Replaced create-next-app README boilerplate with a monorepo router.
- Corrected the documented community admin POST from obsolete metadata-only JSON to the implemented multipart/job contract.
- Preserved historical plans/specs, active prototype edits, untracked `sub2api/`, and generated iOS build deletions.

## Changed files

- `README.md` — repository purpose, lanes, commands, docs router, and limitations.
- `docs/community-poses-api.md` — current multipart upload and async job response.
- `docs/harness/specs/*.md` — architecture, feature inventory, and UI/UX source of truth.
- `docs/harness/features/*.md` — five observable product behavior contracts.
- `docs/harness/index.md` and `docs/harness/graph-out/` — CLI-generated retrieval artifacts.
- `docs/harness/templates/`, `docs/harness/workflows/`, `.agents/skills/` — CKH 0.1.0 bootstrap assets.

## Verification evidence

- `ckh validate --all --workspace .` — success, zero findings.
- `ckh doctor --workspace .` — success, zero findings.
- `ckh index check --workspace .` — success and fresh.
- `ckh graph check --workspace .` — success, available and fresh.
- `npm test && npm run build` in `web/services/pose-extract-server` — 14 test files and 78 tests passed; TypeScript build passed.
- `npm run lint && npm run build` in `web/admin-ui` — build passed; lint returned zero errors and four `@next/next/no-img-element` warnings.
- `./gradlew :composeApp:compileKotlinIosSimulatorArm64` — build successful.
- `./gradlew :composeApp:compileKotlinIosSimulatorArm64 :shared:iosSimulatorArm64Test` — failed in shared test compilation because `kotlinx.coroutines.test.runTest` is unresolved in `PoseApiServiceTest.kt`.

## Plan variance

Historical specs and plans were not moved into the Harness. They remain at their existing paths to preserve links and provenance; the new Harness documents summarize current code and link to source paths instead.

## Repeated friction

- Node workspace dependencies were absent initially; `npm ci` from each lockfile was required before checks could run.
- Dependency installation reported 12 vulnerabilities for admin UI (1 low, 11 high) and 9 for the backend (2 low, 1 moderate, 6 high). No automatic audit fix was applied because dependency upgrades are outside this documentation task.
- The shared iOS simulator test source requires the coroutines test dependency before its tests can compile.
