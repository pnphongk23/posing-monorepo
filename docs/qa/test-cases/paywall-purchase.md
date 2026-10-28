# Paywall and purchase (FEAT-011)

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-PAY-001 | P0 | paywall_enabled, signed out | Capture in camera | Paywall (sign-in required to buy), photo not saved | pending: M02 not landed (no screen presents the paywall, capture gating not built); it will run on the simulator because the gate sits before the camera check |
| TC-PAY-002 | P0 | paywall_enabled off | Capture | Photo saved, no paywall | manual (device) |
| TC-PAY-003 | P1 | Paywall shown, signed out | View paywall | "Sign in with email" prompt, plans not purchasable | pending |
| TC-PAY-004 | P1 | Signed in, StoreKit test config | Pick plan, confirm test purchase | Entitled; capture succeeds | pending (queued E2E, after M01 closes) |
| TC-PAY-005 | P1 | Entitled | Sign out; capture | Paywall again | pending (queued E2E) |
| TC-PAY-006 | P1 | Sign in as different account | Capture | No entitlement carried over | pending (queued E2E) |
| TC-PAY-007 | P1 | Plans fail to load | Open paywall offline | "Retry loading Premium plans" works | manual |
| TC-PAY-008 | P1 | Paywall open | Close | Returns to previous screen | manual |
