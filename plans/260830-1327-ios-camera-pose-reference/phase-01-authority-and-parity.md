---
phase: 1
title: "Authority and parity matrix"
status: pending
priority: P0
effort: "2h"
dependencies: []
---

# Phase 1: Authority & Parity Matrix

## Mục tiêu

Đóng authority gap giữa FEAT-003, FEAT-008, Harness plan 2241, prototype, và **evidence code hiện tại** trước future cook.

## Goals

- Parity matrix đầy đủ (Prototype | Harness | Current code | Residual gap) — xem `plan.md` § Parity matrix.
- Phân biệt rõ: partial session overlay **đã có** vs durable relaunch **chưa có**.
- Xác nhận prerequisite plans 2240/1806 với Maintainer.

## Non-goals

- Sửa code (kể cả comment stale `Navigation.kt:282`).
- Thay đổi API/data spec ngoài ghi chú migration field names.

## Contracts

- FEAT-003: browse/detail/Try Pose prepare boundary (`REP-006`).
- FEAT-008: relaunch persistence acceptance — authority durable handoff.
- `PreparedPoseReference`: transient; `ActivePoseReference`: app-level (2241 design).
- **Không** tạo entity catalogue mới.

## Tasks

1. Reconcile `REP-006` `E-2241-BOUNDARY` với `CameraScreen.kt` hiện tại (không còn `if (false)` render guard).
2. Ghi field migration: code `poseName`/`skeletonPath` → spec `name`/`skeletonLocator` + `mediaId`.
3. Maintainer sign-off prerequisite + Harness 2241 approval path.

## Acceptance

- [ ] Matrix trong `plan.md` reviewed; mọi residual gap P0 map phase 2–5.
- [ ] Không claim ship durable; không cite REP-002 `if (false)` là current state.

## Verification

- Docs review; `ckh validate` targeted REP-012 pass.

## Risks

- Unapproved FEAT → BLOCKED_NEEDS_LEAD cho cook.

## Rollout / Rollback

Docs-only; rollback = revert plan edits.

## Gate

**Authority Closure Gate** — future cook Phase 2+ cần FEAT-008 relaunch acceptance + Maintainer approve 2241.
