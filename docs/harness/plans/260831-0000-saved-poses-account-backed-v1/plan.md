---
title: Saved Poses account-backed v1
description: Implementation plan for Saved Poses account-backed v1.
status: in_progress
approval:
  status: approved
  required_by: Repository Maintainer
  decided: 2026-09-03
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
    - "[[REP-012-feat-012-relaunch-restore-delivery|REP-012]]"
  rules: []
  features:
    - "[[FEAT-013-saved-poses-albums-account-backed|FEAT-013]]"
  source_paths:
    - docs/harness/features/FEAT-013-saved-poses-albums-account-backed.md
    - docs/harness/specs/data-contract.md
    - docs/harness/specs/api-contract.md
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

Plan P2 này chỉ triển khai Account-backed Saved Poses v1. Supabase Auth uses Google as the only enabled provider for v1.
Các provider còn lại (email/password, magic link, anonymous, Apple, GitHub và mọi
provider khác) đều OFF/out of scope. Feature FEAT-013 đã được Product Authority
approve; Plan đã được Repository Maintainer approve và đang `in_progress` cho
execution. Runtime SDK/config/integration vẫn cần WI-02 xác minh.

Albums many-to-many là future/out-of-scope; không có Album work item, CRUD hoặc
membership UI/API. Không mở rộng FEAT-012 hay thay đổi FEAT-008.

## WI-01 frozen policy rows

| Requirement | Policy record |
| --- | --- |
| FR-001 | Google trên Supabase là provider duy nhất cho auth và signed-in Account/session; Supabase chỉ ở server-side boundary, mobile chỉ gọi API của hệ thống; Runtime/Auth vẫn `Unresolved` tới khi WI-02 có evidence. |
| FR-002 | Signed-out Save/Saved/Try Pose phải yêu cầu sign-in; Guest không được Try Pose; không fabricate SDK, dependency, env, callback hoặc runtime path. |
| FR-006 | Unpublish/terminal delete giữ SavedEntry persistence-side; list/API chỉ trả published usable pose; stale detail/deep-link/use báo “đã xoá hoặc đã ẩn”, chặn Try Pose, và 401 phải isolate account collection. |
| FR-010 | Albums many-to-many là future boundary; không có Albums/WI-06 CRUD, membership UI/API/model/migration trong v1. |

Thiếu WI-02 Runtime/Auth evidence phải escalates `BLOCKED_NEEDS_LEAD` hoặc
`CLARIFICATION_NEEDED`; không claim runtime shipped/verified.

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
| Proposed auth constraints (identity, lifecycle, privacy, provider guard, deletion, callback, config/JWT) | WI-01 policy record; WI-02 evidence; Product Authority approval where marked |

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
| Feature scope and frozen decisions | Policy documented | FEAT-013; validation check only |
| Account/SavedEntry/API contracts | Referenced | docs/harness/specs/data-contract.md; docs/spec/api; no edits in this slice |
| Reusable mobile/backend flows | Navigation plus mocked-test evidence | `admin.test.ts` covers admin Bearer 401/200; `PoseApiServiceTest.kt` covers MockEngine HTTP/error mapping; source navigation is not runtime verification |
| Account/Saved runtime implementation | Partially evidenced; live persistence Pending-validation | Backend Account schema/store, Account verifier, and Saved API are implemented with mocked/contract tests and route evidence; live Account persistence and cross-account DB isolation remain Unresolved/Pending-validation |
| Google/Supabase runtime path | Partially verified; full E2E Pending-validation | Active ephemeral tunnel `coated-text-regime-crm.trycloudflare.com` (sustained for mobile dev/TestFlight): health 200, Google start 302 with fixed tunnel callback/state/S256; prior probe facts for Supabase health/JWKS/Railway remain valid; no real credential, callback, token exchange, or verified-token flow completed |
| Mobile secure session boundary | Partially evidenced; platform gaps Pending-validation | Common `SecureTokenStorage`/`SessionBoundary`, iOS Keychain, Bearer attachment, refresh-once/clear behavior, iOS callback handoff, and URL wiring have compile/typecheck/simulator evidence; Android target compile is unavailable and full Xcode app build is blocked by environment contention |
| WI-05 tunnel HTTP evidence | Partially verified; WI-05 remains in_progress | 2026-09-04 sustained dev/tunnel: active ephemeral URL `coated-text-regime-crm.trycloudflare.com`; local/tunnel health 200; Google start 302 with fixed tunnel callback, state, and S256; tsx watch + cloudflared kept alive for mobile E2E; prior 401/unauthenticated observations remain valid; not full token/DB E2E proof |
| Graph artifact | Unresolved | No fresh graph evidence was produced in this remediation; not treated as runtime evidence |
| Evidence-only remediation scope | Partially evidenced | This remediation changes evidence documentation only; the working tree also contains implementation changes from WI-01..WI-04, which are not hidden by this claim |
| Accepted runtime/release blockers | Pending / Required | Live callback/token/Saved/Account DB/isolation, in-process `PendingAuthStore` multi-instance behavior, configured/default key-id release risk, Google-only provider enforcement evidence, production `BACKEND_PUBLIC_URL`, and credential rotation remain unresolved; no remediation is claimed |
| FR-001–FR-010 and direct scenarios | Mixed; see WI-05 matrix | WI-05 records each requirement and signed-in Save, removed published pose, invalid session, and offline mutation as Verified/Failed/Unresolved with mocked/compile/live boundaries; unresolved items remain Pending-validation |
| No Album WI/no FEAT-012 scope leakage | Policy documented | re-read owned policy files and targeted sweep |
