# Self-Improve Workflow

## Purpose

Turn verified delivery evidence into small, human-approved improvements to the
harness knowledge base and working method. Rule promotion is one possible
outcome; it is not the entire workflow.

## Use When

Use after a Delivery Report or Decision identifies friction, stale guidance,
missing validation, repeated mistakes, or a useful pattern that may improve a
Spec, template, workflow, project policy, or promoted Rule.

## Inputs

- Completed Delivery Reports (`REP-XXX`) and approved Decisions (`DEC-XXX`).
- Their verification evidence, plan variance, friction notes, and optional
  `recurrence_key` values.
- Current Specs, templates, workflows, `RULES.md`, and promoted `RULE-XXX`
  artifacts.
- Wikilinks, index relationships, and the optional derived retrieval artifact.

## Hard Gates

- **Evidence Gate:** Every proposed improvement must cite direct evidence. An
  agent opinion or confidence statement is not evidence.
- **Classification Gate:** Classify the signal before changing anything:
  isolated incident, documentation drift, workflow/template friction, missing
  validation, durable decision, or recurring rule candidate.
- **Human Approval Gate:** A human must approve the target, scope, and wording
  before any canonical policy, workflow, template, Spec, or Rule changes.
- **Recurrence Gate for Rules:** Promoting `RULE-XXX` requires at least two
  independent Reports or Decisions with the same stable `recurrence_key` and a
  shared reusable lesson.
- **No Recursive Automation Gate:** The CLI may list candidates and validate
  approved edits, but it must never rewrite its own rules or workflows
  automatically.

## Procedure

1. **Capture the Signal:** Record the observed friction, consequence, evidence,
   and suggested follow-up in the originating Report or Decision. Add a stable
   `recurrence_key` only when future occurrences should be grouped.
2. **Classify the Signal:** Route it to the smallest suitable outcome:
   - isolated defect or task-specific issue → keep it in the Report or create
     follow-up work; do not create a general rule;
   - stale technical truth → propose a focused Spec correction;
   - unclear authoring structure → propose a template correction;
   - repeated process friction → propose a workflow improvement;
   - durable trade-off → interrupt with the Decision Workflow and return to the
     Self Improve proposal after resolution;
   - repeated reusable lesson → evaluate a promoted Rule.
3. **Search Existing Guidance:** Check Specs, Decisions, workflows, templates,
   `RULES.md`, and promoted Rules for an existing answer. Prefer correcting or
   superseding existing guidance over creating duplicates.
4. **Aggregate Recurrence:** For a rule candidate, locate at least two
   independent sources with the same `recurrence_key`. Confirm they represent
   separate occurrences and the same underlying lesson.
5. **Draft the Smallest Improvement:** State the target file, exact change,
   expected benefit, evidence links, possible side effects, and verification
   method. Use 2–3 alternatives when the improvement has a meaningful
   trade-off; list the simplest viable option first.
6. **Request Approval:** Present the proposal to the human. Do not mutate a
   canonical document before approval.
7. **Apply the Approved Change:** Make only the approved edit:
   - Spec, template, or workflow improvement → update the canonical file and
     preserve its established contract;
   - project policy improvement → update `RULES.md` while retaining stable
     `R-XXX` labels;
   - promoted rule → allocate the next monotonic `RULE-XXX`, copy
     `templates/rule.md`, link the evidence, and supersede conflicting rules
     rather than rewriting history.
8. **Verify:** Run relevant schema, link, snapshot, workflow, and test checks.
   Confirm the change introduces no broken references or contradictory
   guidance.
9. **Close the Loop:** Record the accepted improvement and verification result
   in a Report or Decision. Rebuild the derived index through tooling when that
   capability exists.
10. **Inspect Relationships (Optional):** Use the built-in retrieval artifact
    only after `ckh graph check` confirms freshness. If it is missing, stale, or
    malformed, warn and continue with canonical Markdown and index checks. Query
    output is derived evidence and removable state; it never replaces document
    authority.

## Output

Exactly one of these evidence-backed outcomes:

- no change, with the reason recorded;
- a retained candidate awaiting more evidence;
- an approved update to a Spec, template, workflow, or `RULES.md`;
- an approved Decision; or
- an active Rule artifact (resolved from the configuration, by default `docs/harness/rules/RULE-XXX-kebab-name.md`) linked to at least two
  independent occurrences.

## Completion Criteria

- The signal is classified and linked to its source evidence.
- The human approved every canonical change.
- The applied change is the smallest one that addresses the evidence.
- Rule promotion, when selected, has two independent recurrence sources and
  matching filename/frontmatter ID.
- Relevant validation and tests pass, with results recorded.
- No duplicate, broken link, contradictory guidance, hidden trace state, or
  unapproved external data transfer was introduced.

## Prohibited Actions

- Do not automatically rewrite rules, workflows, templates, or Specs.
- Do not promote a Rule from one occurrence, one incident split across multiple
  files, or unsupported opinion.
- Do not use Self-Improve to bypass the Feature, Decision, Plan, or Cook gates.
- Do not store learning in a database, hidden trace ledger, chat transcript, or
  retrieval artifact.
- Do not make unrelated cleanup changes while applying an approved improvement.

## Failure and Recovery

- **Insufficient Evidence:** Keep the candidate in its Report or Decision and
  wait for independent evidence; do not promote it.
- **Conflicting Guidance:** Pause and use the Decision Workflow to choose which
  contract should govern, then supersede the losing guidance explicitly.
- **Verification Failure:** Leave the improvement unaccepted, fix or revert
  only the authorized edit without discarding user changes, and rerun checks.
- **Retrieval artifact unavailable or stale:** Warn and continue using canonical
  wikilinks and index checks; do not infer freshness from query results.
- **Handoff Boundary:** The workflow ends after the improvement is approved,
  verified, and recorded. A resulting product behavior change starts Feature;
  maintenance inside existing authority starts Plan; a durable policy choice
  interrupts through Decision and then returns to the appropriate boundary.
