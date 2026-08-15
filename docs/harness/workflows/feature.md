# Feature Workflow

## Purpose
Discover, clarify, and document new or changed observable behavior from a
Business Analyst perspective without deciding implementation design. Feature is
an authority document with its own lifecycle, not a mandatory stage of every
Coding workflow.

## Use When
Use for a new capability, a material behavior change, an ambiguous business
boundary, or undocumented existing behavior. Do not create a new Feature for a
read-only request, a no-change result, or maintenance already governed by an
approved Feature or active Spec.

## Inputs
- User request or issue description.
- Existing Features, Specs, Decisions, Rules, and relevant source evidence.
- Request classification from the workflow router.

## Hard Gates
- **Scout-First Gate:** Apply the local `scout` behavior to research the project
  baseline, architecture, relevant code flows, dependencies, tests, conventions,
  operations, active work, and repository evidence before asking material
  clarifying questions, proposing behavior variants, or authoring.
- **Evidence Labeling Gate:** Classify material findings as **Observed**,
  **Inferred**, **Failed**, or **Unresolved (TBD)**. Never convert a missing or
  failed check into a fact.
- **Exact Requirements Gate:** Make the expected output, acceptance criteria,
  explicit exclusions, non-negotiable constraints, and affected touchpoints
  concrete and testable before requesting approval.
- **Human Decision Gate:** When evidence and approved authority leave a material
  product or scope choice open, apply the local `ask` and `brainstorm` behaviors,
  present two or three viable behavior variants when available, and require
  Product Authority to select or revise them. Do not infer a selection.
- **Business Boundary Gate:** Product Authority must approve purpose, scope,
  observable behavior, requirements, and acceptance before that behavior may
  govern a Coding Plan.
- **CLI Automation Gate:** Invoke and consume the corresponding CLI result at every supported boundary before manually reasoning about or mutating mechanical state.
- **Authority Provenance Gate:** Record declared approval provenance but never grant or invent human approval authority.

## Procedure
1. **Confirm route:** Verify that behavior is new, changing, ambiguous, or
   undocumented. If an approved contract already governs maintenance, link it
   and end Feature work without creating a duplicate artifact.
2. **Scaffold the draft:** Invoke
   `ckh feature create --title TITLE [--created YYYY-MM-DD]`, consume the returned
   path, and read the generated draft before
   manually editing it. If creation fails, use only the named manual fallback in
   **Failure and Recovery**.
3. **Research project and codebase first:** Apply the local `scout` behavior to
   establish project purpose, stack, entry points, architecture, and relevant
   execution flows, then trace code, docs, Features, Specs, Decisions, Rules,
   Reports, dependencies, tests, conventions, configuration, operations,
   preserved user changes, and unfinished Plans as relevant. Verify important
   paths, symbols, relationships, and current patterns before asking questions.
4. **Summarize evidence:** Report a concise project and codebase mental model and
   separate observed facts, supported inferences, failed checks, and unresolved
   questions. Include the path, command, or approved authority supporting each
   material finding.
5. **Clarify exact requirements:** Apply the local `ask` behavior to make the
   expected output, acceptance criteria, explicit exclusions, non-negotiable
   constraints, and affected touchpoints concrete. Ask only questions that
   remain material after scouting; ground every question in discovered evidence
   or a named gap. Repeat this step while any field remains vague or untestable.
6. **Define and author behavior:** Record purpose, in/out scope, actors, user needs,
   preconditions, trigger, main flow, material alternative and exception flows,
   postconditions, requirements, and acceptance in exactly the five canonical H2
   sections of the generated draft.
7. **Brainstorm behavior variants:** When multiple observable business policies
   remain viable, apply the local `brainstorm` behavior and present two or three
   concrete variants with evidence, user impact, trade-offs, risks, and testable
   acceptance. When only one policy satisfies authority and evidence, explain
   why alternatives are non-viable. Do not introduce technical architectures or
   library choices.
8. **Obtain the material choice:** Ask Product Authority to select or revise a
   variant when the choice changes observable behavior, scope, compatibility,
   risk acceptance, or success evidence. Record no implicit default.
