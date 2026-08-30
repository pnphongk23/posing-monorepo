# Privacy Policy (nháp) & Support URL — Snap Pose 1.0

> **Lane:** `app-store-publish-prep` · **Status:** DRAFT — PO cấp URL hosting + support email; luật sư/PO rà soát trước khi publish
> **Baseline:** HEAD `49a2eb3`, staged=0 · **Đối tượng nháp:** build 1.0 (6)

Privacy policy là **điều kiện bắt buộc** của ASC vì app: (1) dùng **camera**,
(2) có **Firebase Analytics/Crashlytics/Remote Config**, (3) gửi ảnh lên
**pose-extraction server** khi người dùng tạo pose guide, (4) sắp có
**subscription (RevenueCat)** — mục 6 đánh dấu **PENDING** để PO quyết khi deploy FEAT-011.

---

## 1. Yêu cầu ASC trước khi submit

| Hạng mục | Trạng thái | Ai cung cấp |
| --- | --- | --- |
| Privacy Policy URL (https, công khai, không cần tải app để xem) | **PO cấp URL** (hosting) | PO |
| Support URL (https, công khai) | **PO cấp URL** | PO |
| Support email (hiển thị trong ASC + policy) | **PO cấp email** | PO |
| Hoàn tất bảng App Privacy (Privacy Nutrition Labels) | PO/developer điền theo mục 4 | PO |

**Đề xuất hosting (nếu PO chưa có):**
- Nhanh & miễn phí: GitHub Pages từ repo này (branch `gh-pages` hoặc thư mục `privacy/`)
  — tạo trang tĩnh `privacy-policy.html` + mục Support.
- Lâu dài: mua domain (vd. `camerapose.app` hoặc `aipose.app`) đặt trang sản phẩm
  chứa Privacy Policy + Support — PO quyết (ngoài phạm vi lane này, chỉ ghi nhận).

---

## 2. Nháp Privacy Policy (EN — bản gốc nộp ASC)

> Copy-paste sẵn, đúng hành vi app hiện tại (build 1.0/4). **Không được** thêm claim
> UGC/subscription khi chưa ship. PO bổ sung tên công ty, địa chỉ, email, ngày hiệu lực.

```
SNAP POSE — PRIVACY POLICY

Effective date: [PO to fill] · Last updated: [PO to fill]

1. WHO WE ARE
Snap Pose ("we", "our") is a pose-reference camera app for iPhone ("the App").
Contact: [support email] · [company name & address, if applicable].

2. DATA WE COLLECT

a) Photos and videos you create
The App uses your camera only when you capture a photo inside the App, and your
photo library only when you pick an existing image. Captured and picked images
are stored on your device in your personal gallery. When you create a "pose guide",
the selected image is sent to our pose-extraction service so its AI provider can
detect body joints and return a skeleton guide. The skeleton result is kept in the
App; your original image is used only to produce that guide.

b) Analytics and diagnostics
With your consent where required by law, the App uses Google Firebase:
- Firebase Analytics — app usage events (e.g. app start, endpoint resolution)
  to understand and improve the product;
- Firebase Crashlytics — crash reports and device/diagnostic information
  (model, OS version, memory) to fix bugs;
- Firebase Remote Config — runtime configuration (e.g. the backend endpoint).
These services run best-effort and only when a valid Firebase configuration is
present in the App. They are governed by Google's privacy policy.

c) Account and payment
The App does not require an account today. No name, email, or contact details are
collected in this version. (Subscriptions — if and when introduced — are handled by
Apple's In-App Purchase; see section 6.)

3. HOW WE USE DATA
We use data only to: (i) deliver the pose guide and gallery features you request,
(ii) keep the App reliable (crash and error monitoring), and (iii) improve the App.

4. SHARING — WE DO NOT SELL DATA
We do not sell or rent your personal data. We may share data only with service
providers that process it on our behalf to run the App (Google Firebase for
monitoring/configuration; our AI extraction provider for pose detection), and only
to the extent needed for those purposes. We do not share photos for advertising.

5. STORAGE AND RETENTION
Your captures live on your device and stay there until you delete them. Pose guides
and related data are kept while needed to provide the feature. Analytics/crash data
is retained per Google's data-retention policies. We apply reasonable technical and
organizational safeguards, including TLS in transit.

6. SUBSCRIPTIONS (PENDING — not yet launched)
Snap Pose plans to add a paid "premium" subscription via RevenueCat on top of Apple's
In-App Purchase. When available: payments are processed by Apple (StoreKit); we do
not see or store your payment card details. Subscriptions auto-renew until cancelled;
you can manage or cancel them in your App Store account settings, and restore
purchases in the App. Prices and terms are shown before purchase. [Content above
takes effect only when the subscription feature ships — currently not available.]

7. YOUR RIGHTS
Depending on your location (including Vietnam — Decree 13/2023/ND-CP and the
Personal Data Protection Law), you may request access, correction, deletion, or
withdrawal of consent for your data. Contact us at [support email]. You may also
delete photos from the App at any time.

8. CHILDREN
The App is not directed to children under 13 (or the minimum age in your country).
We do not knowingly collect personal data from children.

9. CHANGES TO THIS POLICY
We may update this policy and will post the new version at this URL with a new
effective date. Material changes will be notified in the App or by the updated date.

10. CONTACT
Questions or requests: [support email].
```

