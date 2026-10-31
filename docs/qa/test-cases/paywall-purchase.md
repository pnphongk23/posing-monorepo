# Paywall and purchase (FEAT-011)

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-PAY-001 | P0 | paywall switch on (launch arg), signed out | 1. Launch with the paywall on. 2. Open the camera. 3. Tap the shutter | Paywall sheet opens | automated: TC-PAY-001-capture-gated.yaml |
| TC-PAY-002 | P0 | paywall switch off (launch arg) | 1. Launch with the paywall off. 2. Open the camera. 3. Tap the shutter | No paywall; camera stays on screen (simulator has no camera, so no photo is checked) | automated: TC-PAY-002-capture-ungated.yaml |
| TC-PAY-003 | P1 | paywall switch on, signed out | 1. Launch with the paywall on. 2. Open the camera. 3. Tap the shutter | Paywall shows the sign-in prompt | automated: TC-PAY-003-paywall-signin-prompt.yaml |
| TC-PAY-004 | P1 | Signed in by email; Debug-Dev build carrying the RevenueCat Test Store key | 1. Launch with the paywall on. 2. Sign in. 3. Camera → shutter (paywall opens for this unentitled account). 4. Pick Monthly, tap "Continue with Monthly". 5. Tap "Test valid purchase" in the Test Store dialog | "Premium access confirmed"; reopening the paywall (Settings → Premium) still reports it; the shutter no longer opens the paywall | automated: TC-PAY-004-purchase-annual-entitles.yaml |
| TC-PAY-005 | P1 | Entitled account (TC-PAY-004 done) | 1. Settings → Account → Sign out. 2. Camera → shutter | The paywall is back and asks the signed-out user to sign in | automated: TC-PAY-005-signout-regates-capture.yaml |
| TC-PAY-006 | P1 | Account A entitled on this device, account B has never purchased | 1. Sign out of A. 2. Sign in as B. 3. Camera → shutter | Paywall with the plans and no sign-in prompt, no "Premium access confirmed" — A's entitlement is not carried over | automated: TC-PAY-006-second-account-no-carryover.yaml |
| TC-PAY-007 | P1 | Plans fail to load | Open paywall offline | "Retry loading Premium plans" works | manual |
| TC-PAY-008 | P1 | paywall switch on, signed out | 1. Launch with the paywall on. 2. Open the camera. 3. Tap the shutter. 4. Close the paywall | Camera visible again, paywall gone | automated: TC-PAY-008-close-paywall.yaml |
| TC-PAY-009 | P1 | paywall switch on, signed out | 1. Launch with the paywall on. 2. Open the camera. 3. Tap the shutter | The signed-out paywall offers Sign in with Apple first (`paywall.signin.apple`), then Google (`paywall.signin`) and email (`signin.emailEntry`) in that visual order, with Apple not the lesser control (same full-width size and border as Google) | automated: TC-PAY-009-signin-apple-first.yaml |

Notes on TC-PAY-004/005/006/009 (why they are still not automated):

- A purchase **can** be driven on the simulator — the Dev-Debug build uses a RevenueCat **Test Store**
  key, whose dialog ("Test valid purchase" / "Test failed purchase" / "Cancel") is app-process UI with
  stable labels. A `.storekit` file or a sandbox Apple ID is not needed and would not help (a scheme
  StoreKit configuration is applied by Xcode's run action, not by a Maestro launch).
- The remaining blocker for 004/005/006 is sign-in: all three start from a real Account, and the
  credentials exist only in the gitignored `mobile/iosApp/maestro/e2e.local.env`. TC-PAY-009 needs no
  account, but its flow is still a draft until the same simulator run happens.
- Every paywall element the flows touch is addressed by id — `paywall.close`, `paywall.signin.apple`,
  `paywall.signin`, `signin.emailEntry`, `paywall.plan.annual`, `paywall.plan.monthly`, `paywall.status`,
  `paywall.cta` (`SupportScreens.swift:541-557`, one declaration each per
  `PaywallAppleSignInTests.testEveryPaywallIdentifierIsDeclaredOnceAndRenderedFromTheConstants`), so no
  flow depends on a price-bearing label.
- The simulator has no capture device, so "capture succeeds" is asserted as the **gate** answer (an
  unentitled press opens the paywall, an entitled one does not) plus the provider's confirmation
  banner read by id. Whether a photo is actually written after the purchase stays a device check
  (TC-GAL-002).
- "Equal prominence" in TC-PAY-009 is geometry, which no Maestro selector can measure; the flow asserts
  presence and the Apple-above-Google order (`below:` selector), while size/width parity is pinned by
  `PaywallAppleSignInTests` + `PaywallSignInOption.allCases`.
- Apple cancel shows no banner and an Apple failure shows `authError` in the sign-in notice; neither is
  a separate case here because both are asserted at unit level
  (`PaywallAppleSignInTests`, paywall model tests).
