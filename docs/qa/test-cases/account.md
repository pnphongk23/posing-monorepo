# Account: sign in, sign out, delete (FEAT-014)

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-ACC-001 | P1 | account switch on, signed out | 1. Launch with accounts on. 2. Open Settings. 3. Tap the Account row | Account screen shows the email sign-in entry | automated: TC-ACC-001-account-signed-out.yaml |
| TC-ACC-002 | P1 | Email sign-in available | Enter email and password, submit | Signed in; Account shows "Signed in" | pending (needs test credentials) |
| TC-ACC-003 | P1 | Email sign-in | Wrong password | Inline sign-in error; stays on form | pending |
| TC-ACC-004 | P1 | Signed in | Sign out | Returns to signed-out state; Saved asks to sign in | pending |
| TC-ACC-005 | P1 | Signed in | Delete account, confirm | Account removed, app signed out; error shown if server fails | pending (server delete landing) |
| TC-ACC-006 | P1 | Sign in, relaunch | Kill and reopen | Still signed in | manual |
| TC-ACC-007 | P1 | account switch on, signed out | 1. Launch with accounts on. 2. Open Settings > Account. 3. Tap "Sign in with email" | Email, password fields and submit button visible | automated: TC-ACC-007-email-form.yaml |
| TC-ACC-008 | P1 | account switch off (launch arg) | 1. Launch with accounts off. 2. Open Settings | Privacy section visible, no Account row | automated: TC-ACC-008-accounts-off.yaml |
| TC-ACC-009 | P1 | account switch on, signed out | 1. Launch with accounts on. 2. Open Settings > Account | Apple button is visible and labelled "Sign in with Apple" (BUG-261029-02: renders blank today) | pending: BUG-261029-02 not fixed |
| TC-ACC-010 | P1 | Fresh install (never signed in), account switch on | 1. Launch with accounts on. 2. Open Settings > Account | Card copy does not imply a previous session (no "again"); wording per BUG-261029-03 | pending: BUG-261029-03 not fixed |
