# Paywall Design Research — AI Pose Premium

> Research note for feat-011. Verified 2026-08-29 against Apple HIG IAP,
> App Review 3.1.2, DEC-008, and FEAT-011. Pricing frozen per DEC-008.
> Binding presentation spec: `docs/harness/plans/260826-0011-paywall-purchase-sandbox/design.md`.

---

## Audit of the 2026-08-28 research (this file, prior revision)

The previous mapping mixed valid Apple/RevenueCat principles with **wrong
product-model and layout conclusions**. Those conclusions shipped in
`paywall.html` / `paywall.css`. Corrected below.

| # | Claim in prior research | Verdict | Why |
| --- | --- | --- | --- |
| 1 | “Visible close button. Users must always be able to dismiss the paywall.” (L16–17, L26–27) | **Wrong HIG reading** | Apple’s IAP example *can* show Close. App Review does **not** require a skippable gate for a paid-access app. Hiding Close when the surface *is* dismissible is a dark pattern. DEC-008 leaves Splash dismissal TBD. Prototype Close stays 44pt and returns to source; it is not a “must skip paywall” product rule. |
| 2 | Calm/Duolingo freemium: “camera preview, Community browsing and Gallery browsing remain free” (L70–80, L93–94) | **Wrong product model** | DEC-008 / FEAT-011: paid-access, not a free core tier. Community library/detail/Try Pose and Gallery/detail/save/share are the paid scope. Copy must not invent a freemium promise. |
| 3 | “alternatives are compact 3-column grid” (L24, L55, L95, L136) | **Anti-pattern vs Apple + vs Direction A** | On 390px each column is ~114px. Price, cadence, and VN anchors wrap or clip. Apple 3.1.2(c) and HIG require the total billing price and duration to be clear *before* purchase. `prototype-research.md` already chose stacked Direction A; the 08-28 research reversed it. |
| 4 | Dual USD + “Vietnam planning anchor” on every consumer card (L57, L135) | **Misleading presentation** | StoreKit shows one localized price. Two currencies on one card reads as two charges. Locale belongs in prototype controls, not on the purchase surface. |
| 5 | Annual selected state = warm pink fill (L24, L54) | **Color-only + contrast** | HIG: do not convey selection by color alone. Pink wash on `#E89CAE` muddies term text. Selection = badge text + thick border + offset shadow. Pink is reserved for the single CTA. |
| 6 | “AI Pose’s freemium model” (L80) | **Contradicts DEC-008** | Explicitly a paid-access app. |
| 7 | Heading “One Premium. Four ways to pay.” (L55) | **Weak hierarchy** | Meta line, not a plan name or benefit. Replace with a visible “Choose a plan” legend. |
| 8 | Weekly equal weight in the 3-col grid | **Contradicts DEC-008** | Weekly is secondary and has a high annualized equivalent; period must be prominent, not a cramped third column. |
| 9 | Ad-hoc hex `#4f545d` / `#555b64` / `#3f444b` (L117) | **Token bypass** | Use `--nb-color-dark` / `--nb-color-gray`. |
| 10 | Checkmark character as structural icon in benefits | **Icon rule** | Use the sprite set (`icon-camera`, `icon-grid`, `icon-share`), not `✓`. |

Valid prior claims **kept**: restore required; Terms/Privacy required; annual default; single primary CTA; no trial/urgency; 44pt targets; sandbox states; no real purchase.

---

## 1. Apple Human Interface Guidelines — In-App Purchase

