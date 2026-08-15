# Decision Workflow

## Purpose
Evaluate and preserve the rationale for a durable product or technical trade-off
that future work must inherit.

## Use When
Use when two or more viable paths have material, cross-cutting,
expensive-to-reverse, security, data-ownership, API, validation, source-of-truth,
or product-policy consequences. Keep local, mandated, and cheaply reversible
choices in the governing Spec or Plan.

## Inputs
- A proposed or approved Feature for product choices.
- An approved Feature or active semantic Spec for technical choices.
- Existing Decisions, Rules, repository evidence, and the workflow boundary that raised the choice.

## Hard Gates
- **Durability Gate:** The choice must justify durable Decision history.
- **Alternative Viability Gate:** Evaluate at least two credible alternatives,
  including the status quo when it is viable.
- **Evidence Gate:** Consequences and recommendation must cite direct evidence or an explicit bounded spike.
- **Human Approval Gate:** Product Authority approves product choices;
  Repository Maintainer approves technical choices.

## Procedure
1. **Identify return boundary:** Record whether the Decision interrupts Feature,
   Plan, Cook, or Self Improve.
2. **Analyze authority and constraints:** Read the linked Feature, Specs,
   Decisions, Rules, and source evidence.
3. **Confirm durability:** If the choice is local, mandated, or cheaply
   reversible, record it in the Plan or Spec and return without a DEC artifact.
4. **Formulate alternatives:** Compare the smallest credible set, state benefits,
   costs, risks, reversibility, and evidence, and recommend one.
5. **Draft Decision:** Allocate the next monotonic `DEC-XXX`, write `created`,
   keep status `proposed`, and link the affected artifacts.
6. **Handle supersession:** When replacing an approved Decision, link it through
   `supersedes` and update the old Decision to `superseded` only after approval.
7. **Obtain authority:** Record approved or rejected outcome, date, and authority.
8. **Update affected contracts:** Change Feature, Spec, or Plan only within the
   approved outcome and reset downstream approval when scope or criteria changed.
9. **Return:** Resume the workflow boundary that raised the Decision.

## Output
One of:
- an approved, rejected, or superseding `DEC-XXX` artifact;
- a local choice retained in Plan or Spec because no durable Decision was needed.

## Completion Criteria
- Status and approval or rejection provenance conform to [[workflow-lifecycle]].
- Alternatives, selected outcome, consequences, evidence, and supersession are explicit.
- Required authority matches product or technical ownership.
- Inbound and outbound wikilinks resolve.
- The affected workflow resumes at the correct boundary without silently expanding scope.

## Prohibited Actions
- Do not create Decisions for every implementation detail.
- Do not treat `proposed` or `rejected` as normative.
- Do not modify product code while deciding, except for an explicitly authorized
  disposable spike that cannot affect production behavior.
- Do not delete or rewrite superseded history.
- Do not let a Plan or current code override Feature, Spec, Rule, or approved Decision authority.

## Failure and Recovery
- **Not durable:** Record the choice in Plan or Spec and return without allocating an ID.
- **Rejected proposal:** Mark materially reviewed history rejected or revise the alternatives and resubmit.
- **Insufficient evidence:** Run a bounded spike or retain the unresolved dependency; do not guess.
- **Conflicting authority:** Return to the owning Feature, Spec, Rule, or Decision before resuming.
- **Handoff:** After resolution, update affected artifacts and return to Feature,
  Plan, Cook, or Self Improve at the recorded boundary.
