---
schema_version: 1
title: Pose domain model unification delivery
relationships:
  specs:
    - "[[pose-domain-glossary]]"
    - "[[model-entity-catalogue]]"
    - "[[erd]]"
    - "[[api-catalogue]]"
    - "[[product-feature-inventory]]"
    - "[[technical-architecture]]"
  decisions: []
  plans:
    - "[[260823-0045-pose-domain-model-unification/plan|260823-0045]]"
  reports: []
  rules: []
  features:
    - "[[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]"
    - "[[FEAT-002-manage-a-local-photo-gallery|FEAT-002]]"
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
    - "[[FEAT-006-publish-a-pose|FEAT-006]]"
    - "[[FEAT-007-operate-pose-content-from-admin-web|FEAT-007]]"
    - "[[FEAT-008-use-published-poses|FEAT-008]]"
  source_paths:
    - docs/harness/specs/pose-domain-glossary.md
    - docs/spec/data/entities/pose.md
    - docs/spec/api/openapi.yaml
type: report
id: REP-008
status: completed
delivered: 2026-08-23
---

# REP-008: Pose domain model unification delivery

## Delivered outcome

Unified the Pose product documentation around a single canonical domain model,
enforcing Code Vương's five authoritative decisions:

1. **Creation timing vs stable UUID:** a `Pose` is created **only after
   extraction succeeds** — no persisted `Pose` before extraction success. During
   extraction the work is tracked by the `ExtractionJob` under its `jobId`
   (correlation key). Once extraction succeeds, the `Pose` is created with its
   stable `poseId` (UUID) and `status: local`; the same `poseId` is retained
   when `status` transitions `local` → `published`. HTTP mapping: `202 Accepted`
   for job start, `201 Created` for Pose creation/completion
   (`POST /api/guides`, admin intake reference a succeeded `jobId`).
2. **Mandatory `ownerAccountId`:** required (non-nullable) on every `Pose`,
   including Admin-created poses — pose local (mobile) và pose admin đều được
   tạo cho một account đã xác thực. Authenticated actor vs owner documented in
   API headers: `AccountSession` → owner is the session account; Admin `Bearer`
   → request must carry `ownerAccountId` explicitly.
3. **Exactly three media roles:** `original`, `skeleton`, `thumbnail`
   (`skeleton` is the AI extraction result — render/result-image terms
   deprecated), all non-nullable and materialized immediately upon Pose
   creation; API responses expose camelCase `originalUrl` / `skeletonUrl` /
   `thumbnailUrl`.
4. **Single canonical entity & DTOs:** `Pose` is the single canonical entity;
   `CommunityPose` is strictly a **published-only DTO** (projection of `Pose`
   with `status='published'`, field `poseId`, `status` enum `[published]`),
   used for public catalogue responses; local/admin endpoints return canonical
   `Pose` / `PoseResponse` (admin list returns `Pose[]`, not `CommunityPose`).
5. **Hierarchical glossary:** canonical numbered glossary
   (`1.`, `1.1`, …) at
   `docs/harness/specs/pose-domain-glossary.md` with creation timing (§3.2),
   mandatory owner, three media roles, lifecycle, ID strategy (`jobId` /
   `poseId` / `mediaId`), and terminology migration map.

Also: `draft` is a deprecated alias of `local`; `PoseReferenceKey` deprecated;
core OpenAPI version bumped to `0.5.0`; every canonical (non-deprecation)
`render` / `extracted pose image` / `result image` reference removed; all
broken prose Markdown links in `docs/harness/` and `docs/spec/` repaired
(0 broken links after audit).

## Changed files

- `docs/harness/specs/pose-domain-glossary.md` — **new** canonical glossary
  (rewritten, numbered hierarchy, §3.2 creation timing).
- `docs/spec/data/entities/pose.md` — **new** canonical Pose entity spec
  (post-extraction creation, mandatory `ownerAccountId`, three non-nullable
  media slots, BR-POSE-001/008/009).
- `docs/spec/data/domain-model.md`, `enums.md`, `README.md`, `CHANGELOG.md`.
- `docs/spec/data/entities/`: `media-asset.md` (three media materialized at
  creation, BR-ASSET-005), `extraction-job.md` (`jobId` correlation key,
  `poseId` nullable until Pose created, BR-JOB-006), `account.md` (mandatory
  owner, admin actor vs owner, BR-ACCOUNT-005), `photo.md`, `community-pose.md`
  (`poseId` DTO field, published-only, BR-COMMUNITY-008), `saved-entry.md`,
  `prepared-pose-reference.md`, and deprecated transition files
  `pose-guide.md`, `personal-pose.md`, `pose-reference-key.md`.
- `docs/spec/data/erd/`: `README.md`, `conceptual.md`, `mobile.md`,
  `server.md` — exact‑3 media relationship, mandatory `ownerAccountId`,
  post-extraction Pose entity, `jobId` on `ExtractionJob`.
- `docs/spec/api/openapi.yaml` — version `0.5.0`; `Pose` response with
  `poseId` / `ownerAccountId` / `originalUrl` / `skeletonUrl` / `thumbnailUrl`
  (non-nullable); `PoseCreated` (`201`) replaces `PoseAccepted`;
  `ExtractionJobAccepted` (`202`, job start only); `CommunityPose`
  published-only (`poseId`, `status: [published]`, required `thumbnailUrl`);
  `POST /api/guides` and admin intake = `201` JSON `{jobId, metadata}` (owner
  session / explicit `ownerAccountId` for admin); retry/re-extract = `202`;
  admin list returns `Pose[]`.
