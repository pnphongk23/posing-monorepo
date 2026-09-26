# Repository Harness Contract

## Harness feature documentation map

This directory is one cross-feature documentation set. Start with the [generated
Harness index](./index.md), then use the shared references below; feature pages own
behavior and evidence, while entity, ERD, and API definitions live only in
the [Data contract](./specs/data-contract.md) and [API contract](./specs/api-contract.md).

### Canonical shared references

- [Release Gitflow and Worktree Lifecycle](./specs/release-gitflow.md) — quy trình tách biệt backlog (plan, design) và baseline (cook, test), quy chuẩn tạo nhánh release và merge ngược lại backlog.
- [Data contract](./specs/data-contract.md) — landing cho data + API (single source of truth).
- [Product delivery roadmap](./specs/product-delivery-roadmap.md) — thứ tự ưu tiên nghiệp vụ từ First Pose Capture đến Community operations.
- [Pose Domain Glossary](./specs/pose-domain-glossary.md) — canonical Pose domain model: creation chỉ sau khi extraction `succeeded` (`jobId` → `poseId`), mandatory `ownerAccountId`, ba media role (`original`, `skeleton`, `thumbnail`) non-nullable, lifecycle `local` → `published`, terminology migration map.

- [Data documentation](specs/data-contract.md) — entity semantics, fields, business rules, ERD, enums. Single source of truth cho mô hình dữ liệu product.
  - [Entities](specs/data-contract.md) — Photo, Pose (canonical), MediaAsset, ExtractionJob, Account, SavedEntry, và entity vận hành/conceptual (PoseGuide deprecated alias; CommunityPose là view/DTO)
  - [ERD](specs/data-contract.md) — server, mobile, conceptual overlay
  - [Enums](specs/data-contract.md#enums) — PoseStatus, PoseDifficulty, MediaAssetRole, MediaAssetReadiness, ExtractionJobStatus, ApiKeyStatus
  - [Domain model](specs/data-contract.md#domain-model) — ranh giới layer và Feature ownership
- [API documentation](specs/api-contract.md) — hợp đồng API product. Single source of truth cho API.
  - [OpenAPI 3.1](specs/api/openapi.yaml) — paths, schemas, status codes
  - [Conventions](specs/api-contract.md#conventions) — URL, auth, pagination, errors, proxies
  - [API modules](specs/api-contract.md) — community, guides, publish, saved, extract, admin
- [Model and entity catalogue](./specs/model-entity-catalogue.md) _(stub — redirects to docs/specs/data-contract.md)_
- [Global ERD](./specs/erd.md) _(stub — redirects to specs/data-contract.md)_
- [API catalogue](./specs/api-catalogue.md) _(stub — redirects to docs/specs/api-contract.md)_
- [Product feature inventory](./specs/product-feature-inventory.md) — business boundary and ownership summary.

### Feature inventory and traceability

| Feature | Lifecycle status | Current evidence | Shared model / ERD / API / evidence |
| --- | --- | --- | --- |
| [FEAT-001 Capture a Photo on Mobile](./features/FEAT-001-capture-a-photo-on-mobile.md) | Approved | Partial iOS implementation; Android parity and atomic persistence gaps remain | [Photo](specs/data-contract.md#photo), [ERD mobile](specs/data-contract.md#mobile-local), no feature API; [code/prototype evidence](./features/FEAT-001-capture-a-photo-on-mobile.md#supporting-evidence) |
| [FEAT-002 Manage a Local Photo Gallery](./features/FEAT-002-manage-a-local-photo-gallery.md) | Draft | Local listing/favorite/detail paths observed; export and full file deletion are incomplete | [Photo](./specs/data-contract.md#photo), [Pose](specs/data-contract.md#pose), [ERD mobile](./specs/data-contract.md#mobile-local), no feature API; [code evidence](./features/FEAT-002-manage-a-local-photo-gallery.md#supporting-evidence) |
| [FEAT-003 Browse and Search Published Poses](./features/FEAT-003-browse-and-search-published-poses.md) | Proposed | Public list/detail API and mobile DTO/client observed; title search is mock-backed and publication readiness is unproven | [CommunityPose](specs/data-contract.md#communitypose), [ERD server](specs/data-contract.md#server), [Community API](specs/api-contract.md#community-public), [code/reports](./features/FEAT-003-browse-and-search-published-poses.md#supporting-evidence) |
| [FEAT-004 Extract Reusable Pose Images](./features/FEAT-004-extract-reusable-pose-images.md) | Draft | Direct synchronous extraction and mobile entry point observed; contract, abuse, and retention gaps remain | [ExtractionJob](specs/data-contract.md#extractionjob), [ERD server](./specs/data-contract.md#server), [Extract API](specs/api-contract.md#extract-pose), [code/report evidence](./features/FEAT-004-extract-reusable-pose-images.md#supporting-evidence) |
| [FEAT-005 Manage a Pose Guide](./features/FEAT-005-manage-a-pose-guide.md) | Draft | Server job, community store, worker, and admin key routes observed; guide ownership/versioning and job linkage are unresolved | [Pose](./specs/data-contract.md#pose), [ERD conceptual](specs/data-contract.md#conceptual-overlay), [Admin API](./specs/api-contract.md), [backend report/code evidence](./features/FEAT-005-manage-a-pose-guide.md#supporting-evidence) |
| [FEAT-006 Publish a Pose](./features/FEAT-006-publish-a-pose.md) | Draft | `local`/`published` fields and public filtering exist; owner authorization, unpublish, and ready-skeleton transition are not implemented | [Pose](./specs/data-contract.md#pose), [ERD conceptual](./specs/data-contract.md#conceptual-overlay), [Admin community API](specs/api-contract.md#admin-community), [feature/report evidence](./features/FEAT-006-publish-a-pose.md#supporting-evidence) |
| [FEAT-007 Operate Pose Content from Admin Web](./features/FEAT-007-operate-pose-content-from-admin-web.md) | Draft | Admin UI and server-side proxies are implemented for keys/community intake; truthful job polling and publication operations are missing | [ExtractionJob](./specs/data-contract.md#extractionjob), [ERD server](./specs/data-contract.md#server), [proxies](./specs/api-contract.md#conventions), [admin/code evidence](./features/FEAT-007-operate-pose-content-from-admin-web.md#supporting-evidence) |
| [FEAT-008 Use Published Poses](./features/FEAT-008-use-published-poses.md) | Draft | Typed source-qualified Try Pose preparation is observed; account, Saved, persistence across relaunch, and overlay completion are unresolved | [Pose](./specs/data-contract.md#pose), [ERD conceptual](./specs/data-contract.md#conceptual-overlay), no Save/Try API found; [mobile evidence](./features/FEAT-008-use-published-poses.md#supporting-evidence) |
| [FEAT-009 Configure Extraction Provider](./features/FEAT-009-configure-extraction-provider.md) | Approved | Admin provider configuration policy approved (2026-08-16 Product Authority); DEC-001 approved (2026-08-17); no extraction-provider settings in admin routes or Admin Keys UI observed today | [ExtractionJob](./specs/data-contract.md#extractionjob), [ERD server](./specs/data-contract.md#server), [Admin API](./specs/api-contract.md), [feature evidence](./features/FEAT-009-configure-extraction-provider.md#current-evidence) |
| [FEAT-013 Saved Poses & Albums (Account-backed)](./features/FEAT-013-saved-poses-albums-account-backed.md) | Proposed | Saved/account policy documented; auth runtime and Saved delivery remain unresolved; Albums are future/out of scope | [Account](./specs/data-contract.md#account), [SavedEntry](./specs/data-contract.md#savedentry), [Saved API](./specs/api-contract.md#saved), [feature policy](./features/FEAT-013-saved-poses-albums-account-backed.md) |
| [FEAT-014 Manage Account and Session](./features/FEAT-014-manage-account-and-session.md) | Proposed | Account UI, session lifecycle, sign-out cleanup, and invalid-session recovery are unresolved policy/ownership scope; no runtime shipment claimed | [Account](./specs/data-contract.md#account), [API conventions](./specs/api-contract.md#conventions), [feature policy](./features/FEAT-014-manage-account-and-session.md) |
| [FEAT-015 Manage App Settings and Preferences](./features/FEAT-015-manage-app-settings-and-preferences.md) | Draft | Settings hub boundary documented; production entry point, first non-camera preference set, support destination, and platform parity remain unresolved; Camera settings explicitly excluded | [UI/UX System](./specs/ui-ux-system.md), [linked Feature policy](./features/FEAT-015-manage-app-settings-and-preferences.md), no new API |

Feature pages intentionally link to these shared entries instead of repeating
field definitions or endpoint contracts. Historical plans, reports, templates,
and workflows remain below this landing layer and are not rewritten into current
implementation claims.

The harness is a deterministic, file-first convention for preserving product
and engineering knowledge as readable Markdown. By default, durable artifacts live below
`docs/harness/`, but a repository-root `harness.yaml` file may customize the document root
and collection subfolders. The resolved `index.md` is derived except for its CLI-owned monotonic
artifact sequences.

## Product boundary

The CLI initializes the Harness, scaffolds supported artifacts, safely changes
Feature lifecycle state, validates canonical knowledge, builds and checks the
derived index, optionally reconciles it while explicitly watching, and offers
an explicit built-in offline Markdown retrieval graph. Repository tooling never invokes Claude,
Codex, Cursor, Antigravity, or another AI agent.

The MVP has one CLI writer. Writes stay under repository-contained allowlists,
use flushed temporary sibling files, validate the staged result, recheck input
content, and replace one target at a time. Each file replacement is atomic;
multiple files are not one atomic transaction. A handled publication failure
attempts best-effort rollback without overwriting a divergent external edit.

## Canonical artifacts and ownership

- Features own observable business behavior and immutable `FEAT-XXX` IDs.
- Specs own project-wide technical context and use semantic filenames.
- Decisions own chosen trade-offs and evidence.
- CK plans own approved implementation sequencing, governing relationships,
  Work Item Decision dependencies, and execution state.
- Reports own delivered outcomes and verification evidence.
- Rules own human-approved, reusable guidance.
- Templates and workflows define authoring contracts.
- `index.md` is generated; humans must not hand-edit its catalog or backlinks.

Root `AGENTS.md` and `CLAUDE.md` are routers only. They must not duplicate this
manual or workflow content.

Request classification prevents read-only, no-change, and maintenance work from
creating unnecessary Features. Decision is an interruptible workflow for
durable trade-offs; it is not one mandatory fixed stage in every task.

## Artifact lifecycle CLI

After building, install the CLI locally for all shell sessions from this
repository:

```sh
npm link
```

You can then use `ck-harness` or the shorter `ckh` alias. The existing
`harness` name remains supported for compatibility. Run either binary from the
repository or pass an explicit workspace after the command path:

```text
ckh init [--workspace PATH] [--json]
ckh feature create --title TITLE [--created YYYY-MM-DD]
ckh feature list
ckh feature show TARGET
ckh feature rename TARGET --title TITLE
ckh feature deprecate TARGET
ckh feature delete TARGET [--force]
ckh validate PATH | --kind KIND | --all
ckh index build
ckh index check
ckh index watch [--poll] [--debounce MS] [--rebind-attempts N]
ckh graph build
ckh graph check
ckh graph search QUERY [--limit N]
ckh graph related TARGET [--direction in|out|both] [--depth N]
ckh doctor
ckh new spec --title TITLE
ckh new decision --title TITLE [--created YYYY-MM-DD]
ckh new report --title TITLE --delivered YYYY-MM-DD
ckh new rule --title TITLE --approved YYYY-MM-DD --scope SCOPE
ckh clean [--dry-run]
ckh plan create --title TITLE --work-item TITLE [--work-item TITLE ...] [--created ISO-8601]
ckh workflow status TARGET
ckh workflow check TARGET
ckh feature approve TARGET --approved YYYY-MM-DD --approved-by AUTHORITY
ckh feature request-changes TARGET
ckh plan approve TARGET --decided YYYY-MM-DD
ckh plan request-changes TARGET --decided YYYY-MM-DD
ckh plan set-status TARGET --status STATUS [--reason TEXT]
ckh work-item set-status TARGET --status STATUS [--reason TEXT]
```

`TARGET` depends on the command context:

- For Features: an exact Feature ID or basename (e.g., `FEAT-001` or `FEAT-001-harness-cli`).
- For Plans: a Plan directory path or repository-relative `plan.md` path.
- For Work Items: a repository-relative Work Item markdown file path.

Options belong after the command path. Unknown commands and options fail rather than being reinterpreted. The `--json` flag enables stable JSON consumption, returning a structured JSON success or error envelope.

### Review and Approval Semantics

- Feature `request-changes` sets the Feature status to `proposed` (or keeps it as `proposed` if it already was) and clears approval provenance; it does not produce a terminal rejected state.
- Plan `request-changes` sets Plan approval to `changes_requested`, preserves the
  independent execution status, prevents new execution until reapproval, and does
  not produce a terminal rejected state.
- Agents may record declared human approval provenance but must never grant, infer, or invent human approval authority.

### Recovery Boundary and Manual Fallback

The harness preserves a strict recovery boundary: agents do not automatically
start Cook, mutate Git, access the network, start a watcher or daemon, create a
database, or persist hidden state.

If a command is unsupported or fails, agents must use the named manual fallback path:

1. Manually edit the affected markdown or frontmatter files to repair the state in accordance with the canonical schema contracts.
2. Run `ckh validate` against the changed path or the whole repository to verify that the repair is mechanically valid.
3. Never claim that the failed command itself succeeded.

`index build` publishes one complete deterministic Markdown snapshot. `index
check` is the independent read-only CI gate. `index watch` is an explicit local
convenience that performs full debounced reconciliation and preserves the last
valid index during invalid edits or degraded coverage. `graph build` publishes
one local versioned retrieval artifact under `graph-out/`; `graph check` is the
explicit freshness gate. `graph search` and `graph related` load only that
artifact and never scan Markdown implicitly. The graph is explicit-link and
lexical-only, offline, deterministic, and disposable.

`feature create` and `new decision` create non-approved drafts/proposals.
Reports require an explicit delivery date. Rules require an explicit approval
date and at least one scope so the CLI records existing human authority rather
than silently granting it. Generated starters preserve the canonical document
shape and label unresolved content as TBD for the owning authority.

## Naming and links

ID-bearing files are `FEAT-001-checkout.md`, `DEC-001-payment-provider.md`,
`REP-001-checkout-delivery.md`, and `RULE-001-verify-webhooks.md`. The ID in a
filename and frontmatter must agree. Renaming a slug retains the ID. Valid
feature links prefer `[[FEAT-001-checkout|FEAT-001]]`. Specs use links such as
`[[security]]` and filenames such as `security.md`.

Invalid examples include `FEAT-1-name.md`, `feat-001-name.md`, a reused deleted
ID, `SPEC-001-security.md`, or a feature whose frontmatter says `FEAT-002`
while its filename says `FEAT-001-name.md`.

Plans use the directory form `YYMMDD-HHmm-slug/`, with `plan.md`, optional plain
`design.md`, and `work-item-XX-name.md` children. A present design is linked by
its sibling Plan through `relationships.source_paths`. For example,
`260714-0033-file-based-agent-harness/plan.md` is valid.

## Rename, deletion, and interruption

A referenced feature is deprecated by default, never silently deleted. Forced
deletion must list every affected wikilink and require explicit human
acceptance. Feature IDs remain reserved forever. A supervised slug rename
stages the new Feature and every resolvable inbound-link rewrite, validates the
complete result, then publishes per-file replacements with best-effort handled
rollback.

There is no transaction manifest, automatic crash recovery, or `harness
recover` command. If the process or machine stops between replacements, inspect
the paths named by the failed operation and restore one consistent authored
state from reviewed content or source-control history. A later relevant
mutation rejects detected invalid or duplicate artifact state; it does not
guess which copy is authoritative. After manual repair, rerun the intended
command. Do not introduce a database or hidden trace store as recovery state.

## Cleanup ownership

`harness clean --dry-run` is the required preview. Confirmed cleanup can remove
only the resolved `graph-out/`, historical `graphify-out/`, `.harness-tmp/`, and `.cache/` directories under the
resolved Harness root, and stale temporary sibling or rollback files carrying
the Harness-owned marker. It never removes canonical authored Markdown,
Features, Specs, Decisions, Plans, Reports, Rules, templates, or workflows.

## Troubleshooting

- **Harness is not initialized:** run `harness init` at the intended repository
  root or pass `--workspace` after the command.
- **Repository lock is owned:** wait for the active mutation to finish. Do not
  remove an uncertain live lock merely because it is old.
- **Target changed while staged:** review the external edit and retry from the
  new content; the CLI will not overwrite it.
- **Duplicate or invalid artifact state:** repair the named paths manually,
  preserving immutable IDs, before retrying a mutation.
- **Referenced deletion blocked:** prefer deprecation, or review every listed
  inbound link before explicitly using `--force`.

## Non-goals

There is no SQLite database, legacy database importer, MCP server, dashboard,
hosted service, event or trace ledger, multi-writer transaction guarantee,
agent orchestration, automatic recovery, commit, push, deployment, or external
graph runtime. `validate`, `index check`, and `doctor` are read-only. Watch mode
is not a CI correctness gate, and graph queries never imply freshness without
an explicit `graph check`.
