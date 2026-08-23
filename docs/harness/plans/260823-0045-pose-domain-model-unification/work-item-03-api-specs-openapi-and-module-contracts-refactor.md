---
work_item: 3
title: API specs openapi and module contracts refactor
status: completed
priority: P1
effort: L
dependencies:
  - 2
decision_dependencies: []
---

# Work Item 3: API specs openapi and module contracts refactor

## Tasks

1. Refactor `docs/spec/api/openapi.yaml`:
   - Rename schema `PoseGuide` → `Pose`; `poseId` primary key; `status`
     enum `[local, published]`.
   - `MediaAsset`: `mediaId`, `poseId`, `role` enum `[original, skeleton,
     thumbnail]`.
   - `CommunityPose` described as public DTO/view of a published `Pose`;
     `imagePath` → `skeletonUrl`, `thumbnailPath` → `thumbnailUrl`.
   - Field renames: `sourceAssetId` → `originalMediaId`, `renderAssetId` →
     `skeletonMediaId`, `thumbnailAssetId` → `thumbnailMediaId`, `guideId` →
     `poseId`.
   - `GuideAccepted` → `PoseAccepted` → **`ExtractionJobAccepted`** (`202`: `{ jobId,
     status }` only — no Pose at job start) và **`PoseCreated`** (`201`: `{ pose }`);
     endpoint summaries/descriptions use Pose + `skeleton`; `draft` → `local`.
   - **Creation timing (second pass):** job start = `202` (`POST /api/extract-pose`, retry, re-extract);
     Pose creation/completion = `201` (`POST /api/guides`, admin intake) referencing a `succeeded` `jobId`.
     `Pose` response: camelCase `poseId`, `ownerAccountId`, `originalUrl`,
     `skeletonUrl`, `thumbnailUrl` (three media roles materialized at creation,
     non-nullable). `CommunityPose` published-only (`status` enum `[published]`,
     field `poseId`); admin list returns canonical `Pose`.
2. Refactor `docs/spec/api/` `conventions.md`, `README.md`, and
   `modules/` `community.md`, `extract-pose.md`, `publish.md`, `saved.md`,
   `admin-community.md`, `guides.md` to canonical terminology.
3. Preserve real route paths (e.g. `/api/guides`) and OpenAPI `operationId`
   identifiers; update prose/semantics only. Bump info.version.

## Scope and affected files

- `docs/spec/api/openapi.yaml`
- `docs/spec/api/conventions.md`, `docs/spec/api/README.md`,
  `docs/spec/api/CHANGELOG.md`
- `docs/spec/api/modules/community.md`, `extract-pose.md`, `publish.md`,
  `saved.md`, `admin-community.md`, `guides.md`

## Success criteria

- OpenAPI represents one `Pose` schema with `local` → `published` lifecycle and
  `skeleton` extraction-result naming (`skeleton_media_id`, `skeleton_url`),
  post-extraction creation (`202` job start / `201` Pose creation) and
  non-nullable three media roles.
- No canonical (non-deprecation) `render` / `extracted pose image` / `result
  image` references remain in API specs; route paths and operationIds stay
  valid. OpenAPI version `0.5.0`.

## Risks

- Divergence between documented path names and the real server routes — routes
  are preserved as-is (source changes out of scope).

## Required evidence

- `ckh validate docs/spec/api/README.md` and `ckh validate
  docs/spec/api/openapi.yaml` pass.
- `grep -niE "renderAsset|sourceAssetId|thumbnaileAssetId|enum: \\[draft" 
  docs/spec/api/` returns no canonical occurrences.