# Plan Workflow

## Purpose
Design the smallest deterministic implementation sequence after closing
authority, grounding the work in current documents and code, and writing
Plan-local implementation design when it materially aids execution.

## Use When
Use for every authorized repository implementation. Behavior-changing work may
combine multiple approved Features. Technical-only work may omit a Feature when
it preserves observable behavior and instead defines explicit technical design objectives.

## Inputs
- Every Feature governing the requested behavior, all approved.
- Active Specs, approved Decisions, project Rules, and unfinished related Plans.
- The built-in retrieval graph artifact and `graph check` evidence when
  available under FEAT-009; otherwise direct canonical inspection.
- Direct inspection of current source, dependencies, tests, and preserved user changes.
- Optional implementation design requirements; when needed, one plain
  `design.md` beside `plan.md` and linked through Plan `relationships.source_paths`.

## Hard Gates
- **Authority Closure Gate:** Every governing Feature is approved and no
  blocking Decision remains unresolved. Technical-only work names its technical authority and objectives.
- **Grounding Gate:** The built-in retrieval graph may accelerate
  Harness-document relationship inspection when a valid artifact is available;
  `graph check` is the freshness gate, and direct canonical inspection remains
  authoritative. Direct project and codebase research grounds implementation
  with a relevant architecture and execution-flow model. Derived output is
  never authority.
- **Design Ownership Gate:** When separate implementation design is needed, it
  is written as linked sibling `design.md`; reusable contracts remain in Specs
  or Decisions and no Change Design artifact is created.
- **Overlap Gate:** Scan unfinished related Plans and reconcile dependencies.
- **Decomposition Gate:** Each `work-item-XX` child is one Work Item with optional
  kind, inline Tasks, risks, and exact evidence expectations in its Markdown
  body; its numeric sequence is stored in `work_item` frontmatter.
- **Coverage Gate:** Every in-scope Feature requirement, or every technical
  objective for technical-only work, maps to at least one Work Item.
- **Claim Verification Gate:** Verify every execution-affecting path, symbol,
  interface, dependency, command, test assumption, and compatibility claim
  against current repository evidence. Record each as **Verified**, **Failed**,
  or **Unresolved** and withhold approval while a material failure or gap remains.
- **Human Decision Gate:** Repository Maintainer decides every unresolved
  material scope, architecture, compatibility, risk-acceptance, sequencing, or
  evidence choice. Planning may recommend with rationale but must not infer a selection.
- **Adversarial Review Gate:** Challenge the draft through security and privacy,
  assumption, failure-mode, and scope-complexity lenses. Retain only findings
  supported by repository evidence and reconcile accepted findings throughout the Plan.
- **Whole-Plan Consistency Gate:** After every material revision, re-read
  `plan.md` and every Work Item and resolve stale names, rejected assumptions,
  duplicate contracts, dependency conflicts, and contradictory success criteria.
  Cook remains unavailable until zero unresolved contradictions remain.
- **Mechanical Validation Gate:** Plan and Work Item contracts pass before human review.
- **Human Approval Gate:** Repository Maintainer approves the current Plan
  template, Work Item sequence, risks, coverage, and success criteria before Cook.
- **CLI Automation Gate:** Invoke and consume the corresponding CLI result at every supported boundary before manually reasoning about or mutating mechanical state.
- **Authority Provenance Gate:** Record declared approval provenance but never grant or invent human approval authority.

These conditions are inputs to one Plan approval. They do not create an
Implementation Readiness artifact, a named readiness gate, or a Plan per Task.

## Procedure
1. **Resolve authority:** Link all governing Features, active Specs, approved
   Decisions, and Rules. Reject Plan approval if any governing Feature is not
   approved or a blocking Decision is unresolved.
2. **Ground documents:** Use the built-in retrieval graph only when a valid
   artifact exists and `ckh graph check` confirms freshness. Use
   `ckh graph related` for bounded explicit-link context and direct canonical
   inspection for authority; warn and continue when the artifact is absent,
   stale, or malformed.