- `docs/spec/api/`: `README.md`, `conventions.md` (status-code table `202`
  vs `201`; authenticated-actor vs owner), `CHANGELOG.md`, and modules
  `community.md`, `extract-pose.md`, `publish.md`, `saved.md`,
  `admin-community.md`, `admin-jobs.md`, `guides.md`.
- `docs/spec/README.md` — feature map updated to canonical `Pose`.
- `docs/harness/features/`: FEAT-004 (post-extraction creation postcondition,
  FR-001/acceptance), FEAT-005 (admin/operator flow two-phase `202`→`201`,
  BR-001), FEAT-007 (ownerAccountId, `201` post-succeeded), plus FEAT-001…FEAT-009
  terminology alignment already delivered.
- `docs/harness/specs/`: `model-entity-catalogue.md`, `erd.md`,
  `api-catalogue.md`, `product-feature-inventory.md`, `technical-architecture.md`
  (async job contract + post-extraction creation steps).
- `docs/harness/README.md` — glossary description updated.
- Plan `docs/harness/plans/260823-0045-pose-domain-model-unification/` —
  plan.md Overview/Acceptance + work items 1–3 synced with decisions;
  broken prose links in work-item-01/04 of plan `260816-2240` and feature→plan
  links repaired.

## Round 2 — Quân sư audit (14 findings) resolution

A second audit (Khổng Minh) issued `CHANGES_REQUIRED` with 14 findings. All
are resolved in this delivery round:

1. **ERD mobile missing `ownerAccountId`** — added `text ownerAccountId FK` to the
   mobile `POSE` block (`docs/spec/data/erd/mobile.md`).
2. **Tech-Arch pre-extraction/`202` phrasing** — replaced `creates a local pose
   record, enqueues task, returns 202` with `enqueues extraction job, returns
   202 Accepted; Pose entity created ONLY AFTER extraction succeeds (201)`
   (`technical-architecture.md`).
3. **Tech-Arch `community_poses` as active storage** — `Pose` declared the single
   canonical server entity; `community_poses` noted as legacy/operational naming
   only; public filter rewritten to `Pose.status = 'published'`.
4. **ExtractionJob sync/async contradiction** — contract described as async
   `202` + `jobId`; Pose created `201` only after `succeeded`.
5. **CommunityPose local+published claim** — clarified as read-only published
   DTO (`status='published'`); admin reads canonical `Pose` (BR-COMMUNITY-003).
6. **FEAT-006 CommunityPose mutable** — rewritten: `local → published` is an
   attribute of canonical `Pose`; `CommunityPose` is the published-only DTO.
7. **FEAT-002 `Pose.id`** → `Pose.poseId`.
8. **FEAT-005 mobile post-extraction** — step 5 and Postconditions now state all
   three media roles (`original`, `skeleton`, `thumbnail`) materialized.
9. **ownerAccountId in fields + traceability** — added to canonical fields and
   workflow contract (`technical-architecture.md`, FEAT-005 FR-003).
10. **FEAT-005 acceptance** — `Submission returns `202` accepted queued job
    (`jobId`); Pose created only on `succeeded` (`201`).`
11. **FEAT-007 Entities table** — changed to canonical `Pose` (with `CommunityPose`
    noted as published view/DTO).
12. **Saved collection DTO projection** — `/api/me/saved` documented as returning
    `CommunityPose` DTO (read-only view projection of published saved Poses)
    in `saved.md` and `openapi.yaml`.
13. **OpenAPI error code consistency** — `INVALID_IMAGE` removed from the
    `POST /api/guides` `400` description, matching `guides.md` (`JOB_NOT_SUCCEEDED`
    / `BAD_REQUEST`).
14. **Changelog legacy terms labeled** — `render` / `extracted pose image` /
    `result image` marked as **Legacy/deprecated terms** in both CHANGELOGs.

## Verification evidence

All commands run from repository root on the final documentation state:

```bash
ckh validate --all   # Harness validation passed
ckh index build      # Harness index built
ckh index check      # Harness validation passed
ckh graph build      # Harness graph built (sha256:f688f31eb36de1b0aaed1882ab0bbc7cdf88cf607c53ae34e51e5a63741dd558)
ckh graph check      # Harness graph is current (sha256:f688f31eb36de1b0aaed1882ab0bbc7cdf88cf607c53ae34e51e5a63741dd558)
```

`git diff --check` exits `0` (no whitespace/conflict markers).

Markdown link audit (`python3` over `docs/harness/` + `docs/spec/`, 151
`.md` files): **0 broken prose links** (relative `[]()` links); frontmatter
wikilinks are ckh-validated (`ckh validate --all` passes); template
placeholders and README naming examples are intentional.

## Plan variance

- **Pre-existing blocker (Plan `260816-2240`)**: out-of-scope plan has a
  `blocked` Work Item (WI-06) and no linked delivery report, so `completed`
  would be inconsistent; its status is verified **clean for ckh** as
  `in_progress` (manual recovery from the earlier `completed` correction —
  no fabricated completion). WI-07 is `completed`; WI-06 stays `blocked` with
  an explicit `status_reason`. `ckh validate --all` passes with this state.
- Route paths (`/api/guides`, `/api/community/poses`) and OpenAPI `operationId`
  identifiers were intentionally preserved (they reflect the real server
  routes' naming; source changes are out of scope). The documented HTTP
  contract (two-phase `202`/`201`, `PoseResponse` URLs) is the canonical
  target per the five decisions.
- **Worktree accuracy:** the repository worktree is **not** docs-only — 88
  dirty paths include ~25 pre-existing modified runtime source files outside
  `docs/spec/`/`docs/harness/` (mobile Kotlin/Swift, web JS, `.gitignore`,
  `AGENTS.md`, etc.). This delivery modified documentation files only, inside
  the approved scope.

## Repeated friction

No repeated friction recorded yet.