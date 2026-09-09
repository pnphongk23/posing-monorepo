---
work_item: 5
title: Verify Saved integration and regression evidence
status: in_progress
priority: P2
effort: S
dependencies:
  - 4
decision_dependencies: []
---

# Work Item 5: Verify Saved integration and regression evidence

## Tasks

- Run backend route/store tests and mobile API/UI tests.
- Capture iOS evidence for signed-out/in, Save 200/idempotency, Unsave 204, invalid 404, list states/pagination, detail/Try Pose, 401, removal retention/message and offline no-queue.
- Regression-check Community browse/detail/Try Pose.
- Re-read all corrected docs and sweep Guest Try Pose contradiction, Album WI, FEAT-012 leakage and stale auth wording.

## Scope and affected files

Verification evidence and command results only; no product code expansion and no Album implementation.

## Success criteria

Every Feature requirement and direct scenario has Verified/Failed/Unresolved owner evidence; no unresolved claim is presented as ready.

## Risks

Credentials, device or removal fixtures may be unavailable; record exact Failed/Unresolved and keep approval pending.

## Required evidence

Backend/mobile outputs, iOS evidence paths, ckh status/check, ckh validate supported files, git diff --check and git diff --name-only base 53bf3b6..HEAD.

## Live verification evidence — 2026-09-04 (sustained dev/tunnel for mobile E2E)

**Ephemeral tunnel notice:** quick-tunnel URLs are temporary and change when cloudflared is restarted. The active dev tunnel for mobile TestFlight/dev E2E is `https://coated-text-regime-crm.trycloudflare.com` (replaces the prior `calling-supposed-salary-represented` URL from the earlier backend lane refresh).

The local dev process runs as `tsx watch src/index.ts` on port 3000 (`PORT=3000`, local Postgres at `localhost:5433`). Local-only `.env` `BACKEND_PUBLIC_URL` matches the active tunnel URL and is gitignored; no secret values are recorded or committed. Both the tsx watch process and cloudflared tunnel are kept alive for mobile testing.

## Mobile regression gate — 2026-09-04

`./gradlew :composeApp:allTests` completed successfully with **217 tests, 0 failures, 0 errors, 0 skipped**. The count is intentional: five obsolete fetch-only tests were deleted with the orphaned community-detail fetch path; the two focused FEAT-013 regressions remain and pass. No placeholder tests were added and the deleted fetch behavior was not restored.

The focused regressions are `signedOutSaveCanBeRequestedAgainAfterDismissal` and `projectedCommunityPoseLoadsWithoutDetailFetch` in `PoseDetailViewModelTest`.

| Observation | Result | Boundary |
| --- | --- | --- |
| Local and tunnel `/api/health` | HTTP 200; body `{"status":"ok","version":"1.0.0"}` | Live HTTP observation |
| Tunnel `/api/auth/google/start` | HTTP 302; redirect to Supabase `/auth/v1/authorize`, `provider=google`, fixed tunnel `redirect_to=https://coated-text-regime-crm.trycloudflare.com/api/auth/google/callback`, state present, `code_challenge_method=S256` | Live route/redirect observation; not full OAuth E2E |
| Supabase `/auth/v1/health` with anon key | HTTP 200; GoTrue v2.196.0 | Live health observation; key value withheld |
| Supabase JWKS | HTTP 200; one `ES256`/`EC` P-256 signing key, `kid=61218c19-fdb0-498d-b773-cebe34cbf90a`; configured id matches case-insensitively | Live public-key metadata; ES256, not RS256 |
| Direct Supabase authorize with Google and tunnel callback | HTTP 302; redirect host `accounts.google.com` | Live provider redirect acceptance only |
| Railway production `/api/health` (`pose-extract-server-production.up.railway.app`) | HTTP 200; body `{"status":"ok","version":"1.0.0"}` | Read-only production health probe; no deploy |
| Unauthenticated tunnel `/api/account/me` | HTTP 401, `{error:{code:UNAUTHORIZED,message:Unauthorized}}` | Live unauthenticated API observation |
| Unauthenticated tunnel `/api/me/saved?page=1&limit=10` | HTTP 401, `{error:{code:UNAUTHORIZED,message:Unauthorized}}` | Live unauthenticated API observation |
| Invalid callback/session/refresh requests | HTTP 401, `UNAUTHORIZED` envelope | Live negative-path observation |

The browser reached the Google Accounts sign-in page, but no Google credential or session was available. Therefore no callback, real token, verified-token Saved API call, live Account persistence, or live cross-account database-isolation evidence was completed. The 302 to Google proves only that the authorization step accepted the tunnel callback; it is not full E2E verification. No dashboard redirect request was needed.

