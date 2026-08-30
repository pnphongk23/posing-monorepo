---
phase: 5
title: "Verification and rollout"
status: pending
priority: P0
effort: "4h"
dependencies: ["phase-04"]
---

# Phase 5: Verification & Rollout

## Mục tiêu

Real-iPhone evidence và closure gates (Harness WI-05 + backlog lane acceptance).

## Goals

- End-to-end scenario: browse/detail → Try Pose → Camera overlay → capture → gallery.
- Document evidence paths; sync harness plan 2241 workflow check.

## Non-goals

- App Store release.
- Load testing extract server.

## Contracts

- Evidence contract: Mobile MCP plan 260809-1805 format (screenshot, a11y snapshot, crash delta).

## UI / Admin / Ops

- Ops runbook: none server-side; iOS install via existing gradle/iosApp path.

## Tasks

1. Execute Mobile MCP scenario on real iPhone.
2. Run full mobile test suite relevant to navigation + camera.
3. Update harness delivery report stub or link REP-012 follow-up.
4. Maintainer approval harness plan 2241 if criteria met.

## Acceptance

- [ ] Real-iPhone recording/screenshots attached to report.
- [ ] Zero new crashes in scenario delta.
- [ ] `ckh workflow check 260809-2241-selected-pose-camera-handoff` pass.
- [ ] README § Current limitations updated at cook time (out of docs lane scope note).

## Verification

| Check | Command |
| --- | --- |
| KMP tests | `./gradlew :composeApp:compileKotlinIosSimulatorArm64 :shared:iosSimulatorArm64Test` |
| Mobilewright | existing camera test per ui-ux-system |
| Harness | `ckh workflow check 260809-2241-selected-pose-camera-handoff --workspace .` |

## Risks

- Device farm unavailable → BLOCKED_NEEDS_LEAD for release claim.

## Rollout

1. Merge backlog + harness branches per Maintainer.
2. Monitor crash-free sessions post-ship (FEAT-010 separate).

## Rollback

Revert Phases 2–4; user sees pre-handoff behavior documented in README.

## Gate

**Human Approval Gate** — Repository Maintainer approves harness plan 2241 before marketing Phase 2 business roadmap complete.
