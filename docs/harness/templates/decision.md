---
schema_version: 1
type: decision
id: DEC-000
title: Choose the canonical persistence format
status: proposed
created: 2026-01-01
relationships:
  specs:
    - "[[architecture]]"
  decisions: []
  plans: []
  reports: []
  rules: []
  features:
    - "[[FEAT-000-confirm-order|FEAT-000]]"
  source_paths: []
---

# DEC-000: Choose the canonical persistence format

## Context

State must be inspectable and portable across supported agent runtimes.

## Decision

Use repository Markdown with parsed YAML frontmatter as canonical state.

## Alternatives

- SQLite: stronger transactions but hidden from ordinary review workflows.
- JSON: easy to parse but poor for durable narrative documents.

## Consequences

Humans can review state directly; the CLI must detect concurrent or malformed edits.

## Evidence

- [[architecture]]

## Supersession

This decision supersedes no earlier decision.