## Evidence status matrix

| Area | Status | Evidence boundary and next validation |
| --- | --- | --- |
| Backend Account schema/store; Account JWT verifier with issuer, audience, expiry, key-id and ES256/RS256 JWKS support; Google-only state+PKCE fixed-redirect routes; opaque one-time handoff/session exchange; refresh; 401 envelope | Verified by mocked/contract tests and route evidence | Mocked tests are not live Supabase or live DB proof |
| Mobile `SecureTokenStorage`/`SessionBoundary`; iOS platform.Security Keychain; Bearer attachment; one refresh attempt then clear/`SignInRequired`; iOS `ASWebAuthenticationSession` callback parser/exchange; `aipose` URL registration/project wiring | Verified by compile/typecheck/simulator evidence where available | Android target compile is unavailable; full Xcode app build is blocked by environment contention; distinguish these from live runtime proof |
| Google credential/token callback and live JWT verification | Pending-validation | No credential was available; do not request or print one |
| Live Account persistence and cross-account DB isolation | Unresolved / Pending-validation | No verified token or live DB evidence |
| Saved API call with a verified token | Unresolved / Pending-validation | Only unauthenticated HTTP 401 was observed |
| Production `BACKEND_PUBLIC_URL` provisioning and full OAuth/token E2E | Pending-validation | Local value was set but is not committed or printed |

## FR-001–FR-010 evidence matrix

| Requirement | Status | Owner evidence and boundary |
| --- | --- | --- |
| FR-001: Google/Supabase session authority | Unresolved / Pending-validation | Backend route and mocked contract evidence; live Google credential, callback, token, and end-to-end session remain unverified |
| FR-002: signed-out gate and Guest cannot Try Pose | Partially Verified; live signed-out behavior Pending-validation | Unauthenticated API 401 evidence and mobile compile/simulator evidence; no authenticated mobile E2E |
| FR-003: published Save returns 200 and is idempotent | Unresolved / Pending-validation | Mocked/backend contract evidence only; no verified-token live Save call |
| FR-004: Unsave returns 204 and is idempotent | Unresolved / Pending-validation | No live authenticated Unsave evidence; runtime result remains unresolved |
| FR-005: invalid/missing/non-published Save returns 404 without creating an entry | Unresolved / Pending-validation | Contract/test evidence is not live Account/Saved DB proof |
| FR-006: removal retention/message and blocked Try Pose | Unresolved / Pending-validation | Removed published pose and live retention/message behavior were not exercised with a verified token |
| FR-007: 401 isolation and refresh/clear session | Partially Verified; live refresh/isolation Pending-validation | Live unauthenticated 401 envelope and invalid refresh 401 observed; live token refresh and cross-account DB isolation remain unverified |
| FR-008: list states and pagination | Unresolved / Pending-validation | Only unauthenticated Saved request was observed; no verified-token list response |
| FR-009: stale read/no queued mutation and detail/Try Pose | Unresolved / Pending-validation | Offline mutation and authenticated stale/detail behavior lack live evidence; compile/mock evidence is not runtime proof |
| FR-010: Albums future boundary | Verified as policy/non-goal | No Albums implementation or route is claimed; policy evidence only |

## Direct scenario evidence matrix

| Direct scenario | Status | Owner evidence and boundary |
| --- | --- | --- |
| Signed-in Save | Unresolved / Pending-validation | No Google credential, real session, or verified-token Saved call was available; mocked route tests are not live proof |
| Removed published pose | Unresolved / Pending-validation | No authenticated removal/retention/message/Try Pose flow completed |
| Invalid session | Partially Verified; live authenticated coverage Pending-validation | Live invalid callback/session/refresh requests returned HTTP 401 with the existing envelope; cross-account isolation remains unverified |
| Offline mutation | Unresolved / Pending-validation | No live device/offline mutation evidence; any mocked/compile evidence does not prove runtime no-queue behavior |

## Accepted review blockers and required risks

The following remain `Pending`/`Required` and are not shipped claims: live callback/token exchange, verified-token Saved calls, live Account persistence and database isolation; `PendingAuthStore` is in-process and requires multi-instance deployment validation; configured/default JWT key-id release configuration requires validation; Google-only provider enforcement lacks dashboard/claim evidence; production `BACKEND_PUBLIC_URL` provisioning is unresolved; credential rotation remains pending. No remediation, SDK, environment value, secret, or runtime success is inferred here.

WI-03 and WI-04 are `completed`; WI-05 remains `in_progress`. This evidence does not mark WI-05 complete or make the plan ready.
