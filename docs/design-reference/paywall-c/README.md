# Paywall — shipped layout (build 1.1 (20))

Source of truth for QA/Maestro: this paywall replaces the old body for **everyone**. There is no A/B
arm, no variant flag and no control layout — `paywall_enabled` is still the only switch (default off).

Artifacts here are **reference only** (downscaled, palettised):
- `variant-c-v2.png` — the approved target look (signed in).
- `variant-a-signed-out.png` — the signed-out idea: the same layout with the sign-in CTA.

Full-resolution mockups and the CRO handoff live outside the repo (`~/ai-pose-work/paywall-cro/`).
Screenshots of the shipped build: `/tmp/shots/PW/paywall-{light,dark,ax3,signed-out}.png` after running
`PaywallSnapshotTests`.

## Layout order (top → bottom)

| # | Block | Always on screen? | Notes |
|---|---|---|---|
| 1 | Hero photo (`paywallHeroC`), full bleed under the status bar | first frame | Height = clamp(0.28 × container, 180, 312) pt: 261 on a 6.7" phone, 187 on an iPhone SE. Carries a top scrim for the status bar and a fade into the page background at the bottom. No motion. |
| 2 | Close X, 44 pt, top-trailing | first frame, never delayed | The only way out (full-screen cover). |
| 3 | Headline: "Pick a pose." (ink) + "Match it. Shoot." (accent ink, own line) | first frame | Drawn as two fragments, so "Shoot." can never be a one-word orphan at 375 pt. |
| 4 | Three steps, numbered 1–3 | scrolls | 1 "Pick a pose" · "Browse and save poses for free." 2 "Match the outline" · "The guide shows on your live camera." 3 "Shoot" · "Premium unlocks the shutter with the full pose camera." Steps 1–2 are free, step 3 is paid. |
| 5 | Plan cards: Yearly (selected by default), Monthly | scrolls | Yearly carries "Save N%" (only when computable) and "… per month, billed {price} yearly". |
| 6 | Offer error card (only on load/purchase failure) | scrolls | Title + message + one action. |
| 7 | Renewal sentence: "Renews automatically until you cancel in Apple ID settings." | scrolls (pinned at AX via the dock) | Legal disclosure. |
| 8 | Legal row: Restore purchases · Terms of Use · Privacy Policy | **pinned in the dock** below the Accessibility sizes; at AX1–AX5 it moves into the scroll content (accepted deviation, same as before) | Never truncated, never painted over. |
| 9 | Status / outcome line (`paywall.status`) | scrolls | Cancelled/failed/entitled copy. |
| 10 | Pinned purchase region: helper line → CTA (48 pt) → legal row | **always** | The helper line and CTA never move off screen; only the content above scrolls. |

## Copy (verbatim)

- Headline: `Pick a pose.` / `Match it. Shoot.`
- Steps: see #4 above.
- Yearly card: title `Yearly`; badge `Save N%`; detail `{perMonth} per month, billed {price} yearly`; price `{price}`.
- Monthly card: title `Monthly`; detail `Billed monthly`; price `{price}`.
- Renewal: `Renews automatically until you cancel in Apple ID settings.`
- Helper line above the CTA: `{Yearly|Monthly} plan · {price} billed today`.
- CTA: `Unlock the pose camera` (signed in) / `Sign in to subscribe` (signed out) / `Try again` (after a
  failed purchase) / `Plans unavailable` (offering could not be read).
- Account line when no price is known yet: `Signed in. Premium follows your account.` /
  `Sign in first so Premium follows you.`
- Not in this screen: timers, scarcity, ratings, trial claims, hidden/delayed close, close-to-discount,
  motion.

## Plan-card rules

- Every figure comes from the store (`PurchaseProduct.localizedPrice`); **no price or percentage is
  typed in the code**. `PaywallMoney` derives the per-month figure and the saving from the two real
  prices; when they cannot be parsed the card degrades to "Billed yearly/monthly" and no badge.
- Yearly is preselected (the catalog order, not a constant in the view).
- Selecting a card updates the helper line above the CTA and emits `paywall_plan_select`.
- Signed out, the cards still show the **real** prices: the offering is read before sign-in. A
  purchase is still Account-bound — the CTA opens sign-in and never starts a guest purchase.

## States