3. **Research project and codebase:** Apply the local `scout` behavior to establish
   project purpose, stack, entry points, architecture, primary control or data
   flows, build and test paths, and operational context before tracing affected
   source, interfaces, dependencies, tests, conventions, configuration, active
   Plans, current behavior, and preserved user changes. Record the evidence and
   relevant source paths; a file list alone is insufficient grounding.
4. **Build a verification ledger:** Verify every execution-affecting claim with
   a repository path and line, symbol lookup, dependency manifest, existing test,
   or reproducible command. Mark claims Verified, Failed, or Unresolved. Do not
   silently repair a Failed claim when the correction changes scope, architecture,
   compatibility, risk acceptance, or success evidence; present that choice to
   Repository Maintainer.
5. **Write or review design:** When separate design materially aids execution,
   write plain `design.md` beside `plan.md` and link its exact path from the
   owning Plan. Promote reusable constraints to a Spec or Decision.
6. **Scan Plans:** Identify unfinished overlapping work and record `blockedBy` or `blocks`.
7. **Setup directory:** Invoke and consume
   `ckh plan create --title TITLE --work-item TITLE [--work-item TITLE ...] [--created ISO-8601]`
   to scaffold the `YYMMDD-HHmm-slug` directory with `plan.md`, optional
   `design.md`, and ordered `work-item-XX-*.md` files. Read every generated Plan and Work Item file returned by the command before manually replacing generated content.
8. **Draft Plan root:** Use the current Plan template and write execution
   `status: pending`, approval metadata, relationships, priority, effort, branch,
   tags, dependencies, author metadata, the coverage map, and the verification ledger.
9. **Draft Work Items:** Treat each Work Item file as one ordered Work Item. In its
   Markdown body record optional kind (`story`, `technical`, `migration`, `docs`,
   or `verification`), inline Tasks, scope, affected files, risks, predecessors,
   `decision_dependencies`, exact success criteria, and required evidence. New
   Work Items start `pending`.
10. **Check coverage:** Map every in-scope Feature requirement to one or more Work
   Items. When no Feature governs technical-only work, map every design objective instead.
11. **Interview material decisions:** Apply the local `ask` behavior to every
    unresolved choice that can change scope, architecture, compatibility, risk
    acceptance, sequencing, or evidence. Present two or three grounded options
    with a recommendation when multiple options remain; record only the
    Repository Maintainer's confirmed answer and propagate it to affected files.
12. **Review adversarially:** Apply the local `brainstorm` behavior through
    security and privacy, assumption, failure-mode, and scope-complexity lenses.
    Require a path-and-line citation or reproducible command for each finding,
    deduplicate findings, and ask Repository Maintainer before applying any
    finding that changes a material Plan choice.
13. **Re-read generated artifacts:** Re-read every generated Plan and Work Item
    file after drafting and reconcile it with the command result and intended scope.
14. **Sweep whole-Plan consistency:** Re-read `plan.md`, optional `design.md`,
    and every Work Item after interview or adversarial revisions. Search for old
    names, rejected assumptions, renamed files, symbols, APIs, fields, duplicate
    embedded contracts, dependency conflicts, and superseded decisions. Record
    zero unresolved contradictions before continuing.
15. **Validate mechanically:** Invoke and consume `ckh workflow status TARGET`
    (where `TARGET` is the Plan directory name or repository-relative `plan.md`
    path) to inspect review/execution state and blockers. Then invoke and consume
    `ckh workflow check TARGET` to aggregate mechanical preflight findings for
    the Plan, every Work Item, links, dependencies, lifecycle state, and coverage.
16. **Submit for approval:** Provide the verification totals, failed and
    unresolved claims, consistency result, risks, coverage, and exact evidence
    commands. Repository Maintainer approves or requests changes.
17. **Record outcome:** If the Repository Maintainer approves, invoke and consume
    `ckh plan approve TARGET --decided YYYY-MM-DD`. If the Repository Maintainer
    requests changes, invoke and consume
    `ckh plan request-changes TARGET --decided YYYY-MM-DD`, which sets approval to
    `changes_requested`, preserves the independent execution status, and prevents
    new execution until reapproval.

## Output
An approved current-shape Plan directory with closed authority, linked grounding
and any applicable Plan-local design, ordered Work Items, inline Tasks, complete coverage, and
executable success criteria; or a non-executable Plan awaiting revision.

