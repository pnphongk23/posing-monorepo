# App Store Publish — Asset & Metadata Package

> **Lane:** `app-store-publish-prep` (coordinator: Bàng Thống)
> **Status:** DRAFT — chờ PO duyệt. Không submit, không upload ASC/TestFlight, không archive.
> **Date:** 2026-08-26 · **Baseline:** HEAD `49a2eb3` (working tree dirty — M1-M5 + FEAT-010, **staged=0**)
> **Build đích:** Snap Pose 1.0 (CFBundleVersion **6**, TestFlight `VALID_BINARY`)

Bộ hồ sơ sẵn sàng để publish lên App Store. Toàn bộ nội dung copy phải được
PO-Đại Vương duyệt trước khi bất kỳ lane nào điền vào App Store Connect.

## Các file trong package

| File | Nội dung | Trạng thái |
| --- | --- | --- |
| [app-store-metadata.md](./app-store-metadata.md) | Name / subtitle / description EN / keywords / what's-new / category + bản VI kèm theo | DRAFT — PO duyệt |
| [privacy-support.md](./privacy-support.md) | Nháp Privacy Policy (camera, Firebase, extract server; subscription PENDING) + App Privacy questionnaire + Support URL | DRAFT — PO cấp URL/email |
| [screenshots-runbook.md](./screenshots-runbook.md) | Kích thước/res, nguồn chụp, danh sách màn hình, điều kiện đẹp, checklist (KHÔNG tự chụp) | Runbook — executor/UCP thực hiện |
| [app-icon-check.md](./app-icon-check.md) | Verify icon 1024 (kích thước, no-alpha) — đã chạy, PASS kỹ thuật; QA thị giác chờ visual review | VERIFIED (kỹ thuật) |
| [app-store-checklist.md](./app-store-checklist.md) | Checklist toàn bộ hạng mục ASC cho submission + runbook thứ tự + mục PO phải cấp | DRAFT — PO điền phần còn thiếu |

## Nguyên tắc phạm vi (bắt buộc)

1. **Chuẩn bị, không hành động publish**: không submit ASC, không upload build,
   không archive, không chạy TestFlight, không chạm mobile code.
2. **Copy phải đúng app thật**: không hứa tính năng chưa ship (live overlay
   camera, UGC community, paywall/IAP của FEAT-011 — xem guardrails trong
   `app-store-metadata.md`).
3. **Chưa commit**: staged=0 giữ nguyên; chỉ tạo file docs mới trong thư mục này.

## Quyết định đã chốt trong package này (chờ PO xác nhận)

- Thư mục: `docs/app-store-publish/` (bộ asset publish, không phải kế hoạch thực thi
  nên không đặt dưới `docs/harness/plans/`).
- Ngôn ngữ phát hành: **EN chính** (đề xuất), VI cho giai đoạn sau — PO chốt.
- Category đề xuất: **Lifestyle** (primary) + **Photo & Video** (secondary) — PO chốt.
- Support URL / Privacy URL / Support email: **PO cấp URL + email** (placeholder trong docs).
