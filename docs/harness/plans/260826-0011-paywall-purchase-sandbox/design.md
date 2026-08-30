# Paywall design spec (binding)

Date: 2026-08-29  
Lane: `feat/paywall-purchase`  
Status: prototype source of truth for presentation  
Pricing: DEC-008 (unchanged)

This file supersedes the compact 3-column / freemium mapping in
`docs/prototype/paywall-research.md` (2026-08-28). Compose `PaywallScreen`
does not exist in this worktree; native UI follows this spec when built.

## Product promise

AI Pose is a **paid-access** app (DEC-008 / FEAT-011), not a free-core
freemium product. Confirmed `premium` unlocks:

- Community pose library, pose detail, and Try Pose
- Capture
- Gallery, gallery detail, and PO-selected save/share

Preview contents and whether a hard paywall after Splash can be dismissed
remain TBD in DEC-008. Prototype Close returns to the prior screen so Capture
and Gallery gates have a way back. Close is **not** hidden. Close is also
**not** an Apple mandate that every paid-access gate must be skippable.

## Information hierarchy (compact 390×844)

1. Identity + Close (44×44pt, high contrast, not recessed)
2. Value: one outcome headline, three paid capabilities
3. Honest gate line: what Close still allows in this prototype vs what needs Premium
4. Four plans, all prices visible without tapping
5. One primary CTA with price and period
6. Restore, Terms, Privacy, and renewal/cancel copy

## Plans (DEC-008)

| Plan | Role | Default | Presentation |
| --- | --- | --- | --- |
| Annual `$39.99` / `₫999,000` | Recommended, best value | Pre-selected | Full-width hero card, equivalent `$3.33/mo`, Recommended badge + thick border + offset shadow (not color alone) |
| Monthly `$5.99` / `₫149,000` | Comparison anchor | No | Full-width row, same price type size as siblings except annual |
| Weekly `$1.99` / `₫49,000` | Secondary, never default | No | Full-width row, quieter chrome, period + honest annualized equivalent |
| Lifetime `$59.99` / `₫1,499,000` | One-time alternative | No | Separated by “Or pay once”, labeled one-time / does not renew |

Show **one** store locale at a time. Dual USD+VND on each consumer card is
forbidden (reads as two charges). Prototype controls may switch USD / VND
planning anchors. Production uses StoreKit localized price only.

## CTA and legal (Apple 3.1.2 + HIG IAP)

- One primary button. Label is a verb plus price plus period:
  `Subscribe for $39.99 / year` or `Buy lifetime for $59.99`.
- Directly under CTA: billed-today + auto-renew until cancelled (or one-time).
- Restore Purchases is always visible.
- Terms of Use and Privacy Policy are always visible.
- Subscriptions: name (Premium), duration, price, auto-renew, cancel in
  App Store settings, no trial.
- No countdown, fake scarcity, hidden price, pre-checked extras, or auto-enroll.

## Visual language

Neo-Brutalism of the existing prototype: cream canvas, 2px ink borders, hard
offset shadows, pastel pink **only** on the primary CTA, yellow on Recommended,
blue/green on benefit marks. Selection = thicker border + shadow + badge text,
not a pink wash over the annual card (that wash hides hierarchy and muddies
term contrast). Reuse `tokens.css`. Body/UI text uses `--nb-color-dark` /
`--nb-color-gray`, not ad-hoc hex.

## Layout

- Compact: stacked plans, scrolling body, sticky purchase dock so CTA/legal
  never clip.
- Tablet/desktop: story left, offer right; still stacked plans, never a
  3-column price grid.
- Touch targets ≥ 44px. Safe-area padding on header and dock.
- Keyboard: native radios, focus-visible, modal focus trap, Escape closes
  non-success dialogs.

## States

Ready, loading, purchase success, purchase error + retry, restore success,
unconfigured. Simulated purchase never grants a real entitlement. Sandbox
banner stays visible.

## Explicitly rejected

- Freemium copy from Calm/Duolingo (“browsing remains free” as a product promise)
- Compact 3-column monthly/weekly/lifetime grid on iPhone
- “Users must always dismiss the paywall” as a misread HIG rule
- Hiding Close, auto-scroll to CTA, or making Close a 12px ghost control
- Dual currency on the same card
- Emoji as structural icons
