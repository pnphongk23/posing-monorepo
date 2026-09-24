# PLAN_FINAL — Email/password sign-in + demo account (App Review 2.1)

`appstore-unblock` · `auth-plan` · 260915 · Lead Tiêu Hà.

## 1. Approach

Supabase email/password behind our backend. `verifyJwt` (`middleware/accountAuth.ts:26-79`) accepts email sessions unchanged → `SessionBoundary`, `KeychainTokenStorage`, refresh (`APIClient.swift:88-104`), `/api/me/saved`, `linkAccount` (`SessionScopeCoordinator.swift:71`) untouched. Only the anon key (`config/env.ts:9`): no service-role, no migration.

Rejected: magic link; env-gated backdoor (`app-review-notes.md` §6); Google-only.

A = sign-in (blocking). B = sign-up + reset, deferred (mailer caps 2 emails/hour; needs SMTP).

## 2. Contract

`POST /api/auth/email/signin` `{email,password}` on the existing router (`app.ts:134`); 200 `{accessToken, refreshToken, account:{id,displayName,createdAt}}`, identical to `/session`/`/refresh` (`accountAuthRoutes.ts:107,128`).

Errors: `400 BAD_REQUEST` (zod, `savedRoutes.ts:35`); `401 INVALID_CREDENTIALS` (unknown email **and** wrong password, one message); `403 EMAIL_NOT_CONFIRMED`; `429 RATE_LIMITED`; `503 AUTH_PENDING_VALIDATION` (no anon key, `:22-24`).

Upstream `grant_type=password` + `apikey` (pattern `:118-128`), snake→camel. Anti-enumeration: one generic 401 — Supabase returns `invalid_credentials` for both (error-codes doc, #10724).

Rate limit: `authRateLimit.ts` cloned from `adminRateLimit.ts:1-70` — `ip+sha256(email)` 10/15 min, per-IP 30/15 min; mount on `/email/signin` only, never `/refresh` (401-burst retries would sign users out spuriously, `APIClient.swift:53-62`). Supabase's own limit is under-enforced (#41947).

Reset: Phase B route → always 200; Phase A rotates in-dashboard.

## 3. Config

Email provider on (default). Keep **Confirm email ON**; the demo user is created with **Auto Confirm User** (off ⇒ session, on ⇒ `session:null`). Optional `AUTH_RATE_LIMIT_*` (`env.ts:14-15`); no service-role.

⚠ `authReady` (`:45`) gates on Google-only `backendPublicUrl` (`env.ts:11`) — email needs its own guard `anonKey && accountStore && keyId`.

## 4. iOS

`APIClient.swift` `signInWithPassword` (mirror `:105-119`); `SignIn.swift` `EmailSignInModel` + form + "Sign in with email" under `ContinueWithGoogleButton` (`:123-137`) + `AuthErrorCopy` in `ErrorCopy` (`:24-40`); `SupportScreens.swift` form in `signedOutCard` (sign-out `:80-88` unchanged); `PaywallModel.swift` call-site only (`:143-160`).

Copy: invalid → "Incorrect email or password."; unconfirmed → "Confirm your email address."; 429 → "Too many attempts."

## 5. Security

Supabase password policy; Phase A never sets one; never log passwords. Same verify, refresh, local-only logout (`SessionBoundary.swift:66-80`, `SessionScopeCoordinator.swift:79`), `linkAccount` re-link.

## 6. Deletion (5.1.1(v)) — DEFER

Sign-out only (`SupportScreens.swift:80-88`); `accountStore` has `upsert`/`getById` only (`:26-42`); FEAT-014 `:44/:143/:164` exclude it; no FK to `accounts` (`schema.sql:59-103`); Supabase deletion needs service-role (absent). Legal docs promise email-only deletion (`snap-pose-privacy-policy.md:84`) while `privacy-ugc-compliance.md:128-130` demands in-app purge.

Reason: separate risk class (privileged secret + irreversible endpoint); delays the 2.1 unblock. **R1 (accepted):** another 5.1.1(v) rejection. Owner: PO decides, backend implements. Trigger: that rejection or the next release. Sketch: `DELETE /api/account` → Admin delete user → purge `saved_entries`, `poses`, `media_assets`, R2 → `accounts`; iOS row after `savedPosesRow` (`:98`), typed confirm.

## 7. Demo account (owner: PO)

1. Supabase → Users → Add user `appreview@<domain>` + random password (password manager, never in repo) + **Auto Confirm User**.
2. No 2FA; no confirmation email.
3. Pre-submit on a fresh device/network: Poses → crown → **Sign in with email** → Restore purchases.
4. ASC: Sign-in required **Yes**; Username/Password as above; Notes = `app-review-notes.md` §4 leading with email.
5. Rotate/lock after approval. If blocked: check 401 vs 429, hand over Google, reply in Resolution Center; keep a spare.
6. Update `app-review-notes.md` §3/§4/§7 (`:110-122`), `app-store-checklist.md` A19, `privacy-support.md:67-68`.

## 8. AC / tests / risks / non-goals / ownership

**AC:** reviewer signs in without Google or email; identical 200 body on all three routes; the 6 tests (`accountAuthRoutes.test.ts:45-116`) pass; `SessionBoundary`/`KeychainTokenStorage`/`schema.sql` untouched.

**Tests:** snake→camel; 401/403/429; no `BACKEND_PUBLIC_URL`; unknown-email ≡ wrong-password; iOS `URLProtocol` stub asserts `saveCredentials` + one `.signedIn`.

**Risks:** R1 (§6); R2 provider disabled/demo user missing; R3 `authReady` reuse; R4 no visible sign-up; R5 credential leakage → rotate.

**Non-goals:** sign-up + reset, deletion, magic link, removing Google, RevenueCat products, migration, service-role.

**Ownership:** backend `accountAuthRoutes.ts`, `authRateLimit.ts`, `env.ts`, `app.ts`, tests · iOS `APIClient.swift`, `SignIn.swift`, `SupportScreens.swift`, `PaywallModel.swift` · docs `app-review-notes.md`, `app-store-checklist.md`, `privacy-support.md` · untouched: `SessionBoundary`, `KeychainTokenStorage`, `SessionCredentials`, `RevenueCatAdapter`, `schema.sql`.
