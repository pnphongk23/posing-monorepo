# App Review Information — posing (demo account & review notes)

Hồ sơ điền vào App Store Connect (ASC), mục **App Review Information** (Guideline 2.1 — Demo Account & Review Notes).

---

## 0. Yêu cầu Guideline 2.1 (App Review Information)

App có tính năng đăng nhập/tài khoản và mua in-app purchases (IAP/subscriptions) bắt buộc phải cung cấp tài khoản demo hoạt động được để Apple Reviewer kiểm tra toàn bộ luồng.

---

## 1. Vì sao Apple bắt account này (bằng chứng từ code)

| Bằng chứng | Vị trí |
| --- | --- |
| Login Google OAuth qua `ASWebAuthenticationSession` | `mobile/iosApp/iosApp/OAuthHandoff.swift:92-130` |
| Sign-in hỗ trợ Apple, Google OAuth và Email/password | `mobile/iosApp/iosApp/Features/Support/SignIn.swift`, `AppleSignIn.swift` |
| Route email/password hỗ trợ credential demo account | `web/services/pose-extract-server/src/routes/accountAuthRoutes.ts:142` |
| Paywall yêu cầu đăng nhập trước khi mua | `mobile/iosApp/iosApp/Features/Support/PaywallModel.swift:128-135` → `.signInRequired` |
| Gate hiển thị promo/sign-in: saved poses, Try Pose, Account, Premium | `Features/Support/SupportScreens.swift:99, 213, 284-290`, `Features/Gallery/GalleryFeature.swift:285`, `Features/Poses/PosesFeature.swift:393` |

Điểm tích cực để ghi vào Notes: **login không bắt buộc** để chạy luồng chính
(browse pose, camera, gallery local đều chạy ẩn danh). Nhưng luồng **mua Premium**
thì bắt buộc → reviewer vẫn cần credential.

---

## 2. Giá trị cần điền trong ASC

| Field (App Review Information) | Giá trị |
| --- | --- |
| Sign-in required | **Yes** |
| Demo account → Username | email tài khoản review (xem §3) |
| Demo account → Password | mật khẩu của tài khoản đó |
| Contact → First/Last name, Phone, Email | hợp lệ, trả lời được trong 24-48h |
| Notes | dán block §4 (EN) |

> **Vì sao `Yes` chứ không phải `No`:** app có subscription mà paywall buộc đăng nhập.
> Khai `No` sẽ khiến reviewer không test được purchase/renewal/restore → dễ bị hỏi lại
> hoặc reject lần nữa. Khai `Yes` + credential là đường ngắn nhất.

---

## 3. Supabase demo account (App Review)

| Fact | Value |
|---|---|
| Email | `jamenguyen27021996+appreview@gmail.com` |
| User UID | `8e872615-2a9b-426c-8842-2e21cec96f2b` |
| Authentication | Supabase email/password |
| Project name | `ai-pose-prod` |
| Project ref | `ugrhcbdlidfxkqewzuut` |
| Project URL | `https://ugrhcbdlidfxkqewzuut.supabase.co` |
| Auto Confirm User | ON at creation |
| Dashboard status | Confirmed |
| Confirmed at | 15 Sep, 2026 07:55 |
| Sign-in credential check | Supabase token exchange HTTP 200, 2026-09-15 |
| Recorded date | 2026-09-15 |

---

## 4. Review Notes (EN) — dán nguyên block vào ASC

```
Thank you for reviewing posing.

SIGN-IN
In App Review Information, "Sign-in required" is "Yes": an account is required for the
account-bound features below. Browsing the pose library, the camera and the on-device
gallery all work without an account.

Please use the demo account listed above (email + password). It is a normal app
account with no two-factor verification, so no OTP is required.

How to reach the sign-in surface:
- Premium gate (fastest): open the "Poses" tab and tap the crown icon at the top
  right, or go to Settings > Premium, then tap "Unlock Premium".
- Account screen: open the "Account" screen and follow the sign-in prompt there.
On the sign-in screen, tap "Sign in with email" to open the email/password sheet and
enter the demo email and password. "Continue with Google" is also offered as an
alternative sign-in method; sign-in is required because a purchase is tied to the
signed-in account.

WHAT TO TEST
1. Sign in with the demo account above.
2. The paywall loads the two auto-renewable plans (Monthly, Annual) from StoreKit.
3. Select a plan and tap "Continue with <plan>" to run the purchase flow with your
   sandbox tester account.
4. "Restore purchases" is available in the paywall footer, next to the Terms and
   Privacy links.

PREMIUM SCOPE
Premium unlocks the paid pose workflow: using a community pose as a camera guide
("Use this pose" / Try Pose) and the capture flow it opens. Every other screen —
pose library, search, pose detail, gallery browsing — is free and does not require
a subscription.

SUBSCRIPTIONS
Premium offers two auto-renewable subscriptions: Monthly and Annual. Payment is
charged to the Apple ID at confirmation of purchase. The subscription renews
automatically for the same period unless cancelled at least 24 hours before the end
of the current period. It can be managed or cancelled in App Store account
settings. No free trial or introductory offer is configured.

LEGAL
Terms of Use (EULA): https://sites.google.com/view/posingapp/terms-of-service
Privacy Policy: https://sites.google.com/view/posingapp/privacy-policy
The app's Terms and Privacy entry points open the same URLs.

CAMERA / PHOTOS
Camera and photo-library access are requested only when the reviewer uses the
camera or imports a photo. The app never requires photo access to launch.
```

