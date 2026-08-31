---
title: Saved Poses account-backed v1 design
status: pending
---

# Saved Poses account-backed v1 design

Reuse CommunityPose, PoseDetailScreen, PoseApiService, PoseRepository, existing
pagination and error conventions. Add only Account/session and SavedEntry boundaries.

Google on Supabase is the auth authority. Backend verifies session and maps identity
to Account; mobile stores token/session through existing native boundary once WI-02
confirms exact paths. Do not invent SDK, dependency, config key or service.

Saved API: GET /api/me/saved, PUT /api/me/saved/:poseId, DELETE /api/me/saved/:poseId.
Use unique(accountId, poseId), published filtering, 200 Save, 204 Unsave, and retain
SavedEntry after unpublish/delete. UI says “đã xoá hoặc đã ẩn”. 401 isolates data.

Mobile has confirmed-response state, loading/empty/error/retry/pagination, detail
navigation and sign-in Try Pose gate. Offline is stale read only; no queued mutation.

Albums many-to-many is future only; no Album model, API, UI or migration in v1.