9. **Interrupt for product Decision when needed:** If selecting a business
   policy requires durable rationale, create a proposed Decision linked to the
   proposed Feature. Resume Feature discovery after human judgment.
10. **Verify readiness:** Recheck every material requirement and acceptance item
   against the evidence summary and Product Authority answers. Invoke and consume
   `ckh workflow check TARGET` (where `TARGET` is the exact Feature ID or
   basename) to validate the Feature state. Approval remains
   unavailable while a Failed or Unresolved (TBD) item can change behavior,
   scope, constraints, touchpoints, or acceptance.
11. **Request and record review:** Product Authority reviews the complete business
    boundary. If approved, invoke and consume
    `ckh feature approve TARGET --approved YYYY-MM-DD --approved-by AUTHORITY` to
    record declared approval provenance. If changes are requested, invoke and
    consume `ckh feature request-changes TARGET`; the agent does not choose either
    outcome.

## Output
An approved Feature artifact (resolved from the configuration, by default `docs/harness/features/FEAT-XXX-*.md`), or a documented
no-change/existing-contract outcome that creates no duplicate Feature. Feature
completion does not require a Coding Plan.

## Completion Criteria
- Exactly the five H2 sections exist and content validation passes.
- Actors are people, business roles, or external systems.
- Material evidence is labeled Observed, Inferred, Failed, or Unresolved (TBD).
- Expected output, acceptance criteria, exclusions, constraints, and touchpoints
  are concrete and testable.
- Every material choice not resolved by evidence has an explicit Product
  Authority answer or an approved Decision.
- Every outgoing relationship resolves.
- Approval date and Product Authority are recorded for approved behavior.
- No implementation design appears in the Feature behavior.

## Prohibited Actions
- Do not create a Feature for every repository task.
- Do not ask material questions or propose behavior variants before project and
  codebase research establishes the relevant evidence.
- Do not select a material behavior, scope, compatibility, risk, or acceptance
  choice on behalf of Product Authority.
- Do not grant, infer, or invent human approval authority (only record declared human approval provenance).
- Do not manually reason about or mutate mechanical state without first invoking and consuming the corresponding CLI command.
- Do not create Plans or modify product code during Feature discovery.
- Do not place implementation design in the Feature; when Coding work needs a
  separate design, use `design.md` beside and linked by its owning `plan.md`.
- Do not place classes, services, libraries, schemas, or source layout in the
  actor and flow model.
- Do not allocate an ID without advancing the monotonic sequence safely.

## Failure and Recovery
- **Wrong route:** Reuse the governing Feature or Spec and stop Feature discovery;
  continue to Plan only when Coding work is separately requested.
- **Missing information:** Keep material gaps as Unresolved (TBD), name the
  smallest verification or Product Authority answer needed, and withhold approval.
- **Failed evidence:** Record the failing path, command, or contract and revise
  the proposed behavior; do not preserve the contradicted claim.
- **Rejected boundary / request-changes:** If Product Authority requests changes, invoke `ckh feature request-changes TARGET`. This sets/keeps the Feature status to `proposed` and clears approval provenance; it does not produce a terminal rejected state. Revise the behavior and resubmit; do not authorize implementation.
- **CLI failure and manual fallback:** If a CLI command is unsupported or fails, apply the named manual recovery path: manually edit the affected markdown or frontmatter files to repair the state, run `ckh validate` to verify mechanical validity, and never claim the failed command succeeded.
- **Recovery boundary:** Preserve the strict recovery boundary: do not automatically
  start Cook, mutate Git, access the network, start a watcher or daemon, or create
  hidden state.
- **Product trade-off:** Pause Feature approval, run Decision using the proposed
  Feature as context, then resume discovery.
- **Material revision after approval:** Return the Feature to proposed, preserve
  history through version control, and invalidate affected downstream approval.
- **Document-only completion:** After approval, stop when no repository
  implementation was requested.
- **Optional Coding handoff:** When coding is requested, resolve every governing
  Feature and blocking Decision before the Plan approval boundary.
