---
work_item: 2
title: Persist and restore existing pose plus eight camera settings
status: pending
priority: P2
effort: TBD
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 2: Persist and restore existing pose plus eight camera settings

## Tasks

- Dùng persistence layer hiện có để ghi snapshot single-device, có version/atomicity theo pattern đã có.
- Persist/restore pose identity hợp lệ và đúng tám nhóm settings; settings phải độc lập với pose.
- Rehydrate `PreparedPoseReference` khi locator hợp lệ; pose missing/corrupt thì clear pose portion và fallback settings, không crash.

## Scope and affected files

- Chỉ persistence implementation paths được WI-01 xác nhận và các consumer hiện có; `PreparedPoseReference` vẫn read-only transport.

## Success criteria

- Tests chứng minh round-trip đủ tám nhóm settings, pose optional, corrupt pose giữ settings, corrupt snapshot fallback an toàn.
- Không có runtime type mới thay `PreparedPoseReference`; không có dependency mới.

## Risks

- Partial write có thể làm pose locator không còn resolve được; atomic write và validation phải ngăn broken overlay.

## Required evidence

- Test names/paths, persistence path evidence, schema/version note trong `design.md` hoặc WI body, và targeted validation pass.
