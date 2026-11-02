# Paywall and purchase (FEAT-011) — **paywall C**, build 1.1 (20)

Business behaviour of the paid surface: what the user is offered, what the app may claim about it, and what
happens while the App Store is talking. Premium unlocks **capture with the full pose camera** and nothing
else — no free first capture, no quota, no offline library — and a purchase is account-bound, so a signed-out
user is asked to sign in before buying.

Source of truth: **`docs/design-reference/paywall-c/README.md`** (layout, copy, states, ids), cross-checked
against the committed `PaywallScreen.swift` / `PaywallModel.swift` at `1256c4f` with `git grep`. Every id
below was verified present in that source. Two things are worth stating up front because they were carried
from the earlier CRO handoff and are **not** what shipped:

- **There is no A/B arm.** The shipped paywall replaces the old body for *everyone*: no `paywall_variant`, no
  control layout, no stickiness to test. `paywall_enabled` is still the only switch, default **off**. So no
  case, flow or analytics expectation exists for a variant split.
- **A cancelled purchase is not silent.** The README's state table and `PaywallModel.statusMessage`
  (`PaywallModel.swift:473`) both put **"Purchase cancelled. No access was granted."** on the status line.
  What a cancel does *not* get is an error card and a retry. (`TC-PAY-013` below is written that way; the
  current committed flow still asserts total silence and must be flipped when it is re-pointed.)

**Two kinds of assertion:** *Sim* = provable on a Debug-Dev simulator with the Test Store key (structure,
order, wiring, states); *Device* = needs TestFlight or a physical iPhone SE (a Release build on a simulator
resolves no StoreKit products; SE geometry, real status bar and VoiceOver are hardware).

## Layout order (top → bottom) — **build 21 compact**

| # | Block | On screen | Notes |
|---|---|---|---|
| 1 | Hero photo, full bleed under the status bar, top scrim + bottom fade, no motion | first frame | Height is the 0.28 share of the container, capped so everything below still fits one screen: `min(0.28 × container, container − 527)`, clamped 118–312 pt — 261 pt on a 932 pt container, ~150 on a 6.1", **~120 on an SE** |
| 2 | Close X, 44 pt, top-trailing | **first frame, never delayed** | the only way out of the cover |
| 3 | Headline "Pick a pose." + "Match it. Shoot." (two fragments) | first frame | no one-word orphan at 375 pt |
| 4 | Numbered steps 1–3, **one line each** at caption size · 1 "Pick a pose — Browse and save poses for free." · 2 "Match the outline — The guide shows on your live camera." · 3 "Shoot — Premium unlocks the shutter with the full pose camera." | **first frame at the default size**, scrolls at AX | steps 1–2 free, step 3 paid (`paywall.benefit` sits on it) |
| 5 | Plan cards: Yearly (preselected) + Monthly | **both on the first screen** | Yearly: "Save N%" + "{perMonth} per month, billed {price} yearly"; Monthly: **"Billed {price} monthly"** — each card states its own amount and period (3.1.2) |
| 6 | Offer error card (load/purchase failure only) | scrolls | title + message + one action |
| 7 | Renewal sentence "Renews automatically until you cancel in Apple ID settings." | **first frame at the default size** (pinned at AX) | the one auto-renew sentence on the surface |
| 8 | Legal row: Restore purchases · Terms of Use · Privacy Policy | **pinned in the dock** below AX; at AX1–AX5 it moves into the scroll (accepted) | never truncated, never painted over |
| 9 | Status / outcome line (`paywall.status`) | scrolls | cancelled / failed / entitled copy |
| 10 | Pinned purchase region: **account line → CTA (48 pt) → legal row** | **always** | **build 21 removed the selected-plan summary line**: the amount and period live on the cards, and `paywall.disclosure.selection` now carries only blocker copy (offline / not-loaded) |

