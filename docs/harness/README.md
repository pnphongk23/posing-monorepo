# Repository Harness Contract

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
