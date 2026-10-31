# Paywall and purchase (FEAT-011)

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-PAY-001 | P0 | paywall switch on (launch arg), signed out | 1. Launch with the paywall on. 2. Open the camera. 3. Tap the shutter | Paywall sheet opens | automated: TC-PAY-001-capture-gated.yaml |
| TC-PAY-002 | P0 | paywall switch off (launch arg) | 1. Launch with the paywall off. 2. Open the camera. 3. Tap the shutter | No paywall; camera stays on screen (simulator has no camera, so no photo is checked) | automated: TC-PAY-002-capture-ungated.yaml |
| TC-PAY-003 | P1 | paywall switch on, signed out | 1. Launch with the paywall on. 2. Open the camera. 3. Tap the shutter | Paywall shows the sign-in prompt | automated: TC-PAY-003-paywall-signin-prompt.yaml |
| TC-PAY-004 | P1 | Signed in by email; Debug-Dev build carrying the RevenueCat Test Store key | 1. Launch with the paywall on. 2. Sign in. 3. Camera → shutter (paywall opens for this unentitled account). 4. Pick Monthly, tap "Continue with Monthly". 5. Tap "Test valid purchase" in the Test Store dialog | "Premium access confirmed"; reopening the paywall (Settings → Premium) still reports it; the shutter no longer opens the paywall | pending (flow drafted: `docs/qa/purchase-e2e/flows/TC-PAY-004-purchase-annual-entitles.yaml` — blocked on `E2E_EMAIL`/`E2E_PASSWORD`, see `../purchase-e2e-blockers.md`) |
| TC-PAY-005 | P1 | Entitled account (TC-PAY-004 done) | 1. Settings → Account → Sign out. 2. Camera → shutter | The paywall is back and asks the signed-out user to sign in | pending (flow drafted: `docs/qa/purchase-e2e/flows/TC-PAY-005-signout-regates-capture.yaml` — same blocker) |
| TC-PAY-006 | P1 | Account A entitled on this device, account B has never purchased | 1. Sign out of A. 2. Sign in as B. 3. Camera → shutter | Paywall with the plans and no sign-in prompt, no "Premium access confirmed" — A's entitlement is not carried over | pending (flow drafted: `docs/qa/purchase-e2e/flows/TC-PAY-006-second-account-no-carryover.yaml` — needs the second credential pair too) |
| TC-PAY-007 | P1 | Plans fail to load | Open paywall offline | "Retry loading Premium plans" works | manual |
| TC-PAY-008 | P1 | paywall switch on, signed out | 1. Launch with the paywall on. 2. Open the camera. 3. Tap the shutter. 4. Close the paywall | Camera visible again, paywall gone | automated: TC-PAY-008-close-paywall.yaml |

Notes on TC-PAY-004/005/006 (why they are still not automated):

- A purchase **can** be driven on the simulator — the Dev-Debug build uses a RevenueCat **Test Store**
  key, whose dialog ("Test valid purchase" / "Test failed purchase" / "Cancel") is app-process UI with
  stable labels. A `.storekit` file or a sandbox Apple ID is not needed and would not help (a scheme
  StoreKit configuration is applied by Xcode's run action, not by a Maestro launch).
- The remaining blocker is sign-in: all three cases start from a real Account, and the repo holds no
  test credentials (`SIGNIN` form is automated, the accounts are not). The flows are drafted in
  `docs/qa/purchase-e2e/` and take `E2E_EMAIL`/`E2E_PASSWORD` (+ `_B`) from the runner environment.
- The simulator has no capture device, so "capture succeeds" is asserted as the **gate** answer (an
  unentitled press opens the paywall, an entitled one does not) plus the provider's confirmation
  banner. Whether a photo is actually written after the purchase stays a device check (TC-GAL-002).
