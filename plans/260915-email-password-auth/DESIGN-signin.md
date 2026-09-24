# DESIGN — Email/password sign-in (Stream S1)

Companion to `PLAN.md` (binding contract). Produced with `.agents/skills/app-design/SKILL.md`.
Author: Bàng Thống (Specialist Lead, S1). Date: 260915.

## 1. Dominant goal

**The user comes here to get back into their account with the email and password they already have.**

Secondary, never primary: choose Google instead. Nothing else lives on this surface — no sign-up,
no reset, no account management (all explicit non-goals).

## 2. Convention evidence

| Source | Adopted principle |
|---|---|
| Apple HIG — *Text fields*, *Entering data* | Use a secure field for passwords; validate at a sensible time (email on submit/blur, not per keystroke). |
| Apple HIG — *Sign in with Apple* | "Ask people to sign in only in exchange for value", "delay sign-in as long as possible" → the surface is still reached only from a gate or the Account screen. |
| web.dev — *Sign-in form best practices* | `autocomplete=current-password`, an explicit show/hide control, never obscure the field/CTA with the keyboard. |
| In-repo prototype `docs/prototype/screens/sign-in-prompt.html` | The existing prompt copy and button order are already the product's sign-in language; email is added *under* Google, not above it. |
| In-repo `Features/Poses/PosesFeature.swift:786-830` (`.nb-search-field`) | The app's only existing text-input chrome: black 2pt border, no offset shadow, 44pt minimum row. |
| Apple HIG — *Motion / accessibility* | Purposeful motion only, with a reduced-motion alternative. |

