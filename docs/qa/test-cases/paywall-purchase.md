# Paywall and purchase (FEAT-011) — **paywall C**, build 1.1 (20)

Business behaviour of the paid surface: what the user is offered, what the app may claim about it, and what
happens while the App Store is talking. Premium unlocks **capture with the full pose camera** and nothing
else — no free tier, no quota, no offline library — and a purchase is account-bound, so a signed-out user is
asked to sign in before buying.

Build 20 replaces the shipped paywall with **paywall C**: real store prices, the yearly plan selected by
default, per-month breakdown and saving computed from the two products, prices visible while signed out, an
X close, the auto-renew disclosure, Restore/Terms/Privacy always reachable, and a legal row that survives
iPhone SE at Dynamic Type AX5. Every row below is the same case id it was before — this is an in-place
update, not a second set of cases.

**Id policy.** Where an id is not final, the row says `id TBD on dev20` instead of guessing; the source of
truth is the committed `PaywallScreen.swift` at the dev20 sha, verified with `git grep` before any flow is
re-pointed. Ids that exist today and are expected to survive: `paywall.close`, `paywall.cta`,
`paywall.plan.annual`, `paywall.plan.monthly`, `paywall.status`, `paywall.retry`, `paywall.benefit`,
`paywall.notice`, `paywall.offline`, `paywall.signin.sheet`, `paywall.signin.close`, `paywall.signin.apple`,
`paywall.signin`, `signin.emailEntry`.

