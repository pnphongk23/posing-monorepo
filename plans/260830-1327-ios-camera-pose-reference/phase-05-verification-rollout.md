---
phase: 5
title: "Verification handoff"
status: pending
priority: P0
effort: "4h"
dependencies: ["phase-04"]
---

# Phase 5: Verification Handoff

## Mục tiêu

Real-iPhone evidence + Harness workflow closure — **future execution cook**, không approval từ docs lane.

## Goals

- Scenario: detail → Try Pose → promote → Camera overlay (pan/zoom/opacity) → capture → gallery.
- Relaunch mid-flow: restore durable overlay.
- Document evidence; run `ckh workflow check 260809-2241`.

## Non-goals

- App Store release.
- Sửa README limitations trong docs-only lane (ghi note cho cook PR).

## Contracts

- Evidence: Mobile MCP plan 260809-1805 format.
- Relaunch acceptance: FEAT-008 + plan 2241 — **không** gán cho README § limitations là sole authority.

## Tasks

1. Mobile MCP real iPhone scenario.
2. KMP tests: navigation, durable store, overlay regression including pan/zoom.
3. Delivery report follow-up (post-cook) linking REP-006 boundary update.
4. Maintainer approval Harness 2241 if criteria met.

## Acceptance (future cook)

- [ ] Real-iPhone screenshots/recording attached.
- [ ] `ckh workflow check 260809-2241-selected-pose-camera-handoff` pass.
- [ ] No regression FEAT-001 capture tests.

## Verification

| Check | Command |
| --- | --- |
| KMP | `./gradlew :composeApp:compileKotlinIosSimulatorArm64 :shared:iosSimulatorArm64Test` |
| Harness | `ckh workflow check 260809-2241-selected-pose-camera-handoff --workspace .` |

## Risks

- Device unavailable → BLOCKED_NEEDS_LEAD for release **claim** (cook can still merge with simulator-only if Maintainer accepts).

## Rollout / Rollback (future execution)

Cook PR merge per Maintainer; monitor crashes (FEAT-010 separate). **Ship** language chỉ dùng sau evidence + approval — không từ plan docs.

## Gate

**Human Approval Gate** — Maintainer approves Harness 2241 before business roadmap Phase 2 “complete” marketing.
