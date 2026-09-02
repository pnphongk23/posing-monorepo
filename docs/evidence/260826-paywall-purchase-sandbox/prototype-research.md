# FEAT-011 paywall prototype research brief

Date: 2026-08-26  
Artifact: static HTML/CSS/JS prototype only  
Target: iOS-like compact viewport first, with continuous resize behavior

## Brief

The user is deciding whether AI Pose's paid-access promise feels clear, trustworthy,
and native to the existing product before any RevenueCat implementation begins.
The dominant journey is: encounter a premium gate → understand what premium unlocks
and how billing works → compare plans → select one → see a safe simulated result or
recover from an error. The prototype must not make a real purchase or imply that a
placeholder key is connected.

## Existing product evidence

- Existing prototype lives in `docs/prototype/` and is a static HTML/CSS/JS app.
- Current visual language is Neo-Brutalism: cream canvas, dark 2px borders, hard
  offset shadows, pastel pink/blue/yellow/green accents, uppercase tracked labels,
  and 44px minimum touch targets.
- Compose theme corroborates the same semantic palette: `AiPoseColors` and
  `AiPoseTypography`; the prototype should reuse the existing web tokens instead of
  inventing a second visual language.
- DEC-008 pricing: weekly `$1.99 / ₫49k`, monthly `$5.99 / ₫149k`, annual
  `$39.99 / ₫999k` highlighted/default, lifetime `$59.99 / ₫1,499k` one-time.
- One access level is represented: entitlement `premium`.

## Research findings

1. Apple HIG says people should experience an app before purchasing, the shopping
   experience should feel integrated with the app, product names/descriptions should
   be succinct, and the total billing price should be displayed for every purchase.
2. Apple recommends a range of durations and clear subscription terms; an annual
   option can be visually selected, but the prototype must not hide the recurring
   nature of weekly/monthly/annual plans.
3. Apple StoreKit guidance says users expect non-consumables and auto-renewable
   subscriptions to be available across devices and provides a visible restore path.
4. RevenueCat models a paywall as an Offering containing Packages; the paywall can
   select a package while entitlement activation remains a separate access concern.
5. Error and unavailable states need recovery copy. A static prototype should make
   loading, purchase success, purchase failure, restore success, and unconfigured
   SDK states reproducible without exposing production controls.

## Design directions considered

### A — Annual-led stacked chooser (recommended)

One scrollable paywall with a short value header, benefit list, three subscription
cards in order annual/monthly/weekly, a distinct lifetime alternative, then one
primary CTA and quiet restore/legal actions. Best for comparison and the existing
mobile prototype; the risk is vertical density on compact screens.

### B — Annual hero with a compact plan switcher

Annual occupies a larger hero card and monthly/weekly/lifetime are revealed in a
segmented control. Best for a strong single conversion story; the risk is hiding
price context and making comparison slower.

### C — Feature-first editorial paywall

Large benefit blocks lead into a bottom-sheet plan picker. Best for onboarding after
Splash; the risk is a longer path from a Capture gate and weaker price transparency.

Choose A for this prototype because it supports direct comparison, keeps all four
prices visible, and matches the established card/shadow language.

**2026-08-29 correction:** The 08-28 `docs/prototype/paywall-research.md` shipped a
compact 3-column monthly/weekly/lifetime grid that **violates Direction A** and
hides cadence on a 390px iPhone. That layout is withdrawn. Binding spec:
`design.md` in this folder. Freemium Calm/Duolingo mapping in the same research
file is also withdrawn; DEC-008 is paid-access.

## Prototype acceptance criteria

- `docs/prototype/screens/paywall.html` is reachable from the prototype and works
  without network dependencies.
- Annual is selected by default and visibly labeled as recommended/best value using
  text plus border/shape, not color alone; monthly shows its monthly anchor, weekly
  is secondary, and lifetime is labeled one-time.
- Every option displays a total price and billing cadence in plain language.
- Purchase, restore, terms, privacy, close/back, and plan selection are keyboard and
  touch operable; primary controls have at least 44px effective targets and visible
  focus treatment.
- Fixture states are reproducible with the prototype controls/query state: default,
  loading, purchase-error with retry, purchase-success, restore-success, and
  unconfigured/offline.
- Prototype is tested at 390×844, 834×1112, and 1440×900, plus a narrow resized
  viewport; no horizontal overflow or clipped legal/CTA content.
- No RevenueCat SDK, real key, network purchase, or production entitlement is added.

## Sources

- Apple HIG — In-app purchase: https://developer.apple.com/design/human-interface-guidelines/in-app-purchase
- Apple — Auto-renewable subscriptions: https://developer.apple.com/app-store/subscriptions/
- Apple — Offering, completing, and restoring in-app purchases: https://developer.apple.com/documentation/StoreKit/offering-completing-and-restoring-in-app-purchases
- RevenueCat — Offerings and Packages: https://www.revenuecat.com/docs/offerings/overview
- RevenueCat — Restoring purchases: https://www.revenuecat.com/docs/getting-started/restoring-purchases
- RevenueCat — Entitlements: https://www.revenuecat.com/docs/getting-started/entitlements
