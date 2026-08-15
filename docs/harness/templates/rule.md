---
schema_version: 1
type: rule
id: RULE-000
title: Verify externally visible failure behavior
status: active
approved: 2026-01-01
scope:
  - order workflows
relationships:
  specs:
    - "[[testing]]"
  decisions: []
  plans: []
  reports:
    - "[[REP-000-order-confirmation|REP-000]]"
  rules: []
  features: []
  source_paths: []
---

# RULE-000: Verify externally visible failure behavior

## Guidance

Test the failure postcondition whenever a workflow depends on an external system.

## Scope

Order workflows that call an external system.

## Rationale

A success-only test cannot prove that partial state is prevented.

## Evidence

- [[REP-000-order-confirmation|REP-000]]

## Exceptions

None. Propose a superseding decision if the behavior cannot be observed.

## Verification

Run the relevant negative-path test and record its command and result.
