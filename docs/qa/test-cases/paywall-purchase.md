# Paywall and purchase (FEAT-011, redesigned build 17)

Business behaviour of the paid surface: what the user is offered, what happens while the App Store is
talking, and what the app is allowed to claim afterwards. Premium unlocks **capture with the full pose
camera** and nothing else — there is no free tier, no quota, no offline pose library, and a purchase is
account-bound, so a signed-out user is asked to sign in first.

Board source: `/tmp/ds-261030/export-c/11-board01..21.png` (paywall, sign-in gate, email sign-in sheet,
evidence page).

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-PAY-001 | P0 | paywall switch on, signed out | 1. Launch with the paywall on. 2. Open the camera, tap the shutter | The paywall cover opens | automated: TC-PAY-001-capture-gated.yaml |
| TC-PAY-002 | P0 | paywall switch off | 1. Launch with the paywall off. 2. Camera → shutter | No paywall; the camera stays (the simulator has no capture device, so no photo is checked) | automated: TC-PAY-002-capture-ungated.yaml |
| TC-PAY-003 | P1 | paywall switch on, signed out | 1. Camera → shutter | The paywall is in its signed-out state: it explains that the purchase is tied to the account and offers a way in, instead of showing prices the user cannot buy | automated: TC-PAY-003-paywall-signin-prompt.yaml |
| TC-PAY-004 | P1 | signed in by email; Debug-Dev build with the RevenueCat Test Store key | 1. Paywall open for an unentitled account. 2. Pick Monthly, Continue. 3. "Test valid purchase" | "Premium access confirmed"; reopening the paywall still reports it; the shutter no longer opens the paywall | automated: TC-PAY-004-purchase-annual-entitles.yaml (tagged `e2e`) |
| TC-PAY-005 | P1 | entitled account | 1. Sign out. 2. Camera → shutter | The paywall is back and asks the signed-out user to sign in: access does not outlive the account | automated: TC-PAY-005-signout-regates-capture.yaml (tagged `e2e`) |
| TC-PAY-006 | P1 | A entitled, B never purchased | 1. Sign out of A, sign in as B. 2. Camera → shutter | B gets the plans with no "Premium access confirmed": A's purchase is not carried over | automated: TC-PAY-006-second-account-no-carryover.yaml (tagged `e2e`) |
| TC-PAY-007 | P1 | paywall open, offering cannot load | 1. Open the paywall where the offering fails | The paywall says plans are unavailable (offline: "Plans can't load", prices "unavailable offline") and offers a **Retry**; retrying with the offering reachable loads the plans in place. It never shows a price it did not receive, and never offers a purchase it cannot complete | draft: redesign-drafts/saved-paywall/flows/TC-PAY-007-plans-unavailable-retry.yaml (needs `paywall.retry`) |
| TC-PAY-008 | P1 | paywall open (signed out) | 1. Close the paywall | The camera is visible again and the paywall is gone; no purchase state changed | automated: TC-PAY-008-close-paywall.yaml |
| TC-PAY-009 | P1 | paywall switch on, signed out | 1. Camera → shutter | Sign in with Apple first, then Google, then email, in that order (guideline 4.8); Apple is not the lesser control | automated: TC-PAY-009-signin-apple-first.yaml |
| TC-PAY-010 | P1 | paywall open, offering still loading | 1. Open the paywall, look at the offer area and the dock | "Loading plans…" where the plans will be, and the subscribe action is not offered yet ("Subscribe turns on when plans load") — a disabled or prematurely enabled button would invite a dead tap | unit: `PaywallModel` phase `.loadingPlans` (dock renders no CTA before `selectedPlan` exists) |
| TC-PAY-011 | P1 | purchase in flight | 1. Start a purchase and watch the paywall while the store sheet is up | The CTA reads "Processing…" and stays disabled, so a second purchase cannot be started from the same sheet | unit: `PaywallModel.phase == .processing` + `isBusy`; e2e observation pending |
| TC-PAY-012 | P1 | Debug-Dev Test Store, paywall open with plans | 1. Continue with the selected plan. 2. "Test failed purchase" | `paywall.status` reports that the purchase could not be completed and that nothing was granted; the plans stay on screen so the user can try again; access is unchanged | draft: redesign-drafts/saved-paywall/flows/TC-PAY-012-purchase-failed.yaml (tagged `e2e`) |
| TC-PAY-013 | P1 | Debug-Dev Test Store, paywall open with plans | 1. Continue with the selected plan. 2. Cancel the store dialog | `paywall.status` says the purchase was cancelled and no access was granted; the app does not claim Premium | draft: redesign-drafts/saved-paywall/flows/TC-PAY-013-purchase-cancelled.yaml (tagged `e2e`) |
| TC-PAY-014 | P1 | paywall open; Test Store | 1. Tap Restore purchases. 2. Repeat with a purchase that the store cannot confirm | A successful restore reports "Premium access confirmed" (access granted); a failed restore says so plainly ("Couldn't restore purchases") and offers Try again instead of silently doing nothing | pending-ids: `paywall.restore`, restore-failure state + Feature copy |
| TC-PAY-015 | P1 | paywall open in any state | 1. Tap Terms of Use. 2. Return, tap Privacy Policy | Both open the real documents in the browser (page content asserted, not just "a URL opened"); the paywall is unchanged when the user comes back | draft: redesign-drafts/saved-paywall/flows/TC-PAY-015-legal-links.yaml |
| TC-PAY-016 | P1 | paywall signed-out state, E2E account | 1. Tap Continue with email. 2. Sign in. 3. Return to the paywall | After a successful sign-in the paywall resumes on the plans for that account (no dead end, no second sign-in prompt) | pending-e2e |
| TC-PAY-017 | P2 | dark appearance; AX3 text | 1. Open the paywall at accessibility text size, in dark mode. 2. Scroll to the bottom | Plan prices, renewal terms, Restore, Terms and Privacy are all reachable by scrolling, and the pinned subscribe button keeps a clear inset — nothing is clipped or overlapped by the dock | draft: redesign-drafts/saved-paywall/flows/TC-PAY-017-ax3-dark.yaml |
| TC-PAY-018 | P1 | Test Store offering with annual and monthly | 1. Open the paywall with plans loaded | Annual card comes first and carries the store's own price/billing line with the annual saving ("Save 44%" when the store reports it); monthly follows; no hardcoded price, no fabricated discount. The same numbers appear in the disclosure line above the CTA | e2e (Test Store) + unit: `PaywallPlanCatalog` ordering / `summaryLine`; assert against the offering, not a hardcoded string |

