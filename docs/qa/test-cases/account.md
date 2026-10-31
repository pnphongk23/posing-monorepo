# Account: sign in, sign out, delete (FEAT-014)

Build-17 redesign: Account is pushed from the Settings hub's account card, no dock, one-row header.
Cases marked `pending (ids …)` exist only in the boards; their draft flows live in
`docs/qa/redesign-drafts/settings-account/` until Feature commits the ids.

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-ACC-001 | P1 | account switch on, signed out | 1. Launch with accounts on. 2. Open Settings. 3. Tap the Account row | Account screen shows the email sign-in entry | automated: TC-ACC-001-account-signed-out.yaml |
| TC-ACC-002 | P1 | Email sign-in available | Enter email and password, submit | Signed in; Account shows the identity | pending (needs test credentials; e2e-tagged flow) |
| TC-ACC-003 | P1 | Email sign-in | Wrong password | Inline sign-in error; stays on form | pending (needs test credentials) |
| TC-ACC-004 | P1 | Signed in | Sign out | Returns to signed-out state; Saved asks to sign in | pending (flow needs `account.signout`; the state transition itself is unit-covered by `AccountSessionTests.testSignOutClearsCredentialsAndProjectsSignedOut`) |
| TC-ACC-005 | P1 | Signed in | Delete account | The account deletion request form opens; the session is untouched afterwards and nothing is deleted in-app | manual (browser + server delete landing; prod-sim smoke S-02) |
| TC-ACC-006 | P1 | Sign in, relaunch | Kill and reopen | Still signed in | manual |
| TC-ACC-007 | P1 | account switch on, signed out | 1. Launch with accounts on. 2. Open Settings > Account. 3. Tap "Sign in with email" | Email, password fields and submit button visible | automated: TC-ACC-007-email-form.yaml |
| TC-ACC-008 | P1 | account switch off (launch arg) | 1. Launch with accounts off. 2. Open Settings | Privacy/legal rows still reachable, no Account row | automated: TC-ACC-008-accounts-off.yaml |
| TC-ACC-009 | P1 | account switch on, signed out | 1. Launch with accounts on. 2. Open Settings > Account | Apple button is visible and labelled "Sign in with Apple" | automated: TC-ACC-009-apple-button-label.yaml |
| TC-ACC-010 | P1 | Fresh install (never signed in), account switch on | 1. Launch with accounts on. 2. Open Settings > Account | Card copy does not imply a previous session (no "again") | automated: TC-ACC-010-fresh-install-copy.yaml |
| TC-ACC-011 | P1 | Signed in, slow account read | Open Account from the Settings card | A skeleton stands in for the real rows (avatar, name, email, two sections) instead of an error or a blank screen; it resolves into the signed-in content without a flash of the signed-out card | pending (ids: `account.loading`, `account.avatar`, `account.name`, `account.email`) |
| TC-ACC-012 | P0 | Account read fails (e.g. 503) | Open Account | One centred icon, the title "Couldn't load your account", a body naming the failure and reassuring that Saved poses are unaffected, and a "Try again" control; retrying re-reads and recovers into the signed-in content without leaving the screen | pending (ids: `account.error`, `account.error.retry`; retry-after-failure is unit-covered by `AccountSessionTests.testRetryReloadsAfterFailure`, and a non-unauthorized failure surfaces the server message) |
| TC-ACC-013 | P0 | Signed in, device offline | Open Account | An offline banner states cached account details are being shown; the cached email and sign-in method still render; **Delete account is disabled and says "Connect to the internet to delete"** while Sign out stays available — an offline user can never be left believing a delete was attempted | pending (ids: `account.offline.banner`, `account.delete`, `account.delete.reason`, `account.signout`) |
| TC-ACC-014 | P1 | Signed in, with a live entitlement | Open Account | Avatar with initials, display name and email; PROFILE lists Email and Sign-in method; PREMIUM shows the plan and its renewal date and a "Manage subscription" row that opens the Apple ID subscription settings; the footnote states that deleting the account does not cancel the Apple subscription | pending (ids: `account.profile.email`, `account.profile.method`, `account.plan`, `account.manageSubscription`; destinations are unit-covered by `SupportDestinationsTests`) |
| TC-ACC-015 | P1 | Signed in | Tap Sign out on Account | Sign-out is destructive-styled but not the primary pink action; afterwards the hub shows the signed-out card (TC-SET-006) and Saved asks to sign in; no account data remains on the device | pending (ids: `account.signout`, plus the TC-SET-006 ids for the resulting hub) |
| TC-ACC-016 | P1 | Signed in | Tap Delete account | A confirm dialog explains that the account **and its Saved poses** are deleted permanently, that an Apple subscription is **not** cancelled, and offers Delete account (destructive red), Manage subscription and Cancel; Cancel and Manage subscription leave the account intact | pending (ids: `account.delete.confirm`, `account.delete.confirm.delete`, `account.delete.confirm.manage`, `account.delete.confirm.cancel`) — **conflict with committed behaviour**: since 54dda46 the row opens the web request form directly with no in-app confirmation (board `10-account-delete-confirm` predates that), so this case is blocked on a Feature answer (A2) |
| TC-ACC-017 | P1 | Signed in | Delete the account while the request fails | An inline error on Account says the deletion did not finish, that nothing was deleted and the Apple subscription is unchanged, with "Try again" and "Keep my account"; the account stays signed in | pending (ids: `account.deleteError`, `account.deleteError.retry`, `account.deleteError.keep`) — same conflict as TC-ACC-016 (A2) |
| TC-ACC-018 | P1 | Signed in with a long display name and email | Read Account at large and AX3 text sizes | The email wraps to a second line inside the row instead of truncating or pushing the value out of the card; the avatar initials stay aligned; no row overlaps its neighbour | pending (ids: `account.email`, `account.avatar`) — visual wrap check, one real risk (truncation) |
| TC-ACC-019 | P1 | Signed in, on Account | Press Back | Back returns to the Settings hub with the account card still showing the same identity (no re-fetch flash to the signed-out card) and no dock of its own | pending (ids: `account.back`, `settings.accountCard`) |
| TC-ACC-020 | P1 | accounts flag off (launch arg) | 1. Launch with accounts off. 2. Open Settings. 3. Inspect the hub | No account card, no sign-in card and no Account entry exist; nothing in the hub advertises a feature the flag has switched off | pending (ids: `settings.accountCard`, `settings.signIn.card`; TC-ACC-008 covers the current `settings.account.row` absence) |

