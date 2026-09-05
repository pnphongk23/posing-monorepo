---
title: Saved Poses account-backed v1 design
status: pending
---

# Saved Poses account-backed v1 design

Reuse CommunityPose, PoseDetailScreen, PoseApiService, PoseRepository, existing
pagination and error conventions. Add only Account/session and SavedEntry boundaries.

Supabase Auth uses Google as the only enabled provider for v1; email/password,
magic link, anonymous, Apple, GitHub and every other provider are disabled/out of
scope. Google on Supabase is the auth authority. Backend shall verify session and
map identity to Account once WI-02 confirms exact paths. The live Google/Supabase
path is `Pending-validation`; mobile's secure session boundary is
`BLOCKED/Unresolved` until repository evidence identifies the existing native
boundary. Mobile must use our API exclusively and must not call Supabase directly.
Do not invent SDK, dependency, config key or service.

The Feature proposal table is the source for `proposed — needs Product Authority
approval` constraints: stable identity mapping, secure token lifecycle/sign-out,
minimal OAuth scopes/privacy, provider enforcement, deletion/relink handling,
callback/deep-link ownership, App Store 4.8 review risk, and config/JWT checks.
These are not frozen decisions; runtime Google/Supabase integration remains
`Unresolved` until WI-02 evidence.

Saved API: GET /api/me/saved, PUT /api/me/saved/:poseId, DELETE /api/me/saved/:poseId.
Use unique(accountId, poseId), published filtering, 200 Save, 204 Unsave, and retain
SavedEntry after unpublish/delete. UI says “đã xoá hoặc đã ẩn”. 401 isolates data.

## WI-01 frozen policy rows

| Requirement | Policy record |
| --- | --- |
| FR-001 | Google trên Supabase là provider duy nhất cho auth và Account/session; Supabase chỉ ở server-side boundary, mobile exclusively gọi API của hệ thống; Runtime/Auth remains `Unresolved` until WI-02 evidence. |
| FR-002 | Signed-out Save/Saved/Try Pose yêu cầu sign-in; Guest không được Try Pose; không invent SDK, dependency, env, callback hoặc runtime path. |
| FR-006 | SavedEntry được giữ khi pose unpublish/terminal-delete; list/API lọc published usable pose; stale detail/deep-link/use báo “đã xoá hoặc đã ẩn”, block Try Pose; 401 phải isolate account collection. |
| FR-010 | Albums many-to-many là future boundary; không có Albums/WI-06 model, CRUD, membership UI/API hoặc migration trong v1. |

Thiếu Runtime/Auth evidence từ WI-02 phải escalates `BLOCKED_NEEDS_LEAD` hoặc
`CLARIFICATION_NEEDED`; không claim runtime shipped/verified.

## WI-02 evidence findings

| Evidence area | Current status | Bounded evidence |
| --- | --- | --- |
| Backend auth | Mocked-test evidence only | `web/services/pose-extract-server/src/middleware/adminAuth.ts` and `src/admin.test.ts` cover admin-secret Bearer handling and 401 responses; this is not Google/Supabase Account auth. |
| Live Google/Supabase runtime | Pending-validation | No OAuth broker, Supabase session/JWT verifier, project/config path, or live validation evidence is recorded. |
| Account correlation/persistence | Unresolved | Account entity/API contracts are documented, but no WI-02 runtime Account store/correlation path is evidenced in the current implementation baseline. |
| Mobile secure session boundary | BLOCKED/Unresolved | `PoseApiService.kt` exposes API calls without credential transport; no repository-backed secure session storage, refresh/clear path, or 401 isolation boundary is evidenced. |
| Saved runtime | Unresolved | No `/api/me/saved` routes or mobile Saved API surface is evidenced; WI-03/WI-04 remain out of scope for this remediation. |

These findings are evidence hygiene only. They do not approve an auth flow,
introduce a dependency, or claim runtime behavior.

Mobile has confirmed-response state, loading/empty/error/retry/pagination, detail
navigation and sign-in Try Pose gate. Offline is stale read only; no queued mutation.

Albums many-to-many is future only; no Album model, API, UI or migration in v1.
