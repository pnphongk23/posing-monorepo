---
name: brainstorm
description: Explore a feature, design, or technical problem through scout-first discovery, exact requirements, two or three viable approaches, and evidence-backed trade-offs. Use before selecting an unclear behavior or implementation direction; stop before implementation and require human confirmation for material choices.
---

# Brainstorm

Explore the problem collaboratively without implementing a solution.

## Hard gates

- Scout the relevant repository surface before asking material questions or
  proposing approaches.
- Do not proceed to alternatives until these five fields are concrete:
  expected output, acceptance criteria, explicit exclusions, non-negotiable
  constraints, and affected touchpoints.
- Do not record a material choice without confirmation from the responsible human.
- Do not write code or begin Cook during brainstorming.

## Workflow

1. **Scout:** Use the local `scout` behavior to inspect the project type,
   canonical Harness documents, relevant modules, established patterns, tests,
   dependencies, configuration, and unfinished related Plans.
2. **Summarize evidence:** Report three to six relevant findings. Distinguish
   observed, inferred, failed, and unresolved claims.
3. **Discover exact requirements:** Resolve the five hard-gate fields. Ground
   each question in a file, pattern, constraint, or missing verification. Ask
   another focused round when an answer remains too vague to test.
4. **Challenge scope:** Identify independent concerns, hidden dependencies,
   unnecessary expansion, and assumptions that conflict with current authority.
5. **Explore approaches:** Present two or three viable approaches with:
   - behavior or architecture outline;
   - advantages and disadvantages;
   - migration and compatibility impact;
   - security, performance, operational, and maintenance risks as applicable;
   - validation strategy and evidence gaps.
6. **Recommend:** Prefer the smallest approach satisfying the verified
   constraints. Explain why other approaches are weaker or non-viable.
7. **Confirm:** Ask the responsible human to select or revise the approach when
   the choice affects product behavior, scope, architecture, compatibility,
   risk acceptance, or success evidence.
8. **Handoff:** Summarize the agreed requirements, chosen approach, rationale,
   risks, verification criteria, and remaining questions. Enter Feature,
   Decision, or Plan only when separately requested and allowed by its workflow.

## Anti-rationalization

- "The task is simple" does not replace a concrete acceptance criterion.
- "The existing pattern is obvious" requires a cited example.
- "The recommended option is standard" does not authorize a human decision.
- "Verification can happen during implementation" does not justify an
  unverified Plan claim.

Keep the output concise. Exclude approaches that violate approved authority or
direct evidence instead of presenting decorative options.
