# Privacy & UGC Compliance Guide

> **Last updated:** 2026-05-10  
> **Status:** Pre-release checklist — implement before opening Community features to public users.

---

## 1. Tại sao cần quan tâm?

App Posing cho phép user upload ảnh chứa **khuôn mặt người thật** để extract pose. Theo cả luật Việt Nam lẫn yêu cầu Apple App Store, ảnh mặt người được phân loại là **dữ liệu cá nhân nhạy cảm (sensitive personal data)**. Xử lý sai có thể dẫn tới:

- App bị reject/remove khỏi App Store
- Vi phạm Luật Bảo vệ Dữ liệu cá nhân Việt Nam (phạt hành chính + hình sự)
- Kiện tụng từ người bị chụp ảnh mà không đồng ý

---

## 2. Luật áp dụng

### 2.1 Việt Nam — PDPD & PDP Law

| Văn bản | Hiệu lực | Ghi chú |
|---|---|---|
| Nghị định 13/2023/NĐ-CP (PDPD) | 01/07/2023 | Nghị định đầu tiên về bảo vệ dữ liệu cá nhân |
| Luật 91/2025/QH15 (PDP Law) | 01/01/2026 | Luật chính thức, thay thế/bổ sung PDPD |

**Điểm quan trọng:**

- **Ảnh mặt = Biometric = Sensitive Data**: Cần consent rõ ràng, cụ thể trước khi thu thập.
- **Không có "Legitimate Interest"**: Khác GDPR (EU), luật VN **không cho phép** xử lý dữ liệu dựa trên "lợi ích hợp pháp". **Consent là bắt buộc.**
- **Cấm mua bán dữ liệu cá nhân**: Không được bán/chia sẻ ảnh user cho bên thứ ba vì mục đích thương mại.
- **Consent hợp lệ phải bao gồm**: Loại dữ liệu, mục đích xử lý, ai xử lý, thời gian lưu, quyền xóa/rút consent.
- **Extra-territorial**: Luật áp dụng cho cả tổ chức nước ngoài nếu xử lý dữ liệu người Việt Nam.

### 2.2 Apple App Store — UGC Requirements

Apple **bắt buộc** các app có UGC phải đáp ứng đủ 4 điều kiện:

1. ✅ **Terms & Conditions**: User phải đồng ý T&C trước khi upload
2. ✅ **Content Filter**: Có cơ chế lọc nội dung không phù hợp (NSFW, bạo lực, v.v.)
3. ✅ **Report Mechanism**: User có thể report nội dung vi phạm, app phải phản hồi trong **24 giờ**
4. ✅ **Block Mechanism**: User có thể block user khác

> **Nếu thiếu bất kỳ điều nào → App sẽ bị reject khi review.**

---

## 3. Phân loại rủi ro theo giai đoạn

### Giai đoạn 1: Admin-only upload (Hiện tại) — ✅ Rủi ro thấp

- Admin tự kiểm soát nội dung upload
- Không có UGC từ user
- Chỉ cần: Privacy Policy cơ bản trên website/app

### Giai đoạn 2: Community (User upload ảnh) — ⚠️ Rủi ro cao

- User upload ảnh chứa mặt người khác (có thể vi phạm bản quyền/quyền hình ảnh)
- Ảnh được hiển thị công khai cho toàn bộ community
- **Cần triển khai đầy đủ 3 tấm khiên pháp lý (xem Mục 4)**

### Giai đoạn 3: AI-generated samples — ✅ Rủi ro thấp

- Ảnh do AI render → không chứa dữ liệu cá nhân thật
- Vẫn cần ghi rõ trong T&C rằng ảnh mẫu là AI-generated

---

## 4. Checklist triển khai trước khi release Community

### 4.1 Terms of Service (ToS) — UGC Clause

User phải tick checkbox xác nhận trước khi upload:

```
☐ Tôi xác nhận rằng:
  • Tôi là chủ sở hữu hoặc có quyền hợp pháp sử dụng ảnh này
  • Tôi đồng ý cho Posing hiển thị ảnh này trong Community
  • Ảnh không chứa nội dung bất hợp pháp, khiêu dâm, hoặc bạo lực
  • Nếu ảnh chứa khuôn mặt người khác, tôi đã có sự đồng ý của họ
```

