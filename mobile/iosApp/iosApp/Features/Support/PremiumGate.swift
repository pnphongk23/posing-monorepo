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

/// Everything the capture decision reads, as one value.
///
/// A value (not a bag of parameters) so the decision is a pure function of exactly these six inputs,
/// every call site has to name them, and a new rule has an obvious place to add its input. `cameraReady`
/// is deliberately *not* here: readiness is the camera's answer, and the gate must be able to decide
/// before it is known.
struct PremiumGateInputs: Equatable {
    let paywallEnabled: Bool
    let purchasesConfigured: Bool
    let accountsAvailable: Bool
    let purchasesLinked: Bool
    let entitlement: PurchaseGatewayState
    let signedIn: Bool
}

/// The one place that decides whether a shutter press is a capture or a paywall.
///
/// Pure and total on purpose: the rule order *is* the product decision, so it is a table-driven unit
/// test instead of something only reachable through the camera UI.
///
/// The organising rule is **capture is fail-open**: losing a photo is worse than losing a sale, so
/// only a *confirmed* "this Account is not entitled" answer may show a paywall. Every state where the
/// app does not actually know (booting, offline, offering missing, the RevenueCat link never
/// completed, a provider error) lets the press through exactly as it did before the gate existed.
/// M01's fail-closed rule is untouched: a *purchase* still needs an entitlement and a configured SDK.
///
/// Rules, in order:
/// 1. **G1 — kill switch.** `paywall_enabled == false` → today's behaviour. Checked first so the
///    switch is a real rollback, not one flag among many.
/// 2. **G3 — can this build even sell?** No purchasable configuration (SDK key or entitlement id
///    missing/placeholder) **or** accounts switched off (`accounts_enabled_v2 == false`, and a
///    purchase needs a signed-in Account) → allow. A paywall nobody can complete would lock the
///    camera for good (risk R1, NFR-002).
/// 3. **G4 — signed out.** A known state, not an outage: the paywall opens with its sign-in prompt
///    (M2), because nobody could buy or restore anonymously.
/// 4. **G5 — access.** A live entitlement → allow.
/// 5. **G6 — is the provider context confirmed?** `purchasesLinked == false` means the RevenueCat
///    customer is not bound to this Account: a cold start still resolving, a failed link, or an
///    identity transition. That is "unknown", so allow. Without this, a subscriber whose cold-start
///    link failed would be paywalled by an outage.
/// 6. **G7 — confirmed or unknown answer.** Only `.notEntitled`, `.billingRetry`, `.expired` and
///    `.revoked` come from a successful entitlement fetch for the linked Account, so only those may
///    paywall. `.loading`, `.noOffering`, `.purchaseCancelled`, `.purchaseFailed`, `.signInRequired`
///    and anything else unknown → allow (see `PremiumGate.isConfirmedNotEntitled`).
///
/// `cameraReady` is consulted only *after* the outcome is already known to be a capture. That is the
/// point of the ordering: the gate must be reached before the camera-readiness and capture-error path
/// (`CameraCoordinator.onCaptureRequested()` → `captureError`), so an unentitled press asks for the
/// paywall even when the camera could not have produced a photo — which is what makes the flow
/// testable on a simulator that has no capture device (and why `shutterAcceptsPress` exists).
enum PremiumGate {
    static func captureOutcome(_ inputs: PremiumGateInputs, cameraReady: Bool) -> CaptureGateOutcome {
        // G1: the kill switch wins over every other input.
        guard inputs.paywallEnabled else { return allowed(cameraReady: cameraReady) }
        // G3: unconfigured purchases or no accounts → never lock the camera behind an unbuyable paywall.
        guard inputs.purchasesConfigured, inputs.accountsAvailable else { return allowed(cameraReady: cameraReady) }
        // G4: signed out is a confirmed state, and the paywall is how the user gets in.
        guard inputs.signedIn else { return .paywall(signIn: true) }
        // G5: access.
        if inputs.entitlement == .entitled { return allowed(cameraReady: cameraReady) }
        // G6: the provider context is not confirmed, so the answer below it means nothing yet.
        guard inputs.purchasesLinked else { return allowed(cameraReady: cameraReady) }
        // G7: only a confirmed "not entitled" answer may gate; everything else is fail-open.
        guard isConfirmedNotEntitled(inputs.entitlement) else { return allowed(cameraReady: cameraReady) }
        // G8: a confirmed, signed-in, unentitled Account.
        return .paywall(signIn: false)
    }

    /// States that a *successful* entitlement fetch produces when the Account has no access.
    ///
    /// Everything else is "we do not know": `.loading` (booting / a refresh that has not answered),
    /// `.noOffering` (the price list failed — unrelated to access), `.purchaseCancelled`,
    /// `.purchaseFailed` and `.signInRequired` (the outcomes of an attempt, not an answer about
    /// access) and `.unconfigured` (this build cannot sell). All of them must fail open.
    static func isConfirmedNotEntitled(_ state: PurchaseGatewayState) -> Bool {
        switch state {
        case .notEntitled, .billingRetry, .expired, .revoked:
            return true
        case .loading, .unconfigured, .noOffering, .entitled, .purchasePending,
             .purchaseCancelled, .purchaseFailed, .signInRequired:
            return false
        }
    }

    /// Whether the shutter control accepts a press.
    ///
    /// A `.paywall` answer stays pressable even when the camera is not ready (no permission, no
    /// hardware, a simulator): that press belongs to the gate, the camera never sees it, and hiding
    /// it behind readiness is exactly how the paywall became unreachable in the first place. The
    /// outcomes that would capture keep today's rule — readiness decides (`.capture` / `.unchanged`).
    static func shutterAcceptsPress(outcome: CaptureGateOutcome, isBusy: Bool) -> Bool {
        guard !isBusy else { return false }
        switch outcome {
        case .paywall, .capture: return true
        case .unchanged: return false
        }
    }

    /// Today's camera behaviour, unchanged: a ready camera captures, an unready one ignores the press.
    private static func allowed(cameraReady: Bool) -> CaptureGateOutcome {
        cameraReady ? .capture : .unchanged
    }
}

/// The one paywall sheet's presentation state (`FEAT-011` M1), owned by `AppFeatureRoot`.
///
/// Two rules, both pure so they are tested without a sheet:
///  - a press while the sheet is already up does not stack a second one;
///  - a confirmed entitlement arriving while the sheet is up closes it exactly once, and grants
///    nothing by itself: the camera becomes usable again, but the shutter is never fired for the
///    user (resuming the action silently would be a surprise purchase-follow-on).
struct PaywallPresentation: Equatable {
    private(set) var isPresented = false
    /// How many times this state closed the sheet on its own, so "exactly once" is provable and a
    /// second push for the same entitlement is a no-op.
    private(set) var automaticDismissals = 0

    enum Action: Equatable {
        /// The camera's gate answered `.paywall`.
        case shutterRequested
        /// The gate's inputs moved (entitlement push, session change).
        case gateSettled(entitlement: PurchaseGatewayState, signedIn: Bool)
        /// The user closed the sheet (swipe, or the paywall's close button).
        case userDismissed
    }

    mutating func send(_ action: Action) {
        switch action {
        case .shutterRequested:
            isPresented = true
        case .gateSettled(let entitlement, let signedIn):
            guard isPresented, signedIn, entitlement == .entitled else { return }
            isPresented = false
            automaticDismissals += 1
        case .userDismissed:
            isPresented = false
        }
    }
}
