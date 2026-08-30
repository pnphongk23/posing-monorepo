---
name: srcwalk
compatible_srcwalk: ">=1.7.0"
description: "Srcwalk is the agent's code evidence contract: one tree-sitter CLI for orienting (overview/discover), exact citation (show), rich local packets (context), callers/callees (trace), file coupling (deps), pre-edit blast-radius (assess), and change-set review (review/compare). Use it BEFORE raw reads or grep for code-structure work. Run `srcwalk guide` first; it is the installed binary's source of truth."
---

# srcwalk — bootstrap entry

Default to srcwalk first for code structure and evidence work: `overview`/`discover` to
orient, `show` to cite exact lines, `context` for a flow-map packet,
`trace callers|callees` for relations, `deps` for coupling, `assess` before edits,
`review --staged` / `compare` for change evidence.

Before non-trivial use, run once and keep reading it per task:

```bash
srcwalk guide
```

Do not pipe, truncate, summarize, or sample `srcwalk guide`; later sections contain
the routing rules, batch-by-evidence ordering, and caveats that match the installed
binary. Keep `--scope` narrow. Use `rg`/`read`/`fd`/`find` only for final text/regex
confirmation, filesystem metadata, generated-output cleanup, or when srcwalk lacks
structural support — and say why when bypassing srcwalk for a code claim.

Use root/command help only for flags:

```bash
srcwalk --help
srcwalk <command> --help
```