---
title: "ios-camera-pose-reference"
description: "Lane BACKLOG — durable Try Pose → Camera overlay handoff trên iOS; bổ sung executable phases cho Harness plan 260809-2241."
status: pending
priority: P0
branch: "backlog/ios-camera-pose-reference"
lane: backlog
persona: "Lính · Bàng Đức"
tags: ["ios", "camera", "pose-overlay", "try-pose", "feat-003", "feat-008"]
blockedBy:
  - "docs/harness/plans/260809-2240-pose-reference-library-convergence"
  - "docs/harness/plans/260809-1806-camera-source-of-truth-convergence"
blocks:
  - "product-delivery-roadmap Phase 2 complete"
created: "2026-08-30T13:27:00+07:00"
source_report: "docs/harness/reports/REP-012-backlog-lane-documentation-survey.md"
harness_plan: "docs/harness/plans/260809-2241-selected-pose-camera-handoff/plan.md"
---

# iOS Camera Pose Reference (Try Pose Handoff)

## Overview

**Vấn đề:** User chọn Try Pose từ pose detail (My Poses hoặc Community) nhưng Camera không nhận overlay; selection không survive relaunch (`README.md` § Current limitations).

**Giải pháp:** Hoàn thiện handoff theo Harness plan `260809-2241`: persist active pose reference + managed render asset, chuyển tab Camera sau khi resolve thành công, render overlay trong suốt với điều khiển prototype-parity, không đổi capture semantics.

Plan lane BACKLOG này **không thay** Harness authority — map work items 2241 sang phase executable và ghi gates/verification cho cook lane.

## Goals

- Try Pose từ local và community detail set active reference trước khi vào Camera.
- Camera hiển thị pose overlay (default opacity 50%), toggle visibility, clear selection.
- Selection và render asset survive app termination + relaunch until replaced/cleared.
- Loading/failure có fallback rõ ràng; shutter behavior unchanged (FEAT-001).

## Non-goals

- Saved Poses server sync (FEAT-008 Phase 3 business).
- Paywall / entitlement gates (FEAT-011).
- Dual-layer source image background (plan `260510-1726`).
- Admin UI hoặc extract server changes.
- Android build target.

## Contracts

### API

- **Không HTTP mới.** Try Pose là local prepare từ detail; public catalogue đã có `GET /api/community/poses` khi nguồn community.
- Error envelope khi fetch image: tuân `docs/spec/api/conventions.md` nếu community CDN/API fail.

### Data

| Contract | Authority | Vai trò |
| --- | --- | --- |
| `PreparedPoseReference` | `docs/spec/data/entities/prepared-pose-reference.md` | Transient emit từ Try Pose |
| Active pose reference (app-level) | Harness plan 2241 `design.md` + WI-02 | Persistent selection + managed cache path |
| `Photo` local link | `docs/spec/data/entities/photo.md` | Capture output; không gán ownership pose |

### UI

- Visual overlay: `docs/prototype/screens/camera-pose-overlay.html`, tokens `design.md` / `tokens.css`.
- Production interaction: `docs/harness/specs/ui-ux-system.md` § Camera + FEAT-003/008 acceptance.
- Controls: clear, toggle overlay, opacity adjustment per prototype/harness WI-04.

### Admin / Ops

- Không thay đổi admin surface.
- Ops: không deploy server; evidence Mobile MCP real iPhone.

## Phases

| Phase | Name | File | Effort |
| --- | --- | --- | --- |
| 1 | Authority & parity matrix | [phase-01-authority-and-parity.md](./phase-01-authority-and-parity.md) | 2h |
| 2 | Active pose reference state | [phase-02-active-pose-reference-state.md](./phase-02-active-pose-reference-state.md) | 4h |
| 3 | Try Pose navigation wiring | [phase-03-try-pose-navigation-wiring.md](./phase-03-try-pose-navigation-wiring.md) | 3h |
| 4 | Camera overlay & controls | [phase-04-camera-overlay-controls.md](./phase-04-camera-overlay-controls.md) | 5h |
| 5 | Verification & rollout | [phase-05-verification-rollout.md](./phase-05-verification-rollout.md) | 4h |

## Phase dependencies

```text
Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5
Prerequisites (external): 260809-2240, 260809-1806 land or equivalent authority closure
```

## Acceptance (plan-level)

- [ ] Try Pose local + community routes Camera chỉ sau resolve asset thành công.
- [ ] Overlay visible default 50% opacity; toggle/clear hoạt động trên real iPhone.
- [ ] Kill app → relaunch → overlay restored hoặc explicit empty state.
- [ ] Capture vẫn tạo Photo local; không regression FEAT-001 tests.
- [ ] Harness `ckh workflow check 260809-2241-selected-pose-camera-handoff` pass khi cook harness plan.

## Verification

| Layer | Command / evidence |
| --- | --- |
| Unit | State store select/replace/clear; navigation tests (Harness WI-02/03) |
| Compose | Camera presentation overlay tests (Harness WI-04) |
| Device | Mobile MCP real iPhone scenario (Harness WI-05) |
| Docs | Plan phase checklists; no drift vs FEAT-003 relaunch acceptance |

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Prerequisite plans chưa land | High | Gate Phase 2+ cook; track harness approval |
| Large image decode memory | Medium | Downscale managed render asset; cache eviction |
| Community fetch fail | Medium | Inline error on detail; không navigate Camera |
| Overlay blocks gestures | High | Non-interactive overlay layer (prototype parity) |

## Rollout / Rollback

**Rollout:** Feature flag không bắt buộc — behavior là completion MVP loop. Ship sau real-iPhone evidence.

**Rollback:** Revert active reference store + overlay branch; Try Pose lại chỉ switch tab (hiện trạng). Không migration server.

## Gates

| Gate | Owner | Blocker |
| --- | --- | --- |
| Harness 2241 approval | Repository Maintainer | Cook harness track |
| Prerequisites 2240/1806 | Maintainer | Authority closure Phase 1 |
| REP-012 accepted | Lead | Docs lane closure |
| Real-iPhone evidence | QA / executor | Release claim overlay |

## Cross-references

- Roadmap: [`../260830-1327-snap-pose-roadmap/roadmap.md`](../260830-1327-snap-pose-roadmap/roadmap.md)
- Survey: [`docs/harness/reports/REP-012-backlog-lane-documentation-survey.md`](../../docs/harness/reports/REP-012-backlog-lane-documentation-survey.md)
- Harness plan: [`docs/harness/plans/260809-2241-selected-pose-camera-handoff/plan.md`](../../docs/harness/plans/260809-2241-selected-pose-camera-handoff/plan.md)
