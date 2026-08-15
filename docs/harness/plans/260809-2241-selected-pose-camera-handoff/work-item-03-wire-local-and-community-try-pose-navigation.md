---
work_item: 3
title: Wire local and community Try Pose navigation
status: pending
priority: P1
effort: M
dependencies:
  - 2
decision_dependencies: []
---

# Work Item 3: Wire local and community Try Pose navigation

**Kind:** story

## Tasks

- Map resolved personal and community detail models into a transparent-image
  render descriptor, validating and decoding the local or downloaded asset.
- On Try Pose, prepare the managed render cache and durably commit selection
  first, then switch to Camera only after success; keep the user on detail with
  a recoverable message on download/read/decode/persistence failure.
- Make both detail variants use the same typed action path while preserving
  source-specific IDs and prohibiting destructive cross-source behavior.
- Define back-stack behavior so returning to Poses does not duplicate screens or
  silently clear/replace the active reference.
- Add navigation tests covering personal/community selection, invalid asset,
  missing record, rapid double tap, replacement, and return navigation.

## Scope and affected files

- Local/community detail state, `Navigation.kt`, active-reference adapters, and
  navigation tests.

## Success criteria

- Both Try Pose flows arrive at Camera with the intended source-qualified active
  reference; no tab switch can occur with discarded or wrong selection data.

## Risks

- Passing a remote URL as a durable render asset breaks relaunch/offline restore;
  Camera navigation requires a validated managed local render asset.

## Required evidence

- Automated navigation/state assertions plus simulator screen evidence for both
  reference origins and failure recovery.