**Limitation, stated honestly:** Mobbin (the skill's preferred research surface) is not available in
this environment, and no external screenshots were captured. Evidence above is platform
documentation plus in-repo conventions (`references/mobbin-research.md` procedure not run).

## 3. Information hierarchy, destination relationship, Back

```
[Back]  Sign in with email                     <- NeoSubscreenHeader, 44pt back target
        View your saved poses.                 <- the interrupted intent, one line, subtext
        ┌ Email address ─────────────────┐
        └────────────────────────────────┘     <- 2pt border, 12pt radius, min 44pt, no shadow
        ┌ Password ──────────────  Show ┐
        └────────────────────────────────┘
        [ error card — only when an error exists ]
        [        Sign in       ]                <- NeoButtonStyle, the single primary action
        Use Google instead                      <- peer option, text action, stays peer
```

Presentation: **a `.sheet` (detents `.large`) hosting `EmailSignInScreen`**, not the existing
overlay modal. Rationale from the skill's decision rules — "use a separate context for a
self-contained task; use a sheet for a short interruption": two fields plus a keyboard plus an
error region is a self-contained task, and the 9-line popup (`SignInPromptView`) cannot hold it
without the keyboard covering the CTA. The overlay prompt is kept for what it is good at: a
one-line interruption with one primary action.

Destination relationship — the two entry points and what Back returns to:

1. **Gate interruption** (Saved poses `PosesFeature.swift:1159`, paywall `.signInRequired`): the
   shared prompt gains a secondary "Sign in with email" under `ContinueWithGoogleButton`. Opening
   the sheet does **not** consume the `SignInIntent`; cancelling returns to the originating screen
   with the gate still pending, exactly like today's "Not now". Only a real success calls
   `onResolved(intent)`.
2. **Account screen** (`signedOutCard`, `SupportScreens.swift`): the sheet is presented directly;
   Back returns to the signed-out card, and success arrives through the existing
   `SessionBoundary` `.signedIn` event — no new navigation state.

Back behaviour: explicit labelled Back control in the header (labelled "Back" for VoiceOver),
swipe-down, and interactive dismiss all mean "cancel". Dismiss is disabled only while a request is
in flight (`interactiveDismissDisabled`), matching the guard `SignInPromptView.dismiss()` already
has; the header Back stays enabled and cancels the in-flight task. Typed input is **not** persisted
across presentations — a silently remembered password on a shared device is a worse failure than
retyping.

## 4. Smallest visual system (existing tokens only — no second visual language)

* Colour: only `AIPoseColor` members — `background`, `surface`, `surfaceVariant`, `foreground`,
  `subtext`, `error`, `errorSurface`, `primary`.
* Spacing: only `AIPoseSpacing` (`xs…xxl`). Radii: 12pt (cards/fields/buttons) — no new radii.
* Type: semantic system styles only (`.title2.bold` header, `.body` field text, `.subheadline`
  intent line, `.footnote.weight(.semibold)` inline errors). No fixed `size:` on text.
* Chrome: 2pt `foreground` border on every bordered surface (field, card, button) — the existing
  neo-brutalist rule. Fields carry **no offset shadow**: in this system the hard 4pt shadow marks
  *raised/actionable* surfaces (`NeoButtonStyle`, `neoCard`, paywall cards), and `FeatureStateView`
  already establishes that an input-like well is flat. Buttons reuse `NeoButtonStyle` unchanged.
* Error region: reuse `FeatureStateView(tone: .error)` — it already owns the error surface fill,
  the alert/assertive announcement and the 10pt `empty-state.css` geometry. No new error component.

## 5. State lifecycle

| State | Behaviour |
|---|---|
| initial | Both fields blank, primary CTA disabled, no error card. Email focused? No — auto-focusing raises the keyboard over the intent line on first paint; focus follows the user's tap. |
| loading | CTA shows `ProgressView` + "Signing in…", fields `.disabled`, header Back cancels the task. |
| content | Both fields non-empty → CTA enabled. |
| empty | As *initial*: CTA disabled + the intent line explains why the screen exists. |
| error | 401 `INVALID_CREDENTIALS` → "Incorrect email or password." (one message for unknown email **and** wrong password); 403 → "Confirm your email address."; 429 → "Too many attempts. Try again in a few minutes."; 503/other → `ErrorCopy.text(for:)`; `URLError` → the URL error's own text. Rendered in `FeatureStateView(tone: .error)`, input preserved so the user only fixes the wrong field. |
| offline | Same error region; copy from `URLError` (e.g. "The Internet connection appears to be offline."), CTA re-enabled immediately — no spinner left running. |
| long content | At accessibility sizes the body scrolls and the CTA sits in a dock pinned above the safe area (the paywall dock precedent); the error card uses `fixedSize(horizontal: false, vertical: true)` so it wraps instead of truncating. |
| interruption | Backgrounding or a call dismisses the focused field but does not clear typed input; the request completes and its result renders when the user returns. |

## 6. Motion and reduced motion

Only one custom transition: the error card fades in (`.easeOut(0.18)`) so a failed attempt reads as a
state *change* rather than a silent repaint. Reduced motion
(`@Environment(\.accessibilityReduceMotion)`) drops the animation and renders the card instantly —
the text and its assertive announcement carry the meaning either way. The spinner is the platform
`ProgressView`, so it is not custom motion and needs no alternative.

## 7. Accessibility

* Dynamic Type: semantic fonts throughout; no fixed text sizes; fields are `minHeight 44`, so the
  hit target does not shrink at small text sizes.
* Targets: ≥44pt for Back, the Sign in CTA, "Use Google instead", and the Show/Hide password toggle.
* Contrast: `foreground` #121212 on `surface`/`background` ≈ 17:1; `subtext` #6B7280 on white
  ≈ 4.8:1 (passes AA for body text). **Residual, disclosed:** `AIPoseColor.error` #EE4848 on
  `errorSurface` #FFF4F5 ≈ 3.5:1 is below AA for small text — this is inherited from the existing
  system and is not introduced here; mitigation is that the error card's *title* stays
  `foreground` black, so the actionable meaning is never carried by the red text alone.
* VoiceOver: fields labelled "Email address" / "Password"; password toggle has a label and a value
  ("shown"/"hidden"); error card announces assertively via `FeatureStateView`; Back is labelled
  "Back"; successful sign-in is announced by the screen it returns to, not by a silent dismissal.
* Autofill: `textContentType(.username)` / `.password`, `keyboardType(.emailAddress)`,
  `.textInputAutocapitalization(.never)`, `.autocorrectionDisabled()` — so a password manager can
  fill both fields and the demo credentials can be pasted.

## 8. Deliberately rejected

1. **Keeping email inside the 9-line modal popup** — the PO's explicit objection; keyboard covers
   the CTA and the error card does not fit.
2. **A new visual language** (gradient hero, glass, mixed neutrals, circular avatars) — the app has
   one neo-brutalist system; a second one on the auth screen would read as a different product.
3. **"Forgot password?" link** — reset is a deferred non-goal; a control that cannot work is worse
   than its absence.
4. **Per-keystroke inline validation** — HIG says validate at a sensible time; premature "invalid
   email" while typing is hostile. Field-level validation runs on submit only.
5. **Distinguishing "no such account" from "wrong password"** — anti-enumeration is a backend
   contract; the UI shows one message for both.
6. **Sign in with Apple / biometric unlock** — out of scope, and the reviewer path must stay email.
7. **Persisting the typed email between presentations** — small convenience, but it leaks the last
   user's identity on a shared device.
