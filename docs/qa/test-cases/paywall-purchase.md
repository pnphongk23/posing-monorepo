# Paywall and purchase (FEAT-011, redesigned build 18)

Business behaviour of the paid surface: what the user is offered, what the app may claim about it, and
what happens while the App Store is talking. Premium unlocks **capture with the full pose camera** and
nothing else — no free tier, no quota, no offline pose library — and a purchase is account-bound, so a
signed-out user is asked to sign in before buying.

Board source: `/tmp/ds-261030/export-c/11-board01..21.png`. Gap source: `/tmp/gap/09-11.md` §11 — the
paywall is **PARTIAL and a different design** (no hero, extra benefits that contradict the shutter-only
rule, "Annual/Recommended" vs "Yearly/Save 44%", "Continue with Annual" vs "Subscribe", `.sheet` vs
full-screen cover, footnote text instead of error cards, no offline/AX3-scrolled pass). Everything the
flows could run today still uses the pre-redesign screen; the rows below say which ones must be
**re-baselined** against build 17.

Status legend: `automated:` = committed flow that passes, `draft:` = flow in
`docs/qa/redesign-drafts/saved-paywall/` (not yet run), `unit:` = XCTest only, `pending` = blocked on an
id or on data, `out of scope 1.1` = agreed out of this release.

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-PAY-001 | P0 | paywall switch on, signed out | 1. Launch with the paywall on. 2. Open the camera, tap the shutter | The paywall opens over the app and the press does not capture. Presentation is the **full-screen cover** the redesign commits to (no sheet grabber, nothing of the camera interactive behind it) and the close control stays reachable | automated: TC-PAY-001-capture-gated.yaml — **re-baseline** (presentation: sheet → full-screen cover) |
| TC-PAY-002 | P0 | paywall switch off | 1. Launch with the paywall off. 2. Camera → shutter | No paywall; the camera stays (the simulator has no capture device, so no photo is checked) | automated: TC-PAY-002-capture-ungated.yaml |
| TC-PAY-003 | P1 | paywall switch on, signed out | 1. Camera → shutter. 2. Tap the CTA "Sign in to subscribe" | The signed-out paywall still shows **what is being sold** (plan cards, prices deferred) and one primary CTA that opens the sign-in sheet (`paywall.signin.sheet` at full height) — the offer is not hidden behind an auth wall, and the ways in are queryable (fixed: `BUG-PAY-18-01`, `33d4354`) | automated: TC-PAY-003-paywall-signin-prompt.yaml — **re-baselined + held for dev19** |
| TC-PAY-004 | P1 | signed in by email; Debug-Dev build with the RevenueCat Test Store key | 1. Paywall open for an unentitled account. 2. Pick a plan, tap the CTA. 3. "Test valid purchase" | "Premium access confirmed"; reopening the paywall still reports it; the shutter no longer opens the paywall. CTA copy is **Subscribe** (not "Continue with <plan>") | automated: TC-PAY-004-purchase-annual-entitles.yaml (tagged `e2e`) — **re-baseline** (CTA copy, plan labels) |
| TC-PAY-005 | P1 | entitled account | 1. Sign out. 2. Camera → shutter | The paywall is back and asks the signed-out user to sign in: access does not outlive the account | automated: TC-PAY-005-signout-regates-capture.yaml (tagged `e2e`) |
| TC-PAY-006 | P1 | A entitled, B never purchased | 1. Sign out of A, sign in as B. 2. Camera → shutter | B gets the plans with no "Premium access confirmed": A's purchase is not carried over | automated: TC-PAY-006-second-account-no-carryover.yaml (tagged `e2e`) — **re-baseline** (CTA copy) |
| TC-PAY-007 | P1 | paywall open, offering cannot load (offline or store failure) | 1. Open the paywall offline | The paywall keeps the offer's shape but tells the truth: an offline banner plus plan rows marked "Price unavailable offline", and the subscribe action disabled with the reason. No price is invented and no purchase is offered that cannot complete; **Retry** recovers in place once the offering loads | draft: redesign-drafts/saved-paywall/flows/TC-PAY-007-plans-unavailable-retry.yaml — **re-baseline** (banner + per-plan unavailable rows) |
| TC-PAY-008 | P1 | paywall open (signed out) | 1. Close the paywall | The camera is visible again and the paywall is gone; no purchase state changed | automated: TC-PAY-008-close-paywall.yaml — **re-baseline** (full-screen cover) |
| TC-PAY-009 | P1 | paywall switch on, signed out | 1. Camera → shutter. 2. Tap Sign in to subscribe | The sign-in options appear in their own sheet (`paywall.signin.sheet`) in App Review 4.8 order: Apple first — drawn with the system `SignInWithAppleButton` — then Google (`paywall.signin`), then email (`signin.emailEntry`); the sheet can be dismissed (`paywall.signin.close`) back to the paywall without buying or signing in | automated: TC-PAY-009-signin-apple-first.yaml — **re-baseline** (options move into a sheet; Apple becomes the system control; add the dismiss check) |
| TC-PAY-010 | P1 | paywall open, offering still loading | 1. Open the paywall, look at the offer area and the dock | Loading keeps the offer's geometry — skeleton plan cards — and the subscribe action is present but disabled with helper copy ("Subscribe turns on when plans load"). No spinner row, no disappearing CTA | unit: `PaywallModel` phase `.loadingPlans`; **re-baseline** (skeleton cards + disabled CTA) |
| TC-PAY-011 | P1 | purchase in flight | 1. Start a purchase and watch the paywall while the store sheet is up | The CTA reads "Processing…" and stays disabled, so a second purchase cannot be started from the same sheet | unit: `PaywallModel.phase == .processing` + `isBusy`; e2e observation pending |
| TC-PAY-012 | P1 | Debug-Dev Test Store, paywall open with plans | 1. Continue with the selected plan. 2. "Test failed purchase" | The failure is reported as an error **card** (with a way to try again), not a footnote, and it says nothing was granted; no access is created | automated: TC-PAY-012-purchase-failed.yaml (tagged `e2e`) — **re-baseline** (error card + Try again) |
| TC-PAY-013 | P1 | Debug-Dev Test Store, paywall open with plans | 1. Continue with the selected plan. 2. Cancel the store dialog | The app reports the cancellation and that no access was granted; the plans stay on screen so the user can start again when ready | automated: TC-PAY-013-purchase-cancelled.yaml (tagged `e2e`) |
| TC-PAY-014 | P1 | paywall open; Test Store | 1. Tap Restore purchases. 2. Repeat with a store that cannot answer | A successful restore reports access confirmed; a failed restore says so in place ("Couldn't restore purchases") with its own **Try again** — the restore link must not leave the user with a silent failure | pending ids (`paywall.restore` + restore-error state) — **re-baseline** (inline retry, failure copy) |
| TC-PAY-015 | P1 | paywall open in any state | 1. Tap Terms of Use. 2. Return, tap Privacy Policy | Both links open the real documents in the browser (asserted on the documents' own text), and the paywall is unchanged when the user comes back. Labels are the board's "Terms of Use" / "Privacy Policy" (today "Terms" / "Privacy") | automated: TC-PAY-015-legal-links.yaml — **re-baseline** (labels) |
| TC-PAY-016 | P1 | paywall signed-out state, E2E account | 1. Tap Sign in. 2. Sign in from the sheet. 3. Return to the paywall | After a successful sign-in the paywall resumes on the plans for that account (no dead end, no second sign-in prompt) | pending-e2e |
| TC-PAY-017 | P2 | dark appearance; AX3 text | 1. Open the paywall at accessibility text size, in dark mode. 2. Scroll to the bottom | The full disclosure is reachable by scrolling — plan prices, renewal terms, Restore, Terms and Privacy — and the pinned subscribe button keeps a clear inset above it, so nothing is clipped or covered by the dock (board `11-paywall-ax3-scrolled`) | automated: TC-PAY-017-ax3-dark.yaml — **re-baseline** (bottom inset, disclosure reachability) |
| TC-PAY-018 | P1 | Test Store offering with yearly and monthly | 1. Open the paywall with plans loaded | The yearly card comes first and carries the store's own price and per-period breakdown, plus a saving badge whose percentage is **derived from the two prices** (12 × monthly vs yearly — the board's 44 % is an example, not a constant, so a different offering must show a different number); monthly follows. No hardcoded price and no invented discount, and the same numbers appear in the disclosure line above the CTA | e2e (Test Store) + unit: `PaywallPlanCatalog` — **re-baseline** ("Yearly" label, pricing-derived badge) |
| TC-PAY-019 | P0 | paywall open with plans loaded (Test Store or a build whose offering resolves) | 1. Read the paywall from the offer to the dock; 2. Open Terms and Privacy from it | **App Store 3.1.2 disclosure, MUST COVER in 1.2**: the surface itself states the price, the billing period, that the subscription **auto-renews** until cancelled, and how to cancel (Apple ID settings), and both Terms of Use and Privacy Policy links are present and open. A paywall that sells without all five cannot ship | pending ids (`paywall.disclosure.price`, `paywall.disclosure.renewal`, `paywall.disclosure.cancel`) + draft follows them; the copy half is assertable by regex today |
| TC-PAY-020 | P0 | paywall open, any state | 1. Read the benefit area and every claim on the surface | **Shutter-only claim (B5), MUST COVER**: Premium is described as capture with the full pose camera and nothing more — the redesign reduces the benefit list to **one** block (`paywall.benefit`), and no claim survives for free shots, a daily quota, a "full pose library" or offline poses (`09-11.md`: the current "Discover"/"Keep" benefits break this rule). A second benefit block is a regression even if its copy is harmless | draft asserts exactly one `paywall.benefit` element + unit: copy constants; **re-baseline** (app currently shows three benefits) |
| TC-PAY-021 | P1 | signed in, paywall open | 1. Read the paywall header | The surface says which account the purchase will attach to ("Signed in as <email>" on the board). Buying Premium against an invisible account is the failure this prevents — the user must be able to see whose subscription this will be | pending id (`paywall.account.email`); **new behaviour** |

