---
work_item: 1
title: Freeze restore contract and state matrix
status: pending
priority: P2
effort: TBD
dependencies: []
decision_dependencies: []
---

# Work Item 1: Freeze restore contract and state matrix

## Tasks

- Đối chiếu FR/BR/NFR của FEAT-012 với baseline source và chốt state matrix trong `design.md`.
- Xác định chính xác tám nhóm settings, pose identity/locator, default khi corrupt, và các transient field bị loại trừ.
- Ghi rõ `PreparedPoseReference` là transport; không tạo `ActivePoseReference`; replace/clear không đổi ownership.

## Scope and affected files

- Chỉ FEAT-012, `plan.md`, `design.md`, và evidence references; không sửa application code/test/source.

## Success criteria

- Mỗi FR/BR/NFR của FEAT-012 có owner Work Item và matrix không còn assumption mơ hồ.
- Exact evidence paths/symbols được ghi; WI-02/03 có thể execute mà không tự mở rộng scope.

## Risks

- Nhầm overlay transport với durable state sẽ tạo hai source of truth.

## Required evidence

- Bảng state matrix trong `design.md`, coverage map trong `plan.md`, và `ckh validate`/`workflow check` pass.
