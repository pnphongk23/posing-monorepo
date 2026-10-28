# Account: sign in, sign out, delete (FEAT-014)

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-ACC-001 | P1 | account_feature on, signed out | Settings > Account | Sign-in options (Google, email) shown | pending (identifiers for sign-in entry via Account) |
| TC-ACC-002 | P1 | Email sign-in available | Enter email and password, submit | Signed in; Account shows "Signed in" | pending (needs test credentials) |
| TC-ACC-003 | P1 | Email sign-in | Wrong password | Inline sign-in error; stays on form | pending |
| TC-ACC-004 | P1 | Signed in | Sign out | Returns to signed-out state; Saved asks to sign in | pending |
| TC-ACC-005 | P1 | Signed in | Delete account, confirm | Account removed, app signed out; error shown if server fails | pending (server delete landing) |
| TC-ACC-006 | P1 | Sign in, relaunch | Kill and reopen | Still signed in | manual |