## 3. Tóm tắt VI (để PO nắm nhanh — không thay bản EN nộp ASC)

- **Camera/Ảnh:** chỉ chụp khi bạn bấm; ảnh lưu trên thiết bị; khi tạo pose guide, ảnh
  được gửi lên dịch vụ extract (và AI provider) chỉ để phát hiện khung xương.
- **Firebase:** Analytics + Crashlytics + Remote Config, best-effort, không bắt buộc.
- **Không bán dữ liệu**; chia sẻ chỉ với nhà xử lý (Firebase/Google, AI provider) theo nhu cầu vận hành.
- **Không tài khoản bắt buộc** ở v1.0.
- **Subscription: PENDING** — khi ship sẽ do Apple StoreKit xử lý thanh toán (qua
  RevenueCat), không lưu thẻ của bạn; đăng ký tự gia hạn, hủy/restore qua Store settings.
- **Quyền người dùng:** truy cập/sửa/xóa/út consent theo PDPD & PDP Law VN.
- **Trẻ em:** không nhắm dưới 13 tuổi; không thu thập có chủ đích.

## 4. Bảng App Privacy (Privacy Nutrition Labels) — đối chiếu hành vi thật

ASC hỏi "data collected" theo danh mục. Khuyến nghị khai (đúng practice hiện tại —
**không** khai IAP khi chưa ship):

| Danh mục ASC | Khai? | Loại | Mục đích | Liên kết danh tính |
| --- | --- | --- | --- | --- |
| Photos or Videos | Yes | Collected | App Functionality (pose guide/gallery) | Not linked |
| Identifiers — Device ID | Yes | Collected | Analytics (Firebase) | Not linked |
| Diagnostics — Crash Data | Yes | Collected | App Functionality (Crashlytics) | Not linked |
| Other — Usage Data (events) | Yes | Collected | Analytics | Not linked |
| Purchase History / IAP | No (chưa ship) | — | — | — |
| Tracking (advertising) | **No — "Data Used to Track You: No"** | — | — | — |

> Apple yêu cầu khai đúng sự thật — nếu sau này đổi hành vi (thêm IAP, thêm UGC)
> phải cập nhật lại bảng này + policy trước khi phát hành bản mới.

## 5. Support URL — đề xuất

| Lựa chọn | URL | Ghi chú |
| --- | --- | --- |
| Trang sản phẩm tương lai | `https://<tên-miền>/support` | PO mua domain (khuyến nghị dài hạn) |
| GitHub Pages tạm | trang tĩnh trong repo này | Nhanh, miễn phí; chứa email support |
| mailto (không hợp lệ cho ASC field) | ✗ | ASC yêu cầu **URL**, không phải email |

Support URL phải mở được trên web, không yêu cầu tải app.

---

## Việc PO cần cấp/duyệt (tóm tắt)

1. **Privacy Policy URL** (hosting + nội dung duyệt sau khi điền contact).
2. **Support URL** + **support email**.
3. Xác nhận bảng App Privacy (mục 4) — PO/US duyệt từng dòng trước khi điền ASC.
4. Quyết định khai công ty hay cá nhân phát hành (ảnh hưởng TAX/USD + contact info ASC).