## Completion Criteria
- Plan and every Work Item parse under the existing Harness schema.
- Every governing Feature is approved; relationships and Decision dependencies resolve.
- Retrieval-graph grounding, when used, and direct project/codebase research
  evidence, including relevant architecture and execution flows, are recorded
  as applicable; canonical Markdown remains the authority.
- Any separate implementation design is the linked sibling of its owning `plan.md`.
- Every required requirement or technical objective has Work Item coverage.
- Every required success criterion has exact evidence expectations.
- Every execution-affecting claim is Verified, Failed, or Unresolved; no
  material Failed or Unresolved claim remains at approval.
- Every unresolved material choice has an explicit Repository Maintainer answer.
- Adversarial findings are evidence-backed and reconciled or explicitly rejected.
- The whole-Plan consistency sweep reports zero unresolved contradictions.
- Approval status, date, and required authority are recorded.
- No application code or tests were modified while planning.

## Prohibited Actions
- Do not write implementation code during Plan.
- Do not use Plan to override approved behavior or technical authority.
- Do not approve a Plan with an unapproved governing Feature or blocking Decision.
- Do not grant, infer, or invent human approval authority (only record declared human approval provenance).
- Do not manually reason about or mutate mechanical state without first invoking and consuming the corresponding CLI command.
- Do not invent a material choice, silently replace a failed claim, or treat a
  recommendation as Repository Maintainer approval.
- Do not present a Plan as ready while execution-affecting claims are Failed or
  Unresolved or the consistency sweep contains a contradiction.
- Do not treat retrieval-graph output as source-code scouting or canonical
  authority; use it only as explainable derived context.
- Do not store Plan-specific design under Specs, a top-level design tree, or another Plan.
- Do not add a Story layer or create a separate Plan for each Task.
- Do not begin Cook before mechanical validation and human approval.
- Do not classify waiting for initial approval as execution blocked.
- Do not create a second Plan when an unfinished overlapping Plan can be safely revised.

## Failure and Recovery
- **Existing contract already satisfied:** End with evidence and create no Plan.
- **Authority not closed:** Identify every unapproved governing Feature or
  blocking Decision and return to its Document workflow.
- **Technical-only authority unclear:** Clarify the design objectives or create
  the necessary Spec or Decision; do not invent a Feature solely to fill a field.
- **Grounding or design insufficient:** Record the missing evidence, scout or
  revise `design.md`, and resubmit the same Plan.
- **Claim verification failure:** Cite the failing path, symbol, contract, or
  command; revise facts that do not change a material choice and ask Repository
  Maintainer before any correction that does.
- **Unresolved decision:** Keep approval pending, present grounded options and
  trade-offs, and resume only after the responsible human answers.
- **Consistency failure:** Reconcile every affected Plan and Work Item location,
  repeat the whole-Plan sweep, and do not recommend Cook until contradictions are zero.
- **Coverage incomplete:** Revise scope, design, or Work Items until every
  requirement or technical objective is covered.
- **Conflicting Plans:** Pause, reconcile dependency and scope with the human, then revalidate.
- **Validation failure:** Correct the Plan contract and rerun checks before approval.
- **Changes requested:** Revise and resubmit. If Repository Maintainer requests
  changes, invoke `ckh plan request-changes TARGET --decided YYYY-MM-DD`. This
  sets Plan approval to `changes_requested`, preserves the independent execution
  status, prevents new execution until reapproval, and does not produce a terminal rejected state.
- **CLI failure and manual fallback:** If a CLI command is unsupported or fails, apply the named manual recovery path: manually edit the affected markdown or frontmatter files to repair the state, run `ckh validate` to verify mechanical validity, and never claim the failed command succeeded.
- **Recovery boundary:** Preserve the strict recovery boundary: do not automatically
  start Cook, mutate Git, access the network, start a watcher or daemon, or create
  hidden state.
- **Material change after approval:** Preserve completed evidence, reset approval,
  and prevent new Work Items until reapproval.
- **Handoff:** Cook may start only the next eligible Work Item of an approved Plan.
