# Paywall and purchase (FEAT-011) — **paywall C**, target 1.1 (20) / 1.2.x

Business behaviour of the paid surface: what the user is offered, what the app may claim about it, and what
happens while the App Store is talking. Premium unlocks **capture with the full pose camera** and nothing
else — no free first capture, no quota, no offline library — and a purchase is account-bound, so a signed-out
user is asked to sign in before buying.

Spec: `~/ai-pose-work/paywall-cro/handoff-1.2.md` + `mockups/variant-c-v2.png` (target) and
`mockups/variant-a-signed-out.png` (the signed-out treatment). Rationale in `report.md`; the repo-side spec
will land as `docs/design-reference/paywall-c/README.md`. Confirmed product numbers from App Store Connect:
**$5.99 monthly, $39.99 yearly** — but the UI must always read prices from the store, never hard-code them.

**Id policy.** Ids below are the ones Feature promised for paywall C. Existing ids are **not** renamed, so
ids that already exist keep their spelling. Where a promised id differs from what is committed today
(`paywall.plan.yearly` vs today's `paywall.plan.annual`), the row names the promised id and says so — and
**every id must be confirmed against `docs/design-reference/paywall-c/README.md` / the committed
`PaywallScreen.swift` when that lands**; if the committed spelling differs, the flow follows the source, not
this table.

**Two kinds of assertion below:** *Sim* = provable on a Debug-Dev simulator with the Test Store key
(structure, order, wiring, state machines); *Device* = needs the TestFlight build or a physical iPhone SE,
because a Release build on a simulator resolves no StoreKit products and SE/AX5 geometry is hardware.

## Variant C, top to bottom (the order is part of the case)

1. **Hero** (full bleed, fades into the background) with a pose outline; **X close, top right, 44 pt, in the
   first frame** — never delayed, never hidden, and never a discount trap.
2. **Headline**: "Pick a pose. Match it. Shoot."
3. **Three steps**: "Pick a pose / Browse and save poses for free." · "Match the outline / The guide shows on
   your live camera." · "Shoot / Premium unlocks the shutter with the full pose camera."
4. **Plan cards**, store-derived values only, **yearly preselected**: Yearly — "Save N%" badge (computed from
   the two products), "{per-month} per month, billed {price} yearly", price right; Monthly — "Billed monthly",
   price right. Selecting a plan updates the helper line.
5. **Renewal sentence**: "Renews automatically until you cancel in Apple ID settings."
6. **Helper line above the CTA**: "Yearly plan • {price} billed today", following the selection.
7. **CTA**: **"Unlock the pose camera"**. Signed out: **"Sign in to subscribe"**, with prices still shown
   (open decision 2 defaults to yes; if it flips to "no", prices read "—" and only signed-in cohorts are
   measured).
8. **Legal row, always visible, never scrolled away**: Restore purchases · Terms of Use · Privacy Policy.

Not in C (and therefore not assertable as a feature): timers, scarcity, ratings/testimonials, a trial claim,
a hidden/delayed X, or a discount after close.

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-PAY-001 | P0 | `paywall_enabled` on, signed out | 1. Launch. 2. Camera → shutter | The paywall opens as a full-screen cover over the camera and the press captures nothing. The whole C order is present in one screen-height-aware scroll: hero, headline, three steps, plan section with **yearly selected by default**, renewal sentence, helper line, CTA, and the legal row. **The X is visible in the first frame at 44 pt** and nothing of the camera is interactive behind the cover | automated: TC-PAY-001-capture-gated.yaml (automatable on sim; re-point to C ids on dev20) |
| TC-PAY-002 | P0 | `paywall_enabled` **off** | 1. Launch with the switch off. 2. Camera → shutter. 3. Settings → Library | The kill switch is a real rollback: no paywall from the shutter, **no Premium row** in Settings, and no route into the surface. Greyed-out or partially rendered C must not appear | automated: TC-PAY-002-capture-ungated.yaml (extend with the Settings absence check) |
| TC-PAY-003 | P1 | `paywall_enabled` on, signed out | 1. Camera → shutter. 2. Read the plan cards. 3. Tap the CTA | **Prices are visible while signed out** (decision 2 default), so the offer is honest before signing in; the CTA reads **"Sign in to subscribe"** and opens the full-height sign-in sheet (Apple → Google → email). **Never tap the CTA on a prod-config build** — there it is a live purchase path | automated: TC-PAY-003-paywall-signin-prompt.yaml |
| TC-PAY-004 | P1 | account A signed in, Dev Test Store key | 1. Open the paywall. 2. Select monthly. 3. Tap **"Unlock the pose camera"**. 4. "Test valid purchase" | Access is granted ("Premium access confirmed"), the paywall closes itself and the shutter stops opening it. Yearly starts selected, so picking monthly proves the selection reaches the purchase and the helper line followed it | automated: TC-PAY-004-purchase-annual-entitles.yaml |
| TC-PAY-005 | P1 | account A entitled | 1. Sign out. 2. Camera → shutter. 3. Read the CTA | The paywall is back as the signed-out state — prices shown, CTA **"Sign in to subscribe"** — because access does not outlive the account | automated: TC-PAY-005-signout-regates-capture.yaml |
| TC-PAY-006 | P1 | A entitled, B never purchased | 1. Sign out of A, sign in as B. 2. Camera → shutter | B gets the full C offer with store prices and no entitlement banner: A's purchase is not carried over | automated: TC-PAY-006-second-account-no-carryover.yaml |
| TC-PAY-007 | P1 | paywall open, offering cannot load | 1. Open the paywall with an unresolvable offering (offline) | The offer keeps its shape and tells the truth: an offline banner, plan rows without prices, and the CTA disabled with the reason ("Connect to the internet to subscribe"). **Retry** (`paywall.offer.retry`) recovers in place once the offering loads. No invented price, never a purchase that cannot complete | automatable (sim) once a seam exists; blocked today — see *Gaps* |
| TC-PAY-008 | P1 | paywall open | 1. Tap the **X** | Closes back to the camera, no purchase state changed. The X is in the first frame (never below the fold) and is the control that must never require a scroll | automated: TC-PAY-008-close-paywall.yaml |
| TC-PAY-009 | P1 | `paywall_enabled` on, signed out | 1. Camera → shutter. 2. Tap "Sign in to subscribe". 3. Read the sheet | The sign-in options are in their own full-height sheet in App Review 4.8 order: Apple (system button) first, then Google, then email; dismissible without signing in or buying | automated: TC-PAY-009-signin-apple-first.yaml |
| TC-PAY-010 | P1 | paywall open, offering still loading | 1. Open the paywall and watch the plan area | Skeleton plan cards keep the offer's geometry and the CTA is present but **disabled with helper copy** ("Subscribe turns on when plans load") — never a bare spinner, never a hidden or silently dead CTA | unit + automatable (sim) — `PaywallModel` `.loadingPlans` |
| TC-PAY-011 | P1 | purchase in flight | 1. Start a purchase and watch the surface | The CTA reads "Processing…" and stays disabled, so a second purchase cannot start from the same sheet | unit + automatable (sim) |
| TC-PAY-012 | P1 | Dev Test Store key, account B (never entitled) | 1. Subscribe. 2. "Test failed purchase". 3. Tap **Try again**. 4. Cancel the second dialog | The failure is the settled outcome: `paywall.status` reads "The purchase didn't go through", the card carries `paywall.retry`, nothing is granted, and **Try again** starts a fresh store attempt (its dialog proves it); cancelling that leaves the user unentitled with the offer intact | automated: TC-PAY-012-purchase-failed.yaml |
| TC-PAY-013 | P1 | Dev Test Store key, account B | 1. Subscribe. 2. Cancel the store dialog | **Silence by design**: no outcome banner, no card, no retry (cancelling is the user's own answer), while the state stays true — no access, paywall still the surface, offer intact | automated: TC-PAY-013-purchase-cancelled.yaml |
| TC-PAY-014 | P1 | paywall open, signed in, real or Test Store | 1. Tap **Restore purchases** (`paywall.restore`). 2. Repeat with a store that cannot answer | Restore is always visible in the legal row and responds: a successful restore confirms access, a failed one says so in place with its own Try again. Restore never grants access without the store's answer, and it must not be pushed below the fold | wiring automatable (sim); a real restore is **device-only** (TestFlight) |
| TC-PAY-015 | P1 | paywall open in any state | 1. Tap **Terms of Use** (`paywall.terms`). 2. Return, tap **Privacy Policy** (`paywall.privacy`) | Both are always visible in the legal row and open the real documents in the browser (asserted on the documents' own text); the paywall is unchanged on return | automated: TC-PAY-015-legal-links.yaml (automatable on sim) |
| TC-PAY-016 | P1 | paywall signed-out state, E2E account | 1. Tap "Sign in to subscribe". 2. Sign in from the sheet. 3. Return | After a successful sign-in the paywall resumes on the offer for that account (yearly still preselected, prices from the store) — no dead end, no second prompt | automatable (sim) |
| TC-PAY-017 | P2 | **iPhone SE**, Dynamic Type **AX5**; and dark mode | 1. Open the paywall on an SE at AX5. 2. Scroll the content. 3. Read the purchase region | At AX5 on the smallest supported screen the plan cards, the renewal sentence, the helper line and the **legal row (Restore · Terms · Privacy) are all reachable by scrolling, and the purchase region stays fixed and unclipped**; the X stays reachable. Headline must not leave a one-word orphan line. In dark mode prices, the saving badge and the renewal sentence stay legible against the surface, and the status bar stays legible over the hero (scrim/light style) | automated: TC-PAY-017-ax3-dark.yaml (sim-OK for reachability; device-only on a real SE at AX5) |
| TC-PAY-018 | P0 | real products (TestFlight) or Test Store (sim) | 1. Open the paywall with the offering resolved. 2. Read the yearly card, then select monthly and read the helper line | The **yearly card is first and preselected**, showing "{per-month} per month, billed {price} yearly" (`paywall.plan.yearly.permonth`) plus a **"Save N%" badge computed from the two products** (`paywall.plan.yearly.savings`) — 12 × monthly vs yearly, so with $5.99/$39.99 it reads 44 %, and any other offering must produce a different number. Monthly shows "Billed monthly" and its price. Selecting a plan flips the observable selected state and updates the helper line ("Yearly plan • $39.99 billed today" ⇄ the monthly equivalent). No hard-coded price, no invented discount | **device-only:** the values (TestFlight); **sim-OK:** card order, preselection, selected-state flips, per-month + badge present and internally consistent (Test Store prices differ, and that is expected) |
| TC-PAY-019 | P0 | paywall open with an offering | 1. Read the surface from the plan cards to the legal row. 2. Open Terms and Privacy | **App Store 3.1.2, all five on one surface:** price and billing period on each card, the **renewal sentence always visible** ("Renews automatically until you cancel in Apple ID settings"), the **cancel instruction** it contains, and Terms of Use + Privacy Policy present and opening. Missing any one blocks shipping | automatable (sim) for presence/order (`paywall.disclosure.autoRenew`/`.cancel`/`.price`, `paywall.terms`, `paywall.privacy`); **device-only** for the values matching the App Store listing |
| TC-PAY-020 | P0 | paywall open, any state | 1. Read every claim on the surface | **Shutter-only claim:** the steps say browse/save poses are free and that **Premium unlocks the shutter with the full pose camera** — one promise, one gate. No free first capture, no quota, no "full pose library", no offline poses, no second benefit promising something the product does not gate | automatable (sim) + unit: copy constants |
| TC-PAY-021 | P1 | signed in, paywall open | 1. Read the surface above the CTA | The app states which account the purchase is attached to (`paywall.account.email`, or the truthful "Premium follows your account" line) — buying against an invisible account is the failure this prevents | automatable (sim) once the id exists |

## Sim-OK vs TestFlight/device-only

- **Prices, per-month breakdown, saving percentage, period and localized currency** come from real StoreKit
  products. A Release build on a simulator resolves none (that is `docs/qa/prod-smoke` S-05b's
  BLOCKED-BY-ENV), and a Debug-Dev Test Store build returns synthetic prices — so the *structure* (order,
  preselection, badge present, helper line following the selection, consistency between the two prices) is
  asserted on the simulator, and the *values* on TestFlight per TC-PAY-018/019.
- **iPhone SE at AX5, clipping, hero/status-bar contrast and dark-mode legibility** need the hardware for the
  final word; the simulator reproduces content size and appearance, which proves reachability only.
- **Restoring a real purchase** needs TestFlight; Test Store proves the wiring.
- **Not assertable by Maestro at all** (so no case pretends to): the A/B assignment (`paywall_variant`
  control|c, 50/50 sticky per install), and the Firebase events (`paywall_view`, `paywall_plan_select`,
  `paywall_cta_tap`, `paywall_close`, `paywall_restore_tap`, `purchase_success`,
  `purchase_cancel`/`purchase_fail`). Stickiness and the kill-switch interaction are unit tests; event
  delivery is an analytics check, not a UI one. Variant `control` must remain byte-for-byte today's paywall,
  which means C's cases only run against `variant = c`.

## Hard gate before the flag is ever on in production

`paywall_enabled` must not be enabled until Terms, Privacy, `docs/app-store-publish/app-store-metadata.md` and
the App Privacy labels are updated (handoff "Decision 1"). QA treats a production flag-on with stale legal
pages as a release blocker, and TC-PAY-019 is where it would be caught.

## Gaps that keep a case from being green (not app bugs)

- `TC-PAY-007` (offer unavailable/offline) has no seam that forces the offering to fail on a Test Store build
  — parked. An offline fixture (or a TestFlight airplane-mode run) would make it automatable.
- `TC-PAY-014/015/019/021` wait on ids (`paywall.restore`, `paywall.terms`, `paywall.privacy`,
  `paywall.disclosure.*`, `paywall.account.email`) — promised by Feature, named above, still to appear in
  committed source.

## Flows and subflows to re-point when the C build lands

Files stay untouched until then; each needs its ids/copy checked against `PaywallScreen.swift` at that sha:

| File | What moves under paywall C |
|---|---|
| `flows/TC-PAY-001-capture-gated.yaml` | cover presentation, hero/steps presence, X in the first frame |
| `flows/TC-PAY-002-capture-ungated.yaml` | add the Settings-Premium-absence check (kill switch) |
| `flows/TC-PAY-003-paywall-signin-prompt.yaml` | CTA copy ("Sign in to subscribe"), prices visible when signed out |
| `flows/TC-PAY-004-purchase-annual-entitles.yaml` | CTA "Unlock the pose camera"; yearly preselected → monthly pick must still reach the purchase; helper line |
| `flows/TC-PAY-005-signout-regates-capture.yaml` | signed-out CTA copy |
| `flows/TC-PAY-008-close-paywall.yaml` | X id/label (`paywall.close` expected to survive) |
| `flows/TC-PAY-009-signin-apple-first.yaml` | unchanged order, full-height sheet |
| `flows/TC-PAY-012-purchase-failed.yaml` | `paywall.retry` + `paywall.status` copy |
| `flows/TC-PAY-013-purchase-cancelled.yaml` | silence assertion (no status/retry) |
| `flows/TC-PAY-015-legal-links.yaml` | `paywall.terms` / `paywall.privacy` |
| `flows/TC-PAY-017-ax3-dark.yaml` | AX5 + SE reachability, legal row scroll, hero/status-bar contrast |
| `subflows/pay-buy-monthly.yaml` | CTA copy + the yearly-by-default selection step |
| `subflows/pay-launch.yaml`, `subflows/pay-sign-in.yaml` | shared (owner 26ab1fba) — only if launch args or the sign-in route change |
| `docs/qa/prod-smoke/flows/S-05b-paywall-signed-in.yaml` | prod-config stays CTA-untouched; prices remain BLOCKED-BY-ENV there |

## Notes (how these run)

- Purchases stay **Test Store only on Dev builds**; on the **Prod-config build a purchase is never started**
  — flows stop at "offer visible" and never tap `paywall.cta`.
- Credentials come only from the gitignored `mobile/iosApp/maestro/e2e.local.env` via `-e`; those flows carry
  the `e2e` tag. Account **B** is the unentitled one (TC-PAY-012/013) — account A becomes entitled as soon as
  TC-PAY-004 buys.
- `paywall.status` is the outcome banner (failed / entitled) and is absent when nothing failed, which is how
  "no error shown" and "cancel is silent" are asserted.
- Reduce Motion: the single-hero C has no motion; if the outline-draw hero ever lands, Reduce Motion must
  show its final frame (device-only check).

## Accepted design deviation (GL)

- **The sign-in sheet is full height (`.large`)**, where the board draws a medium sheet: a medium detent keeps
  a sheet's content out of the accessibility tree on iOS 16+/26 (that was `BUG-PAY-18-01`), so accessibility
  wins. The visual pass must not file it.

## Ids promised by Feature for C (confirm against committed source)

`paywall.close` · `paywall.cta` · `paywall.plan.yearly` · `paywall.plan.monthly` ·
`paywall.plan.yearly.permonth` · `paywall.plan.yearly.savings` · `paywall.restore` · `paywall.terms` ·
`paywall.privacy` · `paywall.disclosure.*` · `paywall.account.email` · `paywall.offer.retry` · plus the
existing `paywall.status`, `paywall.retry`, `paywall.benefit`, `paywall.notice`, `paywall.offline`,
`paywall.signin.sheet`, `paywall.signin.close`, `paywall.signin.apple`, `paywall.signin`,
`signin.emailEntry` (not renamed).

**Confirm all of the above vs `docs/design-reference/paywall-c/README.md` when that lands** (and against the
committed `PaywallScreen.swift`): if the committed spelling for the yearly card is still `paywall.plan.annual`,
the flows follow the source and this table is corrected in the same commit.
