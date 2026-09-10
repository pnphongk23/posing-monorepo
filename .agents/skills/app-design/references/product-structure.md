# Product patterns, information structure, and navigation

Read this reference when designing a new screen/flow or choosing presentation
and navigation semantics.

## Research artifact

Study multiple strong references solving the same user intent. For important
work, aim for at least 10 references; use more when the category is varied.
Classify observations as common pattern, category pattern, product-specific
expression, or outlier.

Record internally:

```text
REFERENCE STUDY
Task:
User goal:
Screen/flow category:
References studied:

COMMON PATTERNS
- Structure:
- Hierarchy:
- Primary action:
- Controls:
- Navigation:
- State handling:
- Motion:

MEANINGFUL VARIATIONS
- Variation:
- Why it differs:

ADOPT:
AVOID:
OUR INTERPRETATION:
```

Use `Reference → Pattern → Principle → Product-specific implementation`, never
`Reference → pixel copy`. Product-specific choices and outliers need an explicit
reason before being generalized.

## Information structure

Define one dominant objective and classify content as primary, supporting,
contextual, or optional. Start from this skeleton:

```text
Navigation context
Primary content
Supporting content
Primary action
Secondary actions
```

Use higher density for browsing, comparison, repeated operations, and data-heavy
work. Use lower density for onboarding, explanation, emotional moments, major
decisions, and rare tasks. Give one intent one canonical label.

## Navigation semantics

Before selecting a transition, answer:

```text
What is this destination relative to the current context?
Should the user be able to return?
What should Back do afterward?
```

- Push for subordinate content the user should return from.
- Give create, compose, checkout, editing, and multi-step setup their own
  presentation context with defined entry, cancel, internal navigation, and
  completion behavior.
- Use a short interruption for filters, pickers, sorting, options, and short
  configuration. If it gains sequential steps, promote it to a task flow.
- Use forward-only replacement/dismissal when the prior state is obsolete, such
  as completed onboarding or an invalidated session.
- Use system-owned behavior when the platform owns the interaction.
- A temporary expanded, selected, or local overlay state may consume the first
  Back; the next Back leaves the screen.
- Deep links should land in a meaningful stack. Do not flash a wrong route while
  session state is unresolved.