Copy verbatim: CTA `Unlock the pose camera` (signed in) / `Sign in to subscribe` (signed out) / `Try again`
(failed purchase) / `Plans unavailable` (offering unreadable); account line **"Signed in. Premium follows your
account."** (signed in) / **"Sign in first so Premium follows you."** (signed out); no price above the CTA.

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-PAY-001 | P0 | `paywall_enabled` on, signed out | 1. Launch. 2. Camera → shutter | The paywall opens as a full-screen cover over the camera and the press captures nothing. The whole C structure is there in the documented order: hero painted with the status bar readable over it, **X in the first frame at 44 pt**, headline in two fragments, steps 1–3, plan cards, renewal sentence, pinned helper + CTA and the legal row. `paywall.steps` and the **paid step 3** (`paywall.benefit`) — present on the first frame at the default size per build 21, but always *reached by scrolling* in the flow, because a shorter device or a large hero can push them below the fold. Both cards, the auto-renew sentence, the signed-out account line ("Sign in first so Premium follows you."), the legal row and the CTA are asserted on the same screen. Nothing of the camera is interactive behind the cover | automated: TC-PAY-001-capture-gated.yaml (automatable on sim; re-point to C ids) |
| TC-PAY-002 | P0 | `paywall_enabled` **off** (the default) | 1. Launch with the switch off. 2. Camera → shutter. 3. Settings → Library | The switch is the only lever and a real rollback: no paywall from the shutter, **no Premium row** in Settings, no route into the surface. No partially rendered C | automated: TC-PAY-002-capture-ungated.yaml (automatable on sim; add the Settings-absence check) |
| TC-PAY-003 | P1 | `paywall_enabled` on, signed out | 1. Camera → shutter. 2. Read the cards. 3. Tap the CTA | The cards show the **real store prices even signed out** (the offering is read before sign-in) and the line above the CTA asks for the account — `paywall.account.status` = **"Sign in first so Premium follows you."** (build 21: the selected-plan summary line is gone, so this is the account line, not a purchase line); the CTA is **"Sign in to subscribe"** and opens the full-height sign-in sheet (Apple → Google → email) — never a guest purchase. Sub-state to expect if the offering has not landed yet: cards keep their shape with "—" and "Price unavailable" while the CTA stays "Sign in to subscribe". **Never tap the CTA on a prod-config build** | automated: TC-PAY-003-paywall-signin-prompt.yaml (automatable on sim) |
| TC-PAY-004 | P1 | account A signed in, Dev Test Store key | 1. Open the paywall. 2. Select monthly. 3. Tap "Unlock the pose camera". 4. "Test valid purchase" | Access is granted ("Premium access confirmed."), the cover then closes itself and the shutter stops opening it. Yearly is preselected, so choosing monthly must flip the card's own selected state (`paywall.plan.monthly` value `selected`, annual back to `not selected`) and reach the purchase — build 21 has no summary line to follow the selection | automated: TC-PAY-004-purchase-annual-entitles.yaml (Test Store on Dev; real products device-only) |
| TC-PAY-005 | P1 | account A entitled | 1. Sign out. 2. Camera → shutter. 3. Read the CTA | The paywall is back in its signed-out state — real prices, CTA "Sign in to subscribe" — because access does not outlive the account | automated: TC-PAY-005-signout-regates-capture.yaml (automatable on sim) |
| TC-PAY-006 | P1 | A entitled, B never purchased | 1. Sign out of A, sign in as B. 2. Camera → shutter | B gets the full offer with store prices and **no** "Premium access confirmed.": A's purchase is not carried over | automated: TC-PAY-006-second-account-no-carryover.yaml (automatable on sim; needs accounts A and B) |
| TC-PAY-007 | P1 | paywall open, offering cannot be read | 1. Open the paywall with the offering failing. 2. Try again from the card | "Offer failed / unavailable": an **offer error card** with title, message and one action — `paywall.offer.retry` — while the CTA is **disabled and reads "Plans unavailable"**. Retrying loads the real offering in place; no invented price, never a purchase that cannot complete. (Offline is its own row of the state table: offline banner `paywall.offline` on the cards + helper "Connect to the internet to subscribe.", CTA disabled) | automatable (sim) once a failure seam exists; blocked today — see *Gaps* |
| TC-PAY-008 | P1 | paywall open | 1. Tap the X | Closes back to the camera, no purchase state changed. The X is in the first frame at 44 pt (never below the fold) and is the only exit — the cover has no swipe-away alternative | automated: TC-PAY-008-close-paywall.yaml (automatable on sim) |
| TC-PAY-009 | P1 | `paywall_enabled` on, signed out | 1. Camera → shutter. 2. Tap "Sign in to subscribe". 3. Read the sheet | The options are in their own **full-height** sheet in App Review 4.8 order: Apple (system button) first, then Google (`paywall.signin`), then email (`signin.emailEntry`); the sheet is dismissible (`paywall.signin.close`) without signing in or buying | automated: TC-PAY-009-signin-apple-first.yaml (automatable on sim) |
| TC-PAY-010 | P1 | paywall open, offering still loading (signed in) | 1. Open the paywall and watch the card area | **Skeleton cards keep the offer's geometry**, the helper line reads "Subscribe turns on when plans load." and the CTA keeps its label but is **disabled** — never a bare spinner, never a hidden or silently dead button | unit + automatable (sim) — `PaywallModel` `.loadingPlans` |
| TC-PAY-011 | P1 | purchase or restore in flight | 1. Start a purchase, watch the purchase region | The CTA **keeps its label with a spinner** and is disabled, so a second purchase cannot start from the same sheet | unit + automatable (sim) |
| TC-PAY-012 | P1 | Dev Test Store key, account B (never entitled) | 1. Subscribe. 2. "Test failed purchase". 3. Tap **Try again**. 4. Cancel the second dialog | The failure is the settled outcome: the **offer error card** appears with `paywall.retry` as its action, the **status line** carries "The purchase didn't go through", the CTA itself reads "Try again", and nothing is granted. Tapping retry starts a fresh store attempt (its dialog proves it); cancelling that leaves the user unentitled with the offer intact | automated: TC-PAY-012-purchase-failed.yaml (automatable on sim; Test Store) |
| TC-PAY-013 | P1 | Dev Test Store key, account B | 1. Subscribe. 2. Cancel the store dialog | A cancel is **reported but not punished**: the status line shows **"Purchase cancelled. No access was granted."**, while there is **no offer error card and no retry** (a retry would scold the user for their own decision). No access granted; CTA back to "Unlock the pose camera"; offer intact | automated: TC-PAY-013-purchase-cancelled.yaml (automatable on sim; flow must flip from "no status at all" to "status line, no card/retry") |
| TC-PAY-014 | P1 | paywall open, signed in, real or Test Store | 1. Tap **Restore purchases** (`paywall.restore`). 2. Repeat with a store that cannot answer | Restore is in the legal row (pinned in the dock below AX sizes, in the scroll at AX1–AX5) and always reachable; it responds — a successful restore confirms access, a restore that fails produces the error card with `paywall.retry` — and it never grants access without the store's answer | wiring automatable (sim); a real restore is **device-only** (TestFlight) |
| TC-PAY-015 | P1 | paywall open in any state | 1. Tap **Terms of Use** (`paywall.terms`). 2. Return, tap **Privacy Policy** (`paywall.privacy`) | Both sit in the legal row with Restore, never truncated or painted over, and open the real documents in the browser (asserted on the documents' own text); the paywall is unchanged on return | automated: TC-PAY-015-legal-links.yaml (automatable on sim) |
| TC-PAY-016 | P1 | paywall signed-out state, E2E account | 1. Tap "Sign in to subscribe". 2. Sign in from the sheet. 3. Return | After a successful sign-in the paywall resumes on the offer for that account (yearly still preselected, real prices, account line "Signed in. Premium follows your account.") — no dead end, no second prompt | automatable (sim) |
| TC-PAY-017 | P2 | **iPhone SE 375×667**, `.large`/`.xxxLarge`, **AX1–AX5**; and dark mode | 1. Open the paywall on an SE. 2. At `.large` read the purchase region. 3. At AX3/AX5 scroll the content. 4. Repeat in dark mode | At `.large`/`.xxxLarge` on an SE the **X, CTA, both cards and the legal row are all inside the frame** (no clipping; build 21's whole point). At AX1–AX5 the **account line + CTA stay pinned and tappable**, the close stays visible, and the steps, the cards, the auto-renew sentence and the legal row all move into the scroll — every one of them reachable by scrolling, nothing truncated. Status-bar glyphs stay ≥4.5:1 over the hero in both schemes; dark mode paints from the tokens and the prices/badge/renewal stay legible. Headline never leaves a one-word orphan line | automated: TC-PAY-017-ax3-dark.yaml (sim-OK: reachability and order at content_size accessibility-extra-extra-extra-large + appearance dark; device-only: the real notch/status bar, actual scroll reachability and VoiceOver order. Layout math is already pinned by PaywallScreenLayoutTests (SE/.xxxLarge frame scan, AX pinned CTA, scrim contrast, dark tokens)) |
| TC-PAY-018 | P0 | real products (TestFlight) or Test Store (sim) | 1. Open the paywall with the offering resolved. 2. Read the yearly card, then select monthly and read the helper line | **Yearly first and preselected** (catalog order, not a constant), showing `{perMonth} per month, billed {price} yearly` (`paywall.plan.yearly.permonth`) and a **"Save N%" badge computed from the two real prices** (`paywall.plan.yearly.savings`) — with $5.99/$39.99 that is 44 %, and any other offering must produce a different number. Monthly shows "Billed monthly" and its price. Selecting a card flips its exposed `selected` value (and the `isSelected` trait); there is no summary line to move any more, and the card states its own billed amount and period (Monthly now reads "Billed {price} monthly"). **No price or percentage is typed into the code** — when the store values cannot be parsed the card degrades to "Billed yearly/monthly" and shows **no badge** | **device-only:** the values (TestFlight); **sim-OK:** order, preselection, selected-state flips, per-month + badge present and consistent (Test Store prices differ — expected) |
| TC-PAY-019 | P0 | paywall open with an offering | 1. Read the surface from the cards to the legal row. 2. Open Terms and Privacy | **App Store 3.1.2, all five on one surface:** price and **billing period on each card** (Yearly: "{perMonth} per month, billed {price} yearly"; Monthly: "Billed {price} monthly"), the renewal sentence **always visible** (`paywall.disclosure.autoRenew` — "Renews automatically until you cancel in Apple ID settings."), the cancel instruction inside it, and Terms of Use + Privacy Policy present and opening. Build 21 removed the summary line above the CTA, so the money/period disclosure lives entirely on the cards. Missing any one blocks shipping | automatable (sim) for presence/copy/order; **device-only** for the values matching the App Store listing |
| TC-PAY-020 | P0 | paywall open, any state | 1. Read the steps and every claim | **Shutter-only claim:** steps 1–2 are free ("Browse and save poses for free.", "The guide shows on your live camera.") and **only step 3 is paid** — "Premium unlocks the shutter with the full pose camera" (`paywall.benefit`). No free first capture, no quota, no "full pose library", no offline poses, no trial claim, no scarcity/ratings/timers, and no close-to-discount | automatable (sim) + unit: copy constants |
| TC-PAY-021 | P1 | paywall open, signed in and signed out | 1. Read the line above the CTA in both states | The line above the CTA tells the truth (`PaywallScreen.footerLine`): **"Signed in. Premium follows your account."** when signed in, **"Sign in first so Premium follows you."** when the purchase is blocked by the session — both on `paywall.account.status`. Blocker copy (offline / offering not loaded) takes that slot via `paywall.disclosure.selection`. It never prints an email address: the app has none, and a fabricated identity line is the failure this prevents | automatable (sim) |

## Sim-OK vs TestFlight/device-only

- **Prices, per-month breakdown, saving percentage, period and localized currency** come from real StoreKit
  products. A Release build on a simulator resolves none (that is `docs/qa/prod-smoke` S-05b's
  BLOCKED-BY-ENV); a Debug-Dev Test Store build returns synthetic prices — so *structure* (order,
  preselection, badge present, helper follows selection, internal consistency of the two prices) is asserted
  on the simulator and *values* on TestFlight per TC-PAY-018/019.
- **SE geometry, real status bar/notch, VoiceOver order and dark-mode legibility** need the hardware. The
  simulator reproduces content size and appearance, which proves reachability only; the frame-level math is
  already covered by `PaywallScreenLayoutTests`.
- **Restoring a real purchase** needs TestFlight; Test Store proves the wiring.

## Gaps that keep a case from being green (not app bugs)

- `TC-PAY-007` (offer unavailable) has no seam that forces the offering to fail on a Test Store build, so it
  is written and parked; an offline/unavailable fixture (or a TestFlight airplane-mode run) would make it
  automatable.
- All ids used above are present in committed source. Nothing on this screen is waiting on a new id.

## Flows and subflows to re-point on the C build

**Re-pointed ahead of dev20** (ids verified in committed source at `1256c4f`; verification on the build is
still pending, so treat them as staged, not proven): `TC-PAY-001`, `002`, `003`, `004`, `008`, `009`, `012`,
`013`, `015`, `017`, `subflows/pay-buy-monthly.yaml` and `docs/qa/prod-smoke/flows/S-05b-paywall-signed-in.yaml`.
`pay-launch.yaml` / `pay-sign-in.yaml` needed no change (the Debug switches and the Settings → Account →
email route still hold). The table below is kept as the record of what moved:

| File | What moves under paywall C |
|---|---|
| `flows/TC-PAY-001-capture-gated.yaml` | cover presentation, hero/steps (`paywall.steps`, `paywall.benefit` on step 3), X in the first frame |
| `flows/TC-PAY-002-capture-ungated.yaml` | add the Settings-Premium-absence check (kill switch) |
| `flows/TC-PAY-003-paywall-signin-prompt.yaml` | CTA copy "Sign in to subscribe", real prices while signed out, "—"/"Price unavailable" sub-state |
| `flows/TC-PAY-004-purchase-annual-entitles.yaml` | CTA "Unlock the pose camera"; yearly preselected → monthly pick flips the card states (no summary line on build 21) |
| `flows/TC-PAY-005-signout-regates-capture.yaml` | signed-out CTA copy |
| `flows/TC-PAY-008-close-paywall.yaml` | X id/label (`paywall.close` survives) |
| `flows/TC-PAY-009-signin-apple-first.yaml` | unchanged order, full-height sheet |
| `flows/TC-PAY-012-purchase-failed.yaml` | error card + `paywall.retry` + status line + CTA reading "Try again" |
| `flows/TC-PAY-013-purchase-cancelled.yaml` | **must flip**: status line "Purchase cancelled. No access was granted." present, no card and no retry (today the flow asserts no status at all) |
| `flows/TC-PAY-015-legal-links.yaml` | `paywall.terms` / `paywall.privacy` in the legal row |
| `flows/TC-PAY-017-ax3-dark.yaml` | SE `.large` frame check + AX5 legal-row-in-scroll |
| `subflows/pay-buy-monthly.yaml` | CTA copy + the yearly-by-default selection step |
| `subflows/pay-launch.yaml`, `subflows/pay-sign-in.yaml` | shared (owner 26ab1fba) — only if launch args or the sign-in route change |
| `docs/qa/prod-smoke/flows/S-05b-paywall-signed-in.yaml` | prod-config stays CTA-untouched; prices stay BLOCKED-BY-ENV there |

## Notes (how these run)

- Purchases stay **Test Store only on Dev builds**; on the **Prod-config build a purchase is never started** —
  flows stop at "offer visible" and never tap `paywall.cta`.
- Credentials come only from the gitignored `mobile/iosApp/maestro/e2e.local.env` via `-e`; those flows carry
  the `e2e` tag. `subflows/pay-sign-in.yaml` scrolls `signin.emailEntry` into view before tapping it, because
  at accessibility text sizes the Account card fills the screen. Account **B** is the unentitled one (TC-PAY-012/013) — account A becomes entitled as soon as
  TC-PAY-004 buys.
- `paywall.status` carries the outcome (cancelled / failed / entitled) and is absent when nothing happened,
  which is how "no error" is asserted — **except** that a cancel does write its status line.
- Reduce Motion: the hero has no motion in this build, so there is nothing to freeze.

## Accepted design deviations (GL)

- **The sign-in sheet is full height (`.large`)**, where the board draws a medium sheet: a medium detent keeps
  a sheet's content out of the accessibility tree on iOS 16+/26 (that was `BUG-PAY-18-01`), so accessibility
  wins. The visual pass must not file it.
- **At AX1–AX5 the legal row leaves the dock and moves into the scroll** (README §8). At `.large`/`.xxxLarge`
  it is pinned. Both are intended; the case asserts reachability, not a fixed position.

## Ids (verified in committed source, `1256c4f`)

`paywall.close` · `paywall.cta` · `paywall.steps` · `paywall.benefit` (step 3) · `paywall.plan.annual` (the
yearly card — deliberately **not** `plan.yearly`, so existing flows keep working; its selection is exposed as
the card's `selected` value + `isSelected` trait) · `paywall.plan.monthly` · `paywall.plan.yearly.permonth` ·
`paywall.plan.yearly.savings` · `paywall.disclosure.selection` · `paywall.disclosure.autoRenew` ·
`paywall.account.status` (**not** `account.email` — the app has no email to print) · `paywall.restore` ·
`paywall.terms` · `paywall.privacy` · `paywall.offer.retry` · `paywall.retry` · `paywall.status` ·
`paywall.notice` · `paywall.offline` · `paywall.signin.sheet` / `.apple` / `.close` / `paywall.signin` /
`signin.emailEntry`.

**One difference to flag:** Feature's grep listed `paywall.disclosure.auto`; the README and the committed
source both say **`paywall.disclosure.autoRenew`**, which is what this doc uses.
