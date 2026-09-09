---
name: ask
description: Analyze technical or architectural questions with repository evidence, explicit assumptions, alternatives, risks, and verification advice. Use for consultation, explanation, best-practice evaluation, or solution comparison when no implementation is requested.
---

# Ask

Answer the question without implementing a solution or mutating the repository.

## Workflow

1. Read `docs/harness/index.md` and the smallest relevant canonical documents,
   source files, tests, configuration, and unfinished Plans.
2. Restate the concrete question, constraints, and decision boundary. Ask only
   for material context that approved authority or direct evidence cannot supply.
3. Classify material claims as:
   - **Observed:** directly supported by a file, command, or approved authority.
   - **Inferred:** supported reasoning that is not a direct fact.
   - **Failed:** contradicted by a reproducible check.
   - **Unresolved:** evidence or human authority is still required.
4. Compare viable alternatives when the question contains a real choice. Apply
   KISS, YAGNI, and DRY; include costs, compatibility, operational impact, and risk.
5. Recommend an option only when evidence and approved constraints support it.
   If a material product, scope, architecture, compatibility, or risk choice
   remains open, present it to the responsible human and do not record a selection.
6. State how the answer can be verified and identify any residual uncertainty.

## Output

- Direct answer.
- Evidence and assumptions.
- Alternatives and trade-offs, when applicable.
- Risks and verification points.
- Unresolved questions or next action.

Keep the response concise and candid. Do not claim certainty that the evidence
does not provide, and do not create a Feature, Plan, Decision, or code change
unless the user separately requests that workflow.
