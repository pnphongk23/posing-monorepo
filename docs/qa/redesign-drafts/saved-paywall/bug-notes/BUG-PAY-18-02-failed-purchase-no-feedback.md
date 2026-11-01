# BUG-PAY-18-02 (medium) — a failed purchase leaves the paywall silent

> **Status: FIXED in `821bd71`** — a failed purchase now renders the notice card as the settled outcome:
> its headline carries `paywall.status` ("The purchase didn't go through") and its **Try again** is
> `paywall.retry` (wired to the same purchase); a failed *restore* keeps its own copy and inline retry, and a
> **cancelled** purchase stays deliberately silent — no card, no retry. **Verify on dev19** with
> TC-PAY-012 (failure → Try again → fresh attempt) and TC-PAY-013 (cancel → silence, no access).

**Build:** 1.1 (18), Debug-Dev, lane-2 `CF871F97`, account B (never entitled), Test Store dialog.
**Screen:** paywall, plans loaded (real prices: "US$6,67 per month, billed US$79,99 yearly", "Save 33%").
**Flow:** `TC-PAY-012-purchase-failed`.

## Steps

1. Sign in as account B, open the camera, tap the shutter → paywall with both plans.
2. Tap `paywall.cta` ("Subscribe").
3. In the RevenueCat Test Store dialog choose **Test failed purchase**.
4. Wait up to 60 s.

## Expected

`paywall.status` reports the failure ("Purchase could not be completed. Try again.") and no access is
granted, per `PaywallModel.statusMessage` for `.purchaseFailed` and board `11-board08`.

## Actual

No banner appears at all: `paywall.status` never becomes visible, and the paywall sits on the ready state
with the plans still selectable. The user pressed Subscribe, the purchase failed, and the app says nothing —
the failure is indistinguishable from "nothing happened".

Contrast: the **cancelled** path in the same session works (`TC-PAY-013` passes: "Purchase cancelled. No
access was granted."), so the banner host itself is fine; the failed-purchase path is what loses the state.

## Impact

- A real store failure (card declined, network, store error) would be silent on this surface.
- TC-PAY-012 cannot pass until the failure produces its banner.

## Evidence

- `BUG-PAY-18-02-failed-purchase-no-banner.png` — paywall right after "Test failed purchase": plans still
  shown, no banner.
- Artifact: `~/.maestro/tests/2026-11-01_04*` for `TC-PAY-012-purchase-failed` (the run that produced it).
