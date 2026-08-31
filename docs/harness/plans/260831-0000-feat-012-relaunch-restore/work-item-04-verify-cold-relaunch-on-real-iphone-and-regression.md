---
work_item: 4
title: Verify cold relaunch on real iPhone and regression
status: pending
priority: P2
effort: TBD
dependencies:
  - 3
decision_dependencies: []
---

# Work Item 4: Verify cold relaunch on real iPhone and regression

## Tasks

- Chạy matrix cold relaunch: no pose, valid pose, corrupt pose; đủ tám nhóm settings; replace, clear, capture.
- Xác minh trên real iPhone: terminate từ app switcher, relaunch, mở Camera; lưu screenshot/log/accessibility evidence.
- Cập nhật verification ledger: chỉ chuyển `Unresolved` thành `Verified` khi có evidence; blocker phải ghi rõ.

## Scope and affected files

- Automated tests và device evidence cho FEAT-012; không sửa application code/test/source trong docs-only lane này.

## Success criteria

- Mỗi acceptance scenario có evidence hoặc trạng thái `Unresolved` kèm blocker cụ thể; không claim simulator thay cho real iPhone.
- Targeted checks/validation và regression evidence pass.

## Risks

- Simulator cold relaunch không chứng minh physical-device termination; thiếu real-iPhone evidence là blocker acceptance.

## Required evidence

- Test run log, real-iPhone screenshots/accessibility hoặc blocker note, verification ledger update, và `ckh workflow check` pass.
