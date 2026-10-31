# Account: sign in, sign out, delete (FEAT-014)

Build-17 redesign (per `/tmp/gap/GAP-AND-OWNERSHIP.md`, page 10): Account gains **PROFILE** (email,
sign-in method) and **PREMIUM** (plan, renewal, Manage subscription) sections plus an in-list **Sign out**
row, an initials avatar with email, a row skeleton while loading, the F4 error state and a new **offline**
state. Today: identity is an SF glyph + "Signed in", no email, no PROFILE/PREMIUM, Sign out is a header
icon, an extra "Saved poses" row exists, and the screen still paints neo chrome.

Email sign-in (page 11) is in this group too: validation is one shared error card today, with no
per-field errors and no offline state.

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-ACC-001 | P1 | account switch on, signed out | 1. Launch with accounts on. 2. Open Settings. 3. Tap the Account row | Account screen shows the email sign-in entry | automated: TC-ACC-001-account-signed-out.yaml (**re-baseline**, R2) |
| TC-ACC-002 | P1 | Email sign-in available | Enter email and password, submit | Signed in; Account shows the identity | pending (needs test credentials; `e2e`-tagged flow) |
| TC-ACC-003 | P1 | Email sign-in | Wrong password | Inline error naming the failure; the typed email stays in the field so the user can retry | pending (needs test credentials) |
| TC-ACC-004 | P1 | Signed in | Sign out | Returns to signed-out state; Saved asks to sign in | pending (flow needs `account.signout`; transition unit-covered by `AccountSessionTests.testSignOutClearsCredentialsAndProjectsSignedOut`) |
| TC-ACC-005 | P1 | Signed in | Tap Delete account | The account deletion **web form** opens; afterwards the session is untouched and nothing was deleted in-app | manual (browser + server delete landing; prod-sim smoke S-02) |
| TC-ACC-006 | P1 | Sign in, relaunch | Kill and reopen | Still signed in | manual |
| TC-ACC-007 | P1 | account switch on, signed out | 1. Launch with accounts on. 2. Open Settings > Account. 3. Tap "Sign in with email" | Email, password fields and submit button visible | automated: TC-ACC-007-email-form.yaml (**re-baseline**, R2) |
| TC-ACC-008 | P1 | account switch off (launch arg) | 1. Launch with accounts off. 2. Open Settings | No Account entry, and nothing advertises a feature the flag switched off | automated: TC-ACC-008-accounts-off.yaml (committed version asserts the pre-redesign Privacy text; the re-baselined version is drafted and lands with the 1.1 (17) run) |
| TC-ACC-009 | P1 | account switch on, signed out | 1. Launch with accounts on. 2. Open Settings > Account | Apple button is visible and labelled "Sign in with Apple" | automated: TC-ACC-009-apple-button-label.yaml (**re-baseline**, R2) |
| TC-ACC-010 | P1 | Fresh install (never signed in), account switch on | 1. Launch with accounts on. 2. Open Settings > Account | Card copy does not imply a previous session (no "again") | automated: TC-ACC-010-fresh-install-copy.yaml (**re-baseline**, R2) |
| TC-ACC-011 | P1 | Signed in, slow account read | Open Account from the profile card | A row skeleton matching the real geometry stands in for the content (no spinner-only screen, no error, no signed-out flash) and resolves into the signed-in sections | pending (ids: `account.loading`, `account.avatar`, `account.name`, `account.email`) |
| TC-ACC-012 | P0 | Account read fails (e.g. 503) | Open Account | The F4 state: one 72 pt accent-tint circle, "Couldn't load your account", a body naming the failure, and "Try again"; retrying re-reads and recovers in place | pending (ids: `account.error`, `account.error.retry`; retry-after-failure unit-covered by `AccountSessionTests.testRetryReloadsAfterFailure`) |
| TC-ACC-013 | P0 | Signed in, device offline | Open Account | The offline state exists at all (it is missing today): a banner says cached details are being shown, the cached email and sign-in method still render, **Delete account is disabled with "Connect to the internet to delete"**, and Sign out stays available. An offline user is never led to believe a delete was attempted | pending (ids: `account.offline.banner`, `account.delete`, `account.delete.reason`, `account.signout`) |
| TC-ACC-014 | P1 | Signed in with a live entitlement | Read Account | Initials avatar, display name, email; **PROFILE** lists Email and Sign-in method; **PREMIUM** shows the plan with its renewal date and a **Manage subscription** row; the footnote states that deleting the account does not cancel the Apple subscription; the pre-redesign "Saved poses" row is gone (Saved lives on the hub) | pending (ids: `account.avatar`, `account.profile.email`, `account.profile.method`, `account.plan`, `account.manageSubscription`) |
| TC-ACC-015 | P1 | Signed in | Tap Sign out | Sign out is an in-list destructive row (not a header icon, not the primary pink action); afterwards the hub shows the signed-out card (TC-SET-006) and Saved asks to sign in; no account data remains on the device | pending (ids: `account.signout`, plus TC-SET-006 ids for the resulting hub) |
| TC-ACC-016 | P1 | Signed in | Delete account → in-app confirm dialog | — | **out of scope 1.1 (17)** (idea kept for later): the boards draw a confirm dialog + delete-error banner, but the product fact is that Delete account opens the web request form with no in-app confirmation — see TC-ACC-005. Not built, no flow |
| TC-ACC-017 | P1 | Signed in | Delete fails → inline delete error | — | **out of scope 1.1 (17)** (idea kept): same override as TC-ACC-016 |
| TC-ACC-018 | P1 | Signed in with a long display name and email | Read Account at large and AX3 text sizes | The email wraps inside its row instead of truncating or escaping the card; avatar initials stay aligned; no row overlaps its neighbour | pending (ids: `account.email`, `account.avatar`) — visual wrap check, real risk is truncation |
| TC-ACC-019 | P1 | Signed in, on Account | Press Back | Back returns to the hub with the profile card still showing the same identity (no flash to signed-out) and no dock of its own | pending (ids: `account.back`, `settings.accountCard`) |
| TC-ACC-020 | P1 | accounts flag off (launch arg) | Launch with accounts off, open Settings | No profile card, no sign-in card and no Account entry exist anywhere in the hub | pending (ids: `settings.accountCard`, `settings.signIn.card`; TC-ACC-008 covers today's `settings.account.row`) |
| TC-ACC-021 | P0 | Email sign-in sheet open, nothing typed | Tap Sign in | Nothing is sent; each empty field states its own problem in place — email `Enter a valid email address, like name@example.com`, password `Enter your password` — and the shared error region answers the tap with `Enter your email address and password.` The control stays tappable and the sheet stays open | pending (re-baselined flow drafted in `docs/qa/redesign-drafts/settings-account/`; promoted and committed only once it is green on 1.1 (17)) |
| TC-ACC-022 | P0 | Email sign-in sheet open | Type a malformed address (`maya@`), fill the password, submit; then correct the address | The malformed address is refused locally with `Enter a valid email address, like name@example.com` on the email field only (no password error, no request sent — the backend contract is `z.string().trim().email()`); correcting the address clears the message without leaving the sheet | pending (same promotion rule as TC-ACC-021) |
| TC-ACC-023 | P1 | Email sign-in sheet open | Fill a valid email, then a single-character password | The client accepts it: the password rule is presence only, because the endpoint accepts any non-empty password (`z.string().min(1)`) — a stricter client rule would refuse credentials the server honours. No `signin.password.error` appears; erasing the password brings `Enter your password` back | pending (same promotion rule as TC-ACC-021) |
| TC-ACC-024 | P1 | Email sign-in sheet open, request in flight | Submit and watch the control | The control reports progress ("Signing in…") and cannot be tapped twice; a second tap while in flight does not create a second request | pending (no deterministic in-flight hook: the submit label turns to "Signing in" only for the length of a real request; needs a `signin.submitting` id or an injectable delay) |
| TC-ACC-025 | P1 | Email sign-in sheet open, valid-format credentials that do not exist | Submit | The shared error region (`signin.error`) names the failure while both fields keep what was typed, so the user can retry without re-entering the email; the sheet does not close | pending (needs one real request to the auth endpoint with deliberately wrong credentials — no account is created; ask the lead before promoting) |
| TC-ACC-026 | P1 | Email sign-in sheet open, device offline | Open the sheet and read it | The offline banner `You're offline. Connect to sign in.` (`signin.offline`) is shown and the Sign in control is disabled — a tap cannot start a request that must fail. The typed values survive going back online | pending (needs a supported way to reach the offline state; an unreachable base URL is not the same thing) |
| TC-ACC-027 | P1 | Email sign-in sheet open | Toggle the password reveal control | The password is masked by default; the reveal control shows it and hides it again, and the field keeps its value | pending (`signin.password`, `signin.showPassword` — the toggle exists) |
| TC-ACC-028 | P1 | Signed in with a live subscription | Account → tap Manage subscription | The App Store subscription-management page opens (`https://apps.apple.com/account/subscriptions`) and the app leaves the foreground; returning shows Account unchanged. The URL itself must be pinned by a unit test, not by the flow | pending (id: `account.manageSubscription`; flow can only assert the app lost the foreground; request: `SupportDestinations` constant + `SupportDestinationsTests` case for the exact URL) |
| TC-ACC-029 | P2 | Email sign-in sheet open | Read the sheet for a password-reset path | — | **out of scope 1.1 (17)** (idea kept): the app has no password-reset path, so the board's "Forgot password?" link is not built; recording it here stops it being reported as a regression |

## Re-baseline when build 17 lands (existing green flows)

- **R1 — TC-ACC-008**: asserts `"Privacy"` is visible with accounts off; the Privacy group leaves the
  hub. Rewrite it to assert the absence of the profile card / Account entry instead.
- **R2 — TC-ACC-001, TC-ACC-007, TC-ACC-009, TC-ACC-010**: all enter Account through
  `settings.account.row`, which becomes the **profile card**, and the Account header identity changes
  from glyph + "Signed in" to avatar + name + email. Re-verify the id that opens Account, then the
  assertions inside.
- **R3 — `open-settings.yaml`** (shared subflow, my file): uses `poses.more → poses.menu.settings` while
  the board pushes Settings from the header **gear** (F8 also keeps a More-menu row). Whichever ships,
  one path may stop existing — re-verify before touching the flows that use it.
- **R4 — TC-SET-001 and TC-SET-002/003/004** (manual): see `settings.md` — Privacy group removed, About
  becomes a header+X sheet with Terms / Privacy / licences.

## Assumptions

- **A1 — Profile card is the Account entry**; the pre-redesign `settings.account.row` may or may not survive.
- **A2 — Delete account** is the web form only (product fact); boards 10-10/10-11 are not built.
- **A3 — Offline** keeps the cached identity readable: a cached read is not a failure and must not look
  like one, hence a separate case from TC-ACC-012.
- **A4 — Email sign-in validation** is now per-field (0632361): each field owns its message
  (`signin.email.error` / `signin.password.error`) and the shared region answers a submit tap that has
  nothing to send. The password rule is presence-only on purpose, because the endpoint accepts any
  non-empty password — TC-ACC-023 pins that, so a future "minimum 8 characters" client rule cannot
  silently refuse credentials the server honours.
- **A5 — Manage subscription** URL is `https://apps.apple.com/account/subscriptions`; the flow can only
  prove the app left the foreground, so the exact URL needs the unit test named in TC-ACC-028.

## Requests to Feature (build 17 ids — all unconfirmed)

Account: `account.back`, `account.title`, `account.avatar`, `account.name`, `account.email`,
`account.loading`, `account.error`, `account.error.retry`, `account.offline.banner`,
`account.profile.email`, `account.profile.method`, `account.plan`, `account.manageSubscription`,
`account.signout`, `account.delete`, `account.delete.reason`.
Email sign-in: `signin.error.email`, `signin.error.password`, `signin.submitting`, `signin.offline`
(`signin.emailEntry`, `signin.password`, `signin.submit`, `signin.error`, `signin.showPassword`,
`signin.apple`, `signin.email.error`, `signin.password.error`, `signin.offline` and `account.signin.apple` all exist
as of 0632361; **`signin.google` no longer exists** — the sheet dropped "Use Google instead", and no flow or
subflow referenced it).
Hub side used by these cases: `settings.accountCard`, `settings.signIn.card` (see `settings.md`).
Test-side: a `SupportDestinations` constant for the App Store subscriptions URL plus a
`SupportDestinationsTests` assertion on the exact string (TC-ACC-028 cannot be automated without it).
Not needed any more: `account.delete.confirm*` and `account.deleteError*` (out of scope 1.1 (17)).