| State | What is on screen | CTA |
|---|---|---|
| Signed in, offering ready | Hero, steps, both cards with real prices, renewal, pinned dock | `Unlock the pose camera` (enabled) |
| Signed out, prices loaded | Same cards with real prices; helper line = the selected plan | `Sign in to subscribe` → sign-in sheet (Apple, Google, email) |
| Signed out, prices not loaded yet | Cards keep their shape with "—" and "Price unavailable" | `Sign in to subscribe` |
| Offer failed / unavailable | Retry card (`paywall.offer.retry`), CTA disabled | `Plans unavailable` |
| Loading (signed in) | Skeleton cards, helper "Subscribe turns on when plans load." | `Unlock the pose camera` (disabled) |
| Offline | Offline banner on the cards, helper "Connect to the internet to subscribe." | disabled |
| Purchasing / restoring | CTA keeps its label with a spinner, disabled | — |
| Purchase cancelled | Status line "Purchase cancelled. No access was granted." | `Unlock the pose camera` |
| Purchase failed | Error card with `Try again` (`paywall.retry`), status line | `Try again` |
| Entitled | Status line "Premium access confirmed." (the cover then closes) | — |

## Accessibility identifiers (stable — write Maestro against these)

| Element | id | Value/state |
|---|---|---|
| Close X (44 pt) | `paywall.close` | — |
| Headline (combined) | — (label only) | — |
| Steps block | `paywall.steps` | — |
| Paid step (3 "Shoot") | `paywall.benefit` | — |
| Plan card — yearly | `paywall.plan.annual` | value `selected` / `not selected` (+ `isSelected` trait) |
| Plan card — monthly | `paywall.plan.monthly` | value `selected` / `not selected` |
| Yearly per-month line | `paywall.plan.yearly.permonth` | text `{perMonth} per month, billed {price} yearly` |
| Yearly saving badge | `paywall.plan.yearly.savings` | text `Save N%` (absent when not computable) |
| Helper line (purchase) | `paywall.disclosure.selection` | `{Plan} plan · {price} billed today`, or the offline/loading blocker copy |
| Account line | `paywall.account.status` | `Signed in. Premium follows your account.` / `Sign in first so Premium follows you.` (never an email — the app has none) |
| Renewal disclosure | `paywall.disclosure.autoRenew` | `Renews automatically until you cancel in Apple ID settings.` |
| CTA | `paywall.cta` | label = the CTA copy above |
| Restore | `paywall.restore` | — |
| Terms of Use | `paywall.terms` | — |
| Privacy Policy | `paywall.privacy` | — |
| Offer-load retry | `paywall.offer.retry` | inside the error card when the offering failed |
| Purchase/restore retry | `paywall.retry` | inside the error card after a failed purchase/restore (unchanged) |
| Status line | `paywall.status` | outcome copy |
| Offline banner | `paywall.offline` | — |
| Sign-in sheet | `paywall.signin.sheet` / `paywall.signin.apple` / `paywall.signin` / `signin.emailEntry` / `paywall.signin.close` | unchanged |
| Error card container | `paywall.notice` | — |

Notes for QA:
- The year card's id is still `paywall.plan.annual` (not `paywall.plan.yearly`) because existing flows
  drive it; the per-month and saving ids use the `yearly` wording that was requested.
- `paywall.benefit` now sits on step 3 (the only paid step) instead of the old single benefit row.
- The plan card is an accessibility **container**: tapping the card still targets the card id, and its
  selection is exposed as the accessibility value.

## Layout acceptance and its evidence

| Check | Evidence |
|---|---|
| iPhone SE 375×667, `.large`/`.xxxLarge`: CTA + legal row inside the frame, X painted | `PaywallScreenLayoutTests.testSEKeepsTheCloseCtaAndLegalRowInsideTheFrame`, `…testXXXLargeKeeps…` (pixel scan of the rendered frame) |
| AX1/AX3/AX5: CTA pinned and tappable, close visible, legal row moved into the scroll | `…testAccessibilitySizesKeepTheCtaPinnedAndMoveTheLegalRowIntoTheScroll`, `PaywallScreen.pinsLegalRow(at:)` |
| Status-bar glyphs ≥4.5:1 over the hero | `…testStatusBarScrimMeetsContrastInBothSchemes`, `…testScrimIsAppliedInBothSchemes` (worst rendered pixel per scheme) |
| Dark mode renders from the tokens | `…testDarkModePaintsTheDarkBackgroundToken` |
| Hero asset ships and paints | `…testHeroAssetIsBundledAndPainted` |
| No typed price | `…testNoPriceIsTypedIntoThePaywallView` + `PaywallModelTests.testFakeStorePricesDriveEveryRenderedFigure` |

Not covered here (needs a device run, Maestro's job): the real status bar under the notch, actual scroll
reachability of the AX legal row, VoiceOver order, and the visual check on a physical iPhone.
