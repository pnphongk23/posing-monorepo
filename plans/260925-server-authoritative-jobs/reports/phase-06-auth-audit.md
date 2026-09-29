# Phase 6 — Account A Supabase auth audit

**Result:** Account A exists and is enabled in the Supabase project used by the deployed `pose-extract-server`, but the supplied credential is still rejected by that project's auth endpoint. A same-email account was also created in a different Supabase project. No credential or account settings were changed.

## Project mapping

- The deployed Railway service's `SUPABASE_URL` points to project ref `ugrhcbdlidfxkqewzuut`, shown in Supabase as `ai-pose-prod` / `main PRODUCTION`.
- The initially open `ai-pose` project is a different ref: `jqvqsxzcbstscvkhizkw`, also `main PRODUCTION`.
- Auth Users shows a same-email account in both projects. Supabase accounts and password hashes are project-local; the identity in one project does not share credentials with the other.

## Target-project account

In `ai-pose-prod`, Account A was created 2026-09-27 07:36 GMT+7, confirmed at 07:38, enabled, not banned, and last signed in at 07:40. User-scoped Auth Logs show successful `/token` responses (HTTP 200) at 07:38:23, 07:40:35, and 07:40:50.

The separate Account A record in `ai-pose` was created and confirmed at 07:54 and has no recorded sign-in. The corrected Maestro attempt occurred later and still received the generic invalid-credentials response.

Railway Network Logs show `/api/auth/email/signin` returning 401 during the later test window, including rows at 08:07:42, 08:09:58, 08:10:10, and 08:10:16. These are service-wide rows; the audit did not inspect request bodies and cannot attribute all of them to one test invocation. This does not establish an app retry or additional Maestro run.

## Client path

`mobile/iosApp/iosApp/Features/Support/SignIn.swift` binds both the visible `TextField` and `SecureField` to `model.password`; `submit()` sends that model value. The flow enters the password in Show mode, then hides it before submitting. The view is re-identified on Show/Hide changes. Source structure alone cannot prove whether the runtime binding survived the toggle; this audit does not claim that it did.

## Boundary and next action

This was a read-only Supabase/Railway audit. No password reset, account change, Supabase mutation, deployment, or further sign-in attempt occurred. Confirm which project's Account A credential should be used. If the correct target-project password is unknown, the user must reset/set it in `ai-pose-prod` and confirm when ready; do not send the password through chat. Then run one controlled E2E attempt.