**Vị trí hiển thị:**
- Màn hình đăng ký tài khoản (lần đầu)
- Màn hình upload ảnh lên Community (mỗi lần upload)

### 4.2 Report & Takedown Mechanism

| Yêu cầu | Cách triển khai |
|---|---|
| Nút Report | Trên mỗi Pose Card trong Community, thêm icon 🚩 "Report" |
| Report form | Chọn lý do: "Ảnh chứa mặt tôi không có đồng ý" / "Vi phạm bản quyền" / "Nội dung không phù hợp" |
| SLA phản hồi | Takedown trong **24 giờ** kể từ khi nhận report |
| Admin dashboard | Thêm tab "Reports" để admin review và xử lý |

### 4.3 Privacy Policy

Cần tạo trang Privacy Policy (hosted trên web) bao gồm:

```markdown
## Dữ liệu chúng tôi thu thập
- Ảnh bạn upload (bao gồm ảnh chứa khuôn mặt)
- Metadata: tên pose, tags, body parts

## Mục đích sử dụng
- Extract pose skeleton từ ảnh
- Hiển thị ảnh trong Community (nếu bạn chọn chia sẻ)

## Ai có quyền truy cập
- Đội ngũ Posing (vận hành hệ thống)
- Người dùng khác trong Community (nếu ảnh được publish)

## Thời gian lưu trữ
- Ảnh được lưu trữ cho đến khi bạn xóa hoặc yêu cầu xóa

## Quyền của bạn
- Xóa ảnh bất kỳ lúc nào
- Yêu cầu xóa toàn bộ dữ liệu cá nhân
- Rút lại consent (dẫn tới xóa ảnh khỏi Community)
- Report ảnh vi phạm quyền hình ảnh của bạn

## Liên hệ
- Email: [support email]
```

### 4.4 Tính năng "Delete My Data"

- User phải có khả năng **xóa tất cả ảnh** đã upload
- Khi user xóa tài khoản → xóa toàn bộ ảnh trên R2 + record trong DB
- **Bắt buộc** theo cả PDPD lẫn Apple App Store guidelines

---

## 5. Quyết định kỹ thuật: Có cần auto-blur mặt không?

### Kết luận: KHÔNG cần ở giai đoạn hiện tại

| Lý do | Giải thích |
|---|---|
| Giai đoạn Admin-only | Admin tự kiểm soát nội dung, không có rủi ro từ user |
| Chi phí kỹ thuật cao | Cần face detection API (tốn server cost, latency) |
| Giảm chất lượng UX | Ảnh bị blur mặt trông không tự nhiên, giảm "vibe" |
| ToS + Report đủ bảo vệ | Đẩy trách nhiệm pháp lý cho uploader (industry standard) |

### Khi nào CẦN xem xét lại:

- App có >10K users active trong Community
- Nhận được >3 DMCA/takedown requests
- Mở rộng sang thị trường EU (GDPR strict hơn)
- Apple/Google thay đổi policy về face data

---

## 6. Tham khảo

- [Nghị định 13/2023/NĐ-CP (PDPD)](https://thuvienphapluat.vn/van-ban/Cong-nghe-thong-tin/Nghi-dinh-13-2023-ND-CP-bao-ve-du-lieu-ca-nhan-405714.aspx)
- [Luật 91/2025/QH15 về Bảo vệ Dữ liệu Cá nhân](https://thuvienphapluat.vn)
- [Apple App Store Review Guidelines — 1.2 User-Generated Content](https://developer.apple.com/app-store/review/guidelines/#user-generated-content)
- [Vietnam Privacy Handbook 2025 (PDF)](https://privacycompliance.vn)
- [Baker McKenzie — Vietnam PDP Law Analysis](https://connectontech.bakermckenzie.com/vietnam-decoding-vietnams-pdp-law-gdpr-inspired-rules-with-local-twists/)
