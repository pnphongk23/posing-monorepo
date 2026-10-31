# BUG-PAY-18-01 (high) — signed out, the paywall's "Sign in to subscribe" CTA does nothing

**Build:** 1.1 (18), Debug-Dev, lane-2 `CF871F97`.
**Screen:** paywall, opened from the camera shutter while signed out (`-AIPosePaywallEnabled YES`, no session).
**Flows that hit it:** `TC-PAY-003-paywall-signin-prompt`, `TC-PAY-009-signin-apple-first` (both red).

## Steps

1. Clean launch with the paywall switch on, no stored session.
2. Camera → shutter → the paywall opens.
3. Tap the bottom CTA, which reads **"Sign in to subscribe"**.
4. Wait 15–20 s.

## Expected

The sign-in sheet opens (`paywall.signin.sheet`) with Apple → Google → email, so a signed-out user has a way
to start. That is the only actionable control on the surface when there are no prices yet.

## Actual

Nothing happens. No sheet, no error, no navigation — the paywall stays exactly as it was. The CTA is not
disabled: the hierarchy reports the element as

```
accessibilityText: "Sign in to subscribe"
resource-id:      paywall.cta
bounds:           [16,706][377,754]
enabled:          true
```

so it looks tappable, is reported as enabled, and swallows the press. The paywall's own signed-out pricing
state ("Price shown after you sign in", with `—` prices) leaves this CTA as the *only* way forward, so the
signed-out purchase path is a dead end: Close is the only control that works.

## Likely area (Feature lane; not fixed here)

`PaywallScreen.primaryAction()` → `guard model.isCTAEnabled else { return }` →
`guard model.isSignedIn else { showsSignInSheet = true }`, with the sheet attached via
`.sheet(isPresented: $showsSignInSheet)`. Either the sheet presentation is not surviving the paywall's
full-screen-cover host, or `primaryAction` is not being reached although the button reports itself enabled.

## Impact

- A signed-out user cannot reach sign-in from the paywall, so cannot subscribe at all.
- TC-PAY-003/009 cannot verify the 4.8 sign-in order until this is fixed; TC-PAY-016 (email sign-in from
  the paywall) is blocked by the same cause.

## Evidence

- `BUG-PAY-18-01-signedout-cta-dead-end.png` — paywall after the tap: still on the offer, no sheet.
- Probe artifact: `/Users/phamnhuphong/.maestro/tests/2026-11-01_033923` (hierarchy quoted above).
