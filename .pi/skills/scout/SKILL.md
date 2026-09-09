---
name: scout
description: Research a local project and codebase into an evidence-backed mental model. Use to understand project purpose, stack, architecture, execution flows, dependencies, tests, conventions, operations, active work, risks, or relevant implementation before Feature, Brainstorm, Plan, debugging, or review work.
---

# Scout

Research the project and codebase through direct, read-only local inspection.
Build enough context to explain how the relevant system works; a file list alone
is not a complete result.

## Workflow

1. Define the research target and the decisions or downstream work it must
   inform. Name material gaps instead of filling them with assumptions.
2. Establish the project baseline from repository-owned READMEs, manifests,
   build files, entry points, configuration, and commands. Identify purpose,
   product surface, languages, frameworks, repository shape, and build, run,
   test, or deployment paths when relevant.
3. Read `docs/harness/index.md` first when Harness authority or workflow state
   matters. Inspect governing documents, unfinished related Plans, delivery
   reports, and preserved working-tree changes.
4. Map architecture before deep tracing: modules and boundaries, public
   contracts, state and storage, integrations, and the primary control or data
   flows related to the target.
5. Trace the relevant implementation through definitions, callers, callees,
   configuration, error handling, tests, and observable outputs. Use `rg` and
   `rg --files`, then open the evidence behind every material conclusion.
6. Examine dependencies, conventions, quality gates, CI or operational paths,
   compatibility constraints, and active work that can affect the answer.
7. Synthesize the evidence into a coherent project and codebase mental model.
   Label material claims as **Observed**, **Inferred**, **Failed**, or
   **Unresolved** and cite paths, symbols, relationships, or commands.
8. Check that the result answers the research target, covers relevant risks and
   unknowns, and explains behavior rather than merely listing matches. Stop
   before design, planning, implementation, or unrelated exhaustive inventory.

## Output

```markdown
# Scout Report

## Research scope
- Target, depth, and boundaries

## Project overview
- Purpose, stack, repository shape, entry points, and commands as relevant

## Architecture and flows
- Components, boundaries, state, and control or data flow

## Relevant code
- `path/to/file` or symbol — role in the traced behavior

## Dependencies and integrations
- Internal or external dependency, configuration, and compatibility boundary

## Quality and operations
- Tests, conventions, error handling, CI, build, run, or deployment evidence

## Active work and constraints
- Governing artifact, unfinished Plan, preserved change, or operational limit

## Findings and risks
- **Observed | Inferred | Failed | Unresolved:** conclusion with direct evidence

## Unknowns
- Material gap and the smallest next check or human answer needed
```

Include only applicable sections, but never omit the research scope, evidence
labels, risks, or material unknowns. Report failed searches and unavailable
checks explicitly. Never treat a missing result as proof that behavior does not
exist without checking relevant alternate names, generated files, configuration,
and call paths. Do not change repository files while scouting.