## Assumptions

- **A1 — hub entry.** Account is reached from the Settings account card (board `10-settings-hub-*`) and
  returns there with Back. The 1.2 `settings.account.row` may or may not survive the redesign; my flows
  change with the build, the cases do not.
- **A2 — delete account, boards vs committed behaviour.** `10-account-delete-confirm` and
  `10-account-delete-error` describe an in-app confirmation dialog and an inline delete error, but
  commit 54dda46 made the row open the web request form directly (no dialog, no `account.delete.error`
  id). TC-ACC-005 follows the committed behaviour; TC-ACC-016/017 follow the boards and are blocked
  until Feature or the owner says which is build 17.
- **A3 — offline.** The offline banner keeps the cached identity readable. Kept as a separate case from
  the error state because a cached read is not a failure and must not look like one.
- **A4 — sign-in states.** loading/error/offline only; a signed-out-with-error variant is covered by
  TC-ACC-012's reassurance copy, not by a separate case.

## Requests to Feature (build 17 ids — all unconfirmed)

Account screen: `account.back`, `account.title`, `account.avatar`, `account.name`, `account.email`,
`account.loading`, `account.error`, `account.error.retry`, `account.offline.banner`,
`account.profile.email`, `account.profile.method`, `account.plan`, `account.manageSubscription`,
`account.signout`, `account.delete`, `account.delete.reason` (the offline "connect to the internet"
explanation, readable as text/id).
Delete flow: `account.delete.confirm`, `account.delete.confirm.delete`, `account.delete.confirm.manage`,
`account.delete.confirm.cancel`, `account.deleteError`, `account.deleteError.retry`,
`account.deleteError.keep`.
Hub side used by these cases: `settings.accountCard`, `settings.signIn.card` (see `settings.md`).
Sign-in (needed by TC-ACC-002/003 draft flows, unconfirmed): `signin.error` exists; a submit-in-flight
state id (`signin.submitting`) would let the double-submit case be automated safely.
