---
title: Saved Poses account-backed v1
description: Implementation plan for Saved Poses account-backed v1.
status: pending
approval:
  status: pending
  required_by: Repository Maintainer
priority: P2
effort: M
branch: backlog
tags: []
blockedBy: []
blocks: []
relationships:
  specs:
    - "[[product-delivery-roadmap|Product Delivery Roadmap]]"
    - "[[product-feature-inventory]]"
    - "[[technical-architecture]]"
    - "[[model-entity-catalogue]]"
    - "[[api-catalogue]]"
    - "[[ui-ux-system]]"
  decisions: []
  plans:
    - "[[260831-0000-saved-poses-account-backed-v1/plan|Saved Poses account-backed v1]]"
  reports:
    - "[[REP-012-backlog-lane-documentation-survey|REP-012]]"
  rules: []
  features:
    - "[[FEAT-013-saved-poses-albums-account-backed|FEAT-013]]"
  source_paths:
    - docs/harness/features/FEAT-013-saved-poses-albums-account-backed.md
    - docs/spec/data/entities/account.md
    - docs/spec/data/entities/saved-entry.md
    - docs/spec/api/modules/saved.md
    - docs/spec/api/conventions.md
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseRepository.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PoseDetailScreen.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PosesScreen.kt
    - web/services/pose-extract-server/src/app.ts
    - web/services/pose-extract-server/src/routes/communityRoutes.ts
    - web/services/pose-extract-server/src/middleware/adminAuth.ts
    - web/services/pose-extract-server/src/db/communityStore.ts
    - web/services/pose-extract-server/src/db/schema.sql
    - docs/harness/plans/260831-0000-saved-poses-account-backed-v1/design.md
created: 2026-08-31T00:00:00+07:00
createdBy: Harness CLI
---

# Saved Poses account-backed v1

## Overview

Plan P2 này chỉ triển khai Account-backed Saved Poses v1. Feature FEAT-013 đang
proposed và approval pending; Plan pending, không tự approve. Google trên Supabase
là product authority đã frozen. Runtime SDK/config/integration cần WI-02 xác minh.

Albums many-to-many là future/out-of-scope; không có Album work item, CRUD hoặc
membership UI/API. Không mở rộng FEAT-012 hay thay đổi FEAT-008.

## Work Items

- [Work Item 1: Freeze Google Supabase Account session authority](./work-item-01-freeze-google-supabase-account-session-authority.md)
- [Work Item 2: Add Account infrastructure and session boundary](./work-item-02-add-account-infrastructure-and-session-boundary.md)
- [Work Item 3: Add SavedEntry data and Saved API](./work-item-03-add-savedentry-data-and-saved-api.md)
- [Work Item 4: Build mobile Saved UX and sign-in gating](./work-item-04-build-mobile-saved-ux-and-sign-in-gating.md)
- [Work Item 5: Verify Saved integration and regression evidence](./work-item-05-verify-saved-integration-and-regression-evidence.md)

## Coverage

| Feature requirement | Work Items |
| --- | --- |
| FR-001–FR-002: Google/Supabase session, signed-out gate, Guest không Try Pose | WI-01, WI-02, WI-04 |
| FR-003–FR-005: Save 200/idempotent, Unsave 204/idempotent, invalid 404 | WI-03, WI-04, WI-05; direct route tests |
| FR-006–FR-007: removal retention/message, 401 isolation | WI-02, WI-03, WI-04, WI-05; removal and 401 tests |
| FR-008–FR-009: list states/pagination, stale read/no queue, detail/Try Pose | WI-04, WI-05; mobile/UI and offline evidence |
| FR-010: Albums future boundary | WI-01, WI-05 |

| Direct scenario/evidence owner | Owner |
| --- | --- |
| Save published returns 200; repeated Save keeps one entry | WI-03 route tests |
| Unsave returns 204 and is idempotent | WI-03 route tests |
| Invalid/missing/non-published returns 404 and creates no entry | WI-03 route tests |
| 401 isolation and refresh/clear session | WI-02 backend/mobile tests; WI-05 integration |
| Unpublish/delete retains SavedEntry; usable list filtering; unavailable message and blocked Try Pose | WI-03 backend tests; WI-04 UI tests; WI-05 manual evidence |
| Loading/empty/error/retry/pagination | WI-04 UI tests and iOS evidence |
| Offline stale read only and no queued mutation | WI-04 tests; WI-05 manual evidence |

## Verification

| Claim | Status | Evidence |
| --- | --- | --- |
| Feature scope and frozen decisions | Verified | FEAT-013; ckh validate |
| Account/SavedEntry/API contracts | Verified | docs/spec/data/entities; docs/spec/api |
| Reusable mobile/backend flows | Verified | PoseApiService, PoseRepository, PoseDetailScreen, PosesScreen, app.ts, communityRoutes.ts, adminAuth.ts; srcwalk |
| Account/Saved runtime implementation | Failed | srcwalk discover found no implementation in mobile/web |
| Google/Supabase runtime path | Unresolved | provider frozen, SDK/config path absent in baseline |
| Graph artifact | Unresolved | ckh graph check reports stale artifact |
| No code/test/config/CI changes | Verified | git diff --name-only fbbc284 is docs-only |
| No Album WI/no FEAT-012 scope leakage | Verified | re-read all six files and targeted sweep |