## Accepted design deviation (GL, dev19)

- **The sign-in sheet is full height (`.large`), the board draws a medium sheet.** Accepted: a medium detent
  keeps the sheet's content out of the accessibility tree on iOS 16+/26 (that was `BUG-PAY-18-01`'s root
  cause), so accessibility wins over the board here. The visual pass should expect a full-height sheet and
  must not file it.

## Notes (how these run)

- Purchases stay **Test Store only, on the Debug-Dev build** (`test_…` RevenueCat key; the SDK dialog is
  app-process UI with stable labels, so no `.storekit` file and no sandbox Apple ID are needed). On the
  **Prod-config build a purchase is never started**: that build carries the live key, so flows stop at
  "plans visible" and never tap `paywall.cta`.
- Credentials come only from the gitignored `mobile/iosApp/maestro/e2e.local.env` via `-e`; credential
  flows carry the `e2e` tag so a plain run skips them. The App Review demo account is never used.
- Prices live in the plan card's accessibility label, so a flow asserts a real currency amount by id
  without hardcoding a price. `paywall.status` is the outcome banner (cancelled / failed / entitled /
  unavailable) and is absent in the ready state, which is how "no error shown" is asserted.
- Email-sign-in specifics (validation, submitting, wrong password, offline) and the "Forgot password?"
  link belong to the sign-in surface, not this doc; **password reset is out of scope 1.1**.

