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

Đóng authority gap giữa FEAT-003, FEAT-008, Harness plan 2241, và prototype Camera overlay trước khi sửa code.

## Goals

- Parity matrix: Try Pose, relaunch persistence, overlay controls vs prototype + harness WI.
- Xác nhận prerequisite plans 2240/1806 status với Maintainer.

## Non-goals

- Implementation code.
- Thay đổi API/data spec.

## Contracts

- FEAT-003: browse/detail/Try Pose prepare boundary.
- FEAT-008: camera guide lifecycle ownership (không redefine FEAT-003 catalogue).
- `PreparedPoseReference`: field semantics frozen.

## Tasks

1. Đọc Harness WI-01 và `design.md` trong plan 2241; liệt kê acceptance còn open.
2. So sánh `camera-pose-overlay.html` controls với `ui-ux-system.md` Camera section.
3. Ghi parity matrix vào plan 2241 hoặc phase notes (link-only, không duplicate spec).
4. Maintainer sign-off prerequisite closure.

## Acceptance

- [ ] Matrix có cột: Prototype | Harness | Current code | Gap.
- [ ] Mọi gap P0 có owner phase 2–4.
- [ ] Không claim runtime mới ngoài harness/spec.

## Verification

- `ckh validate --kind feature --workspace .` cho FEAT-003/008 (read-only).
- Reviewer checklist trong phase doc.

## Risks

- Unapproved FEAT → BLOCKED_NEEDS_LEAD.

## Rollout / Rollback

Docs-only phase; rollback = discard matrix draft.

## Gate

**Authority Closure Gate** — không bắt đầu Phase 2 cook nếu FEAT-003 governing acceptance cho relaunch chưa approved.