## Notes (how these run)

- Purchases stay **Test Store only, on the Debug-Dev build**: the key is a `test_…` RevenueCat key, its
  dialog is app-process UI with stable labels, so no StoreKit file or sandbox Apple ID is needed. On the
  **Prod-config build a purchase is never started** — that build carries the live key and the paywall
  there must be driven up to (and including) "plans visible", never to `paywall.cta`.
- Credentials come only from the gitignored `mobile/iosApp/maestro/e2e.local.env` (`E2E_EMAIL`,
  `E2E_PASSWORD`, `E2E_EMAIL_B`, `E2E_PASSWORD_B`) via `-e`; flows carry the `e2e` tag so a plain run
  skips them. The App Review demo account (`tester.posing.003`) is never used.
- Prices live in the plan card's accessibility label (`<plan> plan, <selected>, <price> per <period>`), so
  a flow can assert a real currency amount by id without hardcoding a price.
- `paywall.status` is the banner for cancelled / failed / entitled / unavailable; it is absent in the
  ready state, which is how "no error shown" is asserted.
- Sign-in gate copy ("Sign in to subscribe", "Your Premium stays with your account") and the Apple-first
  ordering are covered by TC-PAY-003 / TC-PAY-009; the email sheet states (invalid email, signing in,
  wrong password, offline) belong to the sign-in surface, not to this doc.

## Requests to Feature (ids needed before the drafts can move into `maestro/flows`)

| Id | Why | Used by |
|---|---|---|
| `paywall.retry` | the unavailable state's Retry is only labelled "Retry loading Premium plans" | TC-PAY-007 |
| `paywall.restore` | the Restore purchases link has no id | TC-PAY-014 |
| `paywall.terms`, `paywall.privacy` | the legal links are only labelled "Terms of Use" / "Privacy Policy" | TC-PAY-015 |
| `paywall.unavailable` | the unavailable/offline notice is labelled "Premium unavailable" but has no id (the `paywall.status` id is only applied in the ready/processing branch) | TC-PAY-007 |
| restore-failure state | boards show "Couldn't restore purchases … Try again"; the model currently has no such phase/copy | TC-PAY-014 |