## Re-baselining that landed with build 18

Rows marked **re-baseline** above change their expected result or their copy, so their flows/assertions
must be updated in the same commit that promotes them: TC-PAY-001, 003, 004, 006, 007, 008, 009, 010, 012,
014, 015, 017, 018, 020. Unaffected: 002, 005, 011, 013, 016. New in 1.1: 019, 020, 021.

## Build 1.1 (17) — historical

The build-17 app (`a03d03a`) had the support-screen split but **not** the paywall redesign, so the 17 run
verified the eight existing flows as regressions (all PASS; see the drafts README for the run table). Those
results are history: the redesign is in **1.1 (18)**, which is what the cases below now describe.

## Build 1.1 (18) — first run against the redesign

Re-baselined before the run (flow defects, not app bugs): `TC-PAY-003` and `TC-PAY-005` now assert the
signed-out CTA label ("Sign in to subscribe") and open `paywall.signin.sheet`, and
`subflows/pay-buy-monthly.yaml` asserts the single "Subscribe" CTA instead of "Continue with Monthly".

**Held for dev19** (prepared, not run): `TC-PAY-003`, `TC-PAY-009` (sheet is now queryable — `33d4354`), and
`TC-PAY-012`, `TC-PAY-013` (failure → "Try again"; cancel → silence — `821bd71`), all on the Dev Test Store
key with account B for the unentitled ones.

