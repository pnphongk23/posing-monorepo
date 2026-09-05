---
title: Saved Poses account-backed v1 design
status: pending
---

# Saved Poses account-backed v1 design

Reuse CommunityPose, PoseDetailScreen, PoseApiService, PoseRepository, existing
pagination and error conventions. Consume FEAT-014’s Account/session boundary;
add only the SavedEntry integration needed by FEAT-013. Account screen and
sign-out semantics are owned by FEAT-014, not this plan.

Supabase Auth uses Google as the only enabled provider for v1; email/password,
magic link, anonymous, Apple, GitHub and every other provider are disabled/out of
scope. Google on Supabase is the auth authority. Backend shall verify session and
map identity to Account once WI-02 confirms exact paths; mobile stores token/session
through existing native boundary once WI-02 confirms exact paths.
Do not invent SDK, dependency, config key or service.

FEAT-014 is the owner of observable Account/session lifecycle, Account screen,
sign-out, signed-out gating, expiry recovery, and account isolation. The Feature
proposal table is the source for `proposed — needs Product Authority
approval` constraints: stable identity mapping, secure token lifecycle/sign-out,
minimal OAuth scopes/privacy, provider enforcement, deletion/relink handling,
callback/deep-link ownership, App Store 4.8 review risk, and config/JWT checks.
These are not frozen decisions; runtime Google/Supabase integration remains
`Unresolved` until WI-02 evidence.

Saved API: GET /api/me/saved, PUT /api/me/saved/:poseId, DELETE /api/me/saved/:poseId.
Use unique(accountId, poseId), published filtering, 200 Save, 204 Unsave, and retain
SavedEntry after unpublish/delete. UI says “đã xoá hoặc đã ẩn”. 401 isolates data.

Mobile has confirmed-response state, loading/empty/error/retry/pagination, detail
navigation and sign-in Try Pose gate. Offline is stale read only; no queued mutation.

Albums many-to-many is future only; no Album model, API, UI or migration in v1.