**Source:** [In-app purchase](https://developer.apple.com/design/human-interface-guidelines/in-app-purchase)

### Principles that survive verification

- Let people understand the app; the purchase surface should feel part of the product, not a bait-and-switch.
- Succinct product names. Display the **total billing price** and duration for every option.
- Auto-renewable subscriptions need clear period and renewal meaning.
- Provide a way to **restore** purchases (also StoreKit / App Review).
- App Review **3.1.2(c)**: before asking for a subscription, clearly describe what the user gets for the price; include functional Privacy Policy and Terms of Use (EULA) links; do not use misleading buttons or bait-and-switch.

### Not a mandate

- A Close control in Apple’s sample paywall is an example, not “users must always dismiss.” Paid-access hard gates are allowed. Dark pattern = hiding dismiss when dismiss is offered.

### Mapping (corrected)

| Apple rule | Design decision |
| --- | --- |
| Value + paid scope before purchase | Headline names the paid job. Three benefit rows = Community/Try Pose, Capture, Gallery save/share. |
| Clear price, duration, renewal | Stacked full-width plans. Annual shows `/ year` plus `$3.33/mo` equivalent. Weekly shows `/ week` plus honest yearly equivalent. Lifetime labeled one-time. |
| Restore + legal | Restore, Terms, Privacy always in the purchase dock. |
| Close when the flow is dismissible | 44pt header Close, not ghosted. Returns to `?return=` or referrer. |
| No misleading presentation | One locale on cards. No fake free tier. No urgency. No hidden price. |

---

## 2. RevenueCat guidance (hypotheses, not conversion guarantees)

Useful hypotheses: outcome headline, annual as default, one primary CTA, transparent “charged today / auto-renews / one-time,” less clutter.

**Not** a license to hide comparison prices. “Minimal variants” in RC blogs means reduce *cognitive* load, not shrink three prices into unread columns. AI Pose launches with four DEC-008 packages; all four stay visible and comparable.

| RC pattern | Design decision |
| --- | --- |
| Outcome headline | “The full pose camera.” |
| Annual default/hero | Pre-selected, Recommended badge, larger price, thick border + shadow. |
| Transparent pricing | Billed today + auto-renew until cancelled, or one-time, on the card and under the CTA. |
| Single CTA | Sticky dock. Pink only on that button. |

---

## 3. Real-app examples — what to copy vs discard

| Source | Keep | Discard for AI Pose |
| --- | --- | --- |
| Headspace | Outcome framing, cancel-in-settings reassurance | Not a template for layout |
| Calm / Duolingo | — | Freemium “what stays free” copy. Contradicts paid-access. |
| Notion pricing | Scannable price + cadence | Desktop 3-up grid does not fit 390px |

Honest prototype gate line (matches current HTML wiring, does not invent a free product):

> You can close this screen to keep looking. Capture, Community Try Pose, and Gallery save or share need Premium.

---

## 4. Accessibility and compliance

| Requirement | Implementation |
| --- | --- |
| Semantic HTML | `<header>`, `<main>`, `<section>`, `<h1>`–`<h2>`, `<ul>`, `<fieldset>` with visible `<legend>` |
| Keyboard | Native radios, CTA, restore, close, modal trap, Escape |
| Screen reader | `aria-live="polite"` plan announcement; Close `aria-label` |
| Touch | ≥ 44px (`--nb-touch-min`) |
| Focus | `*:focus-visible` in `base.css` |
| Contrast | Dark ink on cream; no pink fill behind body copy |
| Reduced motion | Spinner and confetti respect `prefers-reduced-motion` |
| Icons | SVG sprites, not emoji |

---

## 5. Frozen constraints

- Pricing unchanged (DEC-008).
- Neo-brutalism tokens in `tokens.css`. No new palette.
- Annual display price may exceed `--nb-font-size-2xl` (24px) as a **display-price** exception.
- Prototype controls: viewport, mock states, **locale USD/VND**.
- Offline. Simulated purchase only.
- States: default, loading, success, error, restore, unconfigured.

---

## 6. Binding layout (Direction A)

`prototype-research.md` Direction A (stacked chooser) is restored.

Rejected: Direction B (hidden prices), Direction C (extra step), and the 08-28 compact 3-column grid.

See `design.md` in this plan folder for the full presentation contract.