## Promotable at the 1.1 (18) run

Verified against committed source at `a03d03a` (the paywall redesign had **not** landed there, and the
redesign's new ids — `paywall.benefit`, `paywall.offline`, `paywall.notice`, `paywall.signin.sheet`,
`paywall.signin.close` — are committed in build 18, so the drafts that use them are promoted with this run; these run
against the current surface and their re-baseline notes stay open): `paywall.close`, `paywall.cta`,
`paywall.plan.annual`, `paywall.plan.monthly`, `paywall.signin.apple`, `paywall.signin`, `paywall.status`,
`signin.emailEntry`. So **TC-PAY-012, 013, 015, 017** are promoted with the run (012/013 need the Dev Test
Store key and the E2E account; 015 taps the code-owned labels "Terms of Use" / "Privacy Policy"). Still a
draft: **TC-PAY-007** — the unavailable/offline offer has no deterministic producer on a Test Store build.

## Requests to Feature (ids needed before the drafts can move into `maestro/flows`)

| Id | Why | Used by |
|---|---|---|
| `paywall.retry` | the unavailable state's Retry is only labelled "Retry loading Premium plans" (still not in the incoming id list) | TC-PAY-007 |
| ~~`paywall.unavailable`~~ | superseded: Feature is committing `paywall.notice` (the note in the offer area) and `paywall.offline` (the offline banner). Drop this request once both land | TC-PAY-007 |
| `paywall.restore` | the Restore purchases link has no id | TC-PAY-014 |
| `paywall.terms`, `paywall.privacy` | legal links are only labelled "Terms of Use" / "Privacy Policy" | TC-PAY-015, TC-PAY-019 |
| `paywall.disclosure.price`, `paywall.disclosure.renewal`, `paywall.disclosure.cancel` | 3.1.2 disclosure lines need stable anchors so the case cannot pass on partial copy | TC-PAY-019 |
| `paywall.account.email` | "Signed in as <email>" line | TC-PAY-021 |
| `paywall.signin.sheet`, `paywall.signin.close` | **confirmed incoming** (pending commit): the sheet and its dismiss control, so "the options are in the sheet, not inline" and "dismiss returns to the paywall" are assertable | TC-PAY-009, TC-PAY-016 |
| `paywall.benefit` | **confirmed incoming** (pending commit): one block for the shutter-only claim, so "exactly one benefit" is assertable | TC-PAY-020 |
| `paywall.notice`, `paywall.offline` | **confirmed incoming** (pending commit): the notice and the offline banner | TC-PAY-007 |
| restore-failure state | boards show "Couldn't restore purchases … Try again"; the model has no such phase/copy | TC-PAY-014 |