**Two columns matter below:** *Sim* = provable on a Debug-Dev simulator build with the Test Store key
(structure, wiring, state machines); *Device* = needs the TestFlight build or a physical SE, because a
Release build on a simulator cannot resolve the real StoreKit products and the SE/AX5 geometry is hardware.

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-PAY-001 | P0 | paywall switch on, signed out | 1. Launch with the paywall on. 2. Open the camera, tap the shutter | The paywall opens as a full-screen cover over the camera and the press captures nothing: hero, the single shutter-only benefit, the plan section with the **yearly card selected by default**, the X, and the disclosure/dock. Nothing of the camera is interactive behind it | automated: TC-PAY-001-capture-gated.yaml (automatable on sim; re-pointed for paywall C on dev20) |
| TC-PAY-002 | P0 | `paywall_enabled` **off** | 1. Launch with the switch off. 2. Camera → shutter. 3. Settings → Library | No paywall anywhere: the shutter captures (simulator has no capture device, so the camera simply stays), there is **no Premium row** in Settings, and no route opens the surface. The kill switch is a real rollback, not a hidden screen | automated: TC-PAY-002-capture-ungated.yaml (automatable on sim; add the Settings-Premium-absence check) |
| TC-PAY-003 | P1 | paywall switch on, signed out | 1. Camera → shutter. 2. Read the plan cards. 3. Tap the CTA | **Prices are visible while signed out** (paywall C), so the offer is honest before signing in; the CTA reads "Sign in to subscribe" and opens the sign-in sheet (full-height, Apple → Google → email). **Never tap the CTA on a prod-config build** — it is a purchase path there | automated: TC-PAY-003-paywall-signin-prompt.yaml (automatable on sim; re-pointed on dev20) |
| TC-PAY-004 | P1 | account A signed in, Dev Test Store key | 1. Open the paywall. 2. Select monthly, tap Subscribe. 3. "Test valid purchase" | Access is granted ("Premium access confirmed"), the paywall closes itself, and the shutter stops opening it: the entitlement is real, not a UI flag. In paywall C the yearly card starts selected, so choosing monthly proves the selection reaches the purchase | automated: TC-PAY-004-purchase-annual-entitles.yaml (Test Store on Dev; real products device-only) |
| TC-PAY-005 | P1 | account A entitled | 1. Sign out. 2. Camera → shutter. 3. Tap the CTA | The paywall is back and asks the signed-out user to sign in: access does not outlive the account | automated: TC-PAY-005-signout-regates-capture.yaml (automatable on sim) |
| TC-PAY-006 | P1 | A entitled, B never purchased | 1. Sign out of A, sign in as B. 2. Camera → shutter | B gets the offer with real prices and no "Premium access confirmed": A's purchase is not carried over | automated: TC-PAY-006-second-account-no-carryover.yaml (automatable on sim; needs accounts A and B) |
| TC-PAY-007 | P1 | paywall open, offering cannot load | 1. Open the paywall offline / with an unresolvable offering | The offer keeps its shape but tells the truth: an offline banner, plan rows marked unavailable with no price, and the subscribe action disabled with the reason ("Connect to the internet to subscribe"). **Retry** (`paywall.retry`, `id TBD on dev20` for the offer-area retry) recovers in place when the offering loads. No invented price, never a purchase that cannot complete | automatable (sim) once a seam exists; currently blocked — see *Gaps* |
| TC-PAY-008 | P1 | paywall open | 1. Tap the **X** close | The paywall closes back to the camera and no purchase state changed. The X is the only control that must never be behind a scroll | automated: TC-PAY-008-close-paywall.yaml (automatable on sim) |
| TC-PAY-009 | P1 | paywall switch on, signed out | 1. Camera → shutter. 2. Tap the CTA. 3. Read the sheet | The sign-in options are in their own full-height sheet in App Review 4.8 order: Apple (system button) first, then Google, then email; the sheet is dismissible without signing in or buying | automated: TC-PAY-009-signin-apple-first.yaml (automatable on sim) |
| TC-PAY-010 | P1 | paywall open, offering still loading | 1. Open the paywall and watch the offer area | Skeleton plan cards keep the offer's geometry and the subscribe action is present but **disabled with helper copy** ("Subscribe turns on when plans load") — never a bare spinner and never a hidden CTA | unit + automatable (sim) — `PaywallModel.phase == .loadingPlans` |
| TC-PAY-011 | P1 | purchase in flight | 1. Start a purchase, watch the surface | The CTA reads "Processing…" and stays disabled, so a second purchase cannot start from the same sheet | unit + automatable (sim) |
| TC-PAY-012 | P1 | Dev Test Store key, account B (never entitled) | 1. Subscribe. 2. "Test failed purchase". 3. Tap **Try again**. 4. Cancel the second dialog | The failure is the settled outcome: `paywall.status` reads "The purchase didn't go through", the card carries `paywall.retry`, nothing is granted, and **Try again** starts a fresh store attempt (its dialog proves it) whose cancellation leaves the user unentitled with the offer intact | automated: TC-PAY-012-purchase-failed.yaml (Test Store on Dev; device-only for a real store failure) |
| TC-PAY-013 | P1 | Dev Test Store key, account B | 1. Subscribe. 2. Cancel the store dialog | **Silence by design**: no outcome banner, no card, no retry (cancelling is the user's own answer), while the state stays true — no access, paywall still the surface, offer intact | automated: TC-PAY-013-purchase-cancelled.yaml (Test Store on Dev) |
| TC-PAY-014 | P1 | paywall open, signed in, Test Store | 1. Tap **Restore purchases**. 2. Repeat with a store that cannot answer | Restore is always present and tappable (`paywall.restore`, `id TBD on dev20`). A successful restore confirms access; a failed one says so in place ("Couldn't restore purchases") with its own Try again, instead of doing nothing. Restore never grants access without the store's answer | automatable (sim) for the wiring; **device-only** for a real entitlement being restored (TestFlight) |
| TC-PAY-015 | P1 | paywall open in any state | 1. Tap **Terms**. 2. Return, tap **Privacy** | Both are always present in the legal row and open the real documents in the browser (asserted on the documents' own text); the paywall is unchanged on return. Labels are the board's "Terms of Use" / "Privacy Policy" (`paywall.terms` / `paywall.privacy`, `id TBD on dev20`) | automated: TC-PAY-015-legal-links.yaml (automatable on sim) |
| TC-PAY-016 | P1 | paywall signed-out state, E2E account | 1. Tap the CTA. 2. Sign in from the sheet. 3. Return | After a successful sign-in the paywall resumes on the offer for that account — no dead end, no second prompt | automatable (sim) |
| TC-PAY-017 | P2 | **iPhone SE**, Dynamic Type **AX5**; and dark mode | 1. Open the paywall on an SE at AX5. 2. Scroll the offer. 3. Read the legal row | At AX5 on the smallest supported screen the plan cards, the disclosure and the **legal row (Restore · Terms · Privacy) are all reachable by scrolling and nothing is clipped or overlapped** by the pinned CTA; the X stays reachable. In dark mode every price, the saving badge and the disclosure stay legible against the surface | automated: TC-PAY-017-ax3-dark.yaml (sim-OK for reachability; device-only on a real SE at AX5) |
| TC-PAY-018 | P0 | real products (TestFlight) or Test Store (sim) | 1. Open the paywall with the offering resolved. 2. Read the yearly card, then the monthly card | The **yearly card comes first and is selected by default**, showing the store's own price and period plus a per-month breakdown; the saving badge is **computed from the two product prices** (12 × monthly vs yearly) — a different offering must show a different percentage, so "Save 33 %" or "Save 44 %" are examples, never constants. Monthly follows with its own price/period. No hardcoded price and no invented discount | **device-only:** the price/period/saving values (TestFlight, real store); **sim-OK:** card order, default selection, per-month + percentage *present* and internally consistent (Test Store prices differ and that is expected) |
| TC-PAY-019 | P0 | paywall open with an offering | 1. Read the surface from the plans to the dock. 2. Open Terms and Privacy | **App Store 3.1.2, still mandatory in paywall C:** the surface itself states the **price**, the **billing period**, that the subscription **auto-renews until cancelled**, and **how to cancel** (Apple ID settings), and both Terms of Use and Privacy Policy are present and open. All five on one surface — missing any one blocks shipping | automatable (sim) for presence/structure (`paywall.status`/disclosure ids, `id TBD on dev20`); **device-only** for the values matching the store listing |
| TC-PAY-020 | P0 | paywall open, any state | 1. Read every claim on the surface | **Shutter-only claim:** Premium is described as capture with the full pose camera and nothing more — one benefit block (`paywall.benefit`), no free shots, no daily quota, no "full pose library", no offline poses, and no second benefit promising a feature the product does not gate | automatable (sim) + unit: copy constants |
| TC-PAY-021 | P1 | signed in, paywall open | 1. Read the surface above the CTA | The app states which account the purchase will attach to (or, truthfully, that Premium follows the account) — buying against an invisible account is the failure this prevents. **`id TBD on dev20`** (`paywall.account.email` was requested and is not in source) | automatable (sim) once the id exists |

## Which claims are TestFlight/device-only, and why

- **Prices, per-month breakdown, saving percentage, period, and the store's localized currency** can only be
  read from real StoreKit products. A **Release build on a simulator resolves no products** (that is exactly
  what `docs/qa/prod-smoke` S-05b recorded as BLOCKED-BY-ENV), and a Debug-Dev Test Store build returns
  synthetic prices — so in paywall C the *structure* is asserted on the simulator (yearly first, selected,
  per-month + % shown and consistent) and the *values* are asserted on TestFlight per TC-PAY-018/019.
- **iPhone SE at AX5 and dark-mode legibility** need the hardware for the final word; the simulator can
  reproduce the content size and appearance, which is enough to prove reachability but not clipping/contrast.
- **Restoring a real purchase** needs TestFlight; the Test Store can prove the restore wiring only.

## Gaps that keep a case from being green (not app bugs)

- `TC-PAY-007` (offer unavailable/offline): no seam forces the offering to fail on a Test Store build, so the
  case is written and parked. A `-AIPosePaywallOfflineFixture`-style seam (or a TestFlight airplane-mode run)
  would make it automatable.
- `TC-PAY-014`, `TC-PAY-015`, `TC-PAY-019`, `TC-PAY-021` need ids still not in source (`paywall.restore`,
  `paywall.terms`, `paywall.privacy`, `paywall.disclosure.*`/`paywall.account.email`) — recorded here as
  `id TBD on dev20` so the flows are not built on labels that copy edits can move.

## Flows and subflows that must be re-pointed when dev20 lands

Existing files (kept untouched for now, as instructed); each needs its ids/copy checked against the committed
`PaywallScreen.swift` at the dev20 sha before it is run:

| File | What will move in paywall C |
|---|---|
| `flows/TC-PAY-001-capture-gated.yaml` | presentation (full-screen cover), presence of the X and of the disclosure line |
| `flows/TC-PAY-002-capture-ungated.yaml` | add the Settings-Premium-row absence check (kill switch) |
| `flows/TC-PAY-003-paywall-signin-prompt.yaml` | signed-out **prices now visible**; CTA → sign-in sheet; keep "never tap CTA on prod" |
| `flows/TC-PAY-004-purchase-annual-entitles.yaml` | yearly preselected by default → the monthly pick must still reach the purchase |
| `flows/TC-PAY-008-close-paywall.yaml` | X id/label (`paywall.close` expected to survive) |
| `flows/TC-PAY-009-signin-apple-first.yaml` | sheet ids/order unchanged, sheet detent full height |
| `flows/TC-PAY-012-purchase-failed.yaml` | `paywall.retry` + `paywall.status` copy |
| `flows/TC-PAY-013-purchase-cancelled.yaml` | silence assertion (no status/retry) |
| `flows/TC-PAY-015-legal-links.yaml` | `paywall.terms` / `paywall.privacy` once they exist |
| `flows/TC-PAY-017-ax3-dark.yaml` | AX5 + SE-oriented reachability, legal row scroll |
| `subflows/pay-buy-monthly.yaml` | CTA copy ("Subscribe") and the yearly-by-default selection step |
| `subflows/pay-launch.yaml`, `subflows/pay-sign-in.yaml` | shared, owner 26ab1fba — only if the launch args or sign-in route change |
| `docs/qa/prod-smoke/flows/S-05b-paywall-signed-in.yaml` | prod-config: prices/plan cards are BLOCKED-BY-ENV there; must stay CTA-untouched |

## Notes (how these run)

- Purchases stay **Test Store only on Dev builds**; on the **Prod-config build a purchase is never started** —
  flows stop at "offer visible" and never tap `paywall.cta` (that build carries the live key).
- Credentials come only from the gitignored `mobile/iosApp/maestro/e2e.local.env` via `-e`; credential flows
  carry the `e2e` tag. The App Review demo account is never used. Account **B** is the unentitled one and is
  required by TC-PAY-012/013 — account A becomes entitled as soon as TC-PAY-004 buys.
- Prices live in the plan card's accessibility label, so a flow asserts a currency-shaped value by id without
  hardcoding an amount; `paywall.status` is the outcome banner (failed / entitled) and is absent when nothing
  failed, which is how "no error shown" and "cancel is silent" are asserted.

## Accepted design deviation (GL)

- **The sign-in sheet is full height (`.large`), the board draws a medium sheet.** Accepted: a medium detent
  keeps a sheet's content out of the accessibility tree on iOS 16+/26 (that was `BUG-PAY-18-01`), so
  accessibility wins over the board. The visual pass must expect a full-height sheet and not file it.

## Requests to Feature (ids still worth adding)

| Id | Why | Used by |
|---|---|---|
| `paywall.restore` | the Restore link is only labelled | TC-PAY-014 |
| `paywall.terms`, `paywall.privacy` | legal links are label-only, and copy edits can move the label | TC-PAY-015, TC-PAY-019 |
| `paywall.disclosure.price`, `paywall.disclosure.renewal`, `paywall.disclosure.cancel` | 3.1.2 lines need stable anchors so the case cannot pass on partial copy | TC-PAY-019 |
| `paywall.offer.retry` | the offer-area Retry is only labelled "Retry loading Premium plans" | TC-PAY-007 |
| `paywall.account.email` | the identity line | TC-PAY-021 |
