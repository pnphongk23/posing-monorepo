import Foundation

/// What one shutter press means now that capture is the paid action (`FEAT-011` M1).
///
/// Exactly three outcomes, because the camera had exactly two behaviours before the gate existed:
/// take the photo, or do nothing (the shutter is disabled / the coordinator refuses the request).
/// `.paywall` is the third one, and `signIn` records the gate's own answer to "does this user also
/// have to sign in before they could buy?" (`FEAT-011` M2 — a purchase is account-bound).
enum CaptureGateOutcome: Equatable {
    /// Hand the press to the camera's capture path, which still owns readiness and capture errors.
    case capture
    /// Ignore the press: today's behaviour when the camera is not ready.
    case unchanged
    /// The paid action: ask for the paywall instead of capturing.
    case paywall(signIn: Bool)
}

/// The one place that decides whether a shutter press is a capture or a paywall.
///
/// Pure and total on purpose: the rule order *is* the product decision, so it is a table-driven unit
/// test instead of something only reachable through the camera UI. The order matters more than any
/// individual rule:
///
/// 1. **G1 — kill switch.** `paywall_enabled == false` → the press behaves exactly as it did before
///    the feature existed. Checked first so the switch is a real rollback, not one flag among many.
/// 2. **G3 — can this build even sell?** No purchasable configuration (SDK key or entitlement id
///    missing/placeholder) **or** accounts switched off (`accounts_enabled_v2 == false`, and a
///    purchase needs a signed-in Account) → allow. A paywall nobody can complete would lock the
///    camera for good, and "never lose the photo" outranks monetization (risk R1, NFR-002). This is
///    also the offline/kill-switch rule: an unroutable purchase degrades to today's behaviour.
/// 3. **G4 — access.** A live entitlement **and** a signed-in Account → allow. Both halves are
///    required: a snapshot alone is not proof of access for the current session (NFR-001).
/// 4. **G6 — everything else** → paywall. `.loading` / `.purchasePending` included: an unresolved
///    entitlement is not access.
///
/// `cameraReady` is consulted only *after* the outcome is already known to be a capture. That is the
/// point of the ordering: the gate must be reached before the camera-readiness and capture-error
/// path (`CameraCoordinator.onCaptureRequested()` → `captureError`), so an unentitled press asks for
/// the paywall even when the camera could not have produced a photo — which is what makes the flow
/// testable on a simulator that has no capture device.
enum PremiumGate {
    static func captureOutcome(
        paywallEnabled: Bool,
        purchasesConfigured: Bool,
        accountsAvailable: Bool,
        entitlement: PurchaseGatewayState,
        signedIn: Bool,
        cameraReady: Bool
    ) -> CaptureGateOutcome {
        // G1: the kill switch wins over every other input.
        guard paywallEnabled else { return allowed(cameraReady: cameraReady) }
        // G3: unconfigured purchases or no accounts → never lock the camera behind an unbuyable paywall.
        guard purchasesConfigured, accountsAvailable else { return allowed(cameraReady: cameraReady) }
        // G4: an entitlement only counts for the session that holds it.
        if entitlement == .entitled, signedIn { return allowed(cameraReady: cameraReady) }
        // G6: signed out still shows the paywall, so the gate can say why (sign-in prompt, M2).
        return .paywall(signIn: !signedIn)
    }

    /// Today's camera behaviour, unchanged: a ready camera captures, an unready one ignores the press.
    private static func allowed(cameraReady: Bool) -> CaptureGateOutcome {
        cameraReady ? .capture : .unchanged
    }
}