---

## 5. Phương án B — nếu không cấp demo account

Khai `Sign-in required = No` + Notes giải thích login chỉ gate save/purchase, kèm
hướng dẫn từng bước. **Rủi ro đã biết:** reviewer không test được subscription
(3.1.2 + 2.1 dễ bị hỏi lại). Khuyến nghị luôn cung cấp demo account (Phương án A).

---

## 6. Đường email/password — đã implement, **chưa deploy**

Route email/password **đã được implement** trong working tree (chưa deploy lên production):

| Phần | Trạng thái | Vị trí |
| --- | --- | --- |
| Backend `POST /api/auth/email/signin` (`grant_type=password` + `apikey`, snake→camel) | Implemented, chưa deploy | `web/services/pose-extract-server/src/routes/accountAuthRoutes.ts:142` |
| Rate limit `ip+sha256(email)` cho riêng route signin | Implemented, chưa deploy | `web/services/pose-extract-server/src/middleware/authRateLimit.ts` |
| Route dùng `SUPABASE_ANON_KEY` + `SUPABASE_JWT_KEY_ID` (không service-role) | Implemented, chưa deploy | `web/services/pose-extract-server/src/index.ts:47` |
| iOS: link "Sign in with email" + sheet email/password | Implemented, chưa submit build | `mobile/iosApp/iosApp/Features/Support/SignIn.swift` |

**Chưa deploy:** production trả `404` cho `POST https://pose-extract-server-production.up.railway.app/api/auth/email/signin` (build Railway đang chạy cũ hơn thay đổi này).

**Rủi ro còn lại:**
- Reviewer chỉ sign-in được bằng email/password nếu **cả hai** đúng: build nộp Apple có form email, và backend production đã deploy route. Thiếu một trong hai thì demo account vô dụng.
- Route mở thêm bề mặt auth (provider `email` trên Supabase) → cần rà privacy/ToS và rate limit trước khi deploy.
- Credential và trạng thái confirmed **không** còn là ẩn số: đã xác thực trực tiếp với Supabase (token exchange `HTTP 200`, 2026-09-15). Rủi ro duy nhất còn lại là phụ thuộc deploy/build.
- Phương án backdoor env-gated `POST /api/auth/review` **không** được chọn.

---

## 7. Checklist trước khi bấm Resubmit

- [ ] ASC → App Review Information: **Sign-in required = Yes**.
- [ ] Username/password demo đã điền, **đúng** account trong §3 (credential đã xác thực trực tiếp với Supabase: token exchange `HTTP 200`, 2026-09-15).
- [ ] Account demo tạo bằng **Supabase → Authentication → Users → Add user**, **Auto Confirm User = ON**, **không 2FA** (không phone, không recovery email).
- [ ] Backend production đã deploy route `POST /api/auth/email/signin` (hiện trả `404`).
- [ ] **Build nộp Apple phải chứa form email/password** (đảm bảo build có đường sign-in mà Notes mô tả).
- [x] Posing Terms and Privacy pages are published (https://sites.google.com/view/posingapp/) and return 200.
- [ ] Verify the inserted posingapp URLs still return 200 and verify app entry points resolve to these same Posing URLs before pasting Notes.
- [ ] Description contains verified Posing URLs after `Terms of Use (EULA):` and `Privacy Policy:` (see `app-store-metadata.md` §9).
- [ ] Contact info của reviewer là người trả lời được trong 24-48h.
- [ ] Sau khi Apple duyệt: **rotate hoặc lock** credential demo (không dùng account này cho việc khác).

**Chưa verify (chờ backend deploy):** sign-in từ thiết bị/mạng mới, và luồng **Restore purchases**. Cả hai chỉ chạy được sau khi route được deploy và build có form email được cài.
