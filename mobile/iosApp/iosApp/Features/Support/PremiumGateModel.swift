import Combine
import Foundation

/// The gate's one collaborator: `PremiumGate.captureOutcome(...)` over live inputs.
///
/// The camera depends on this instead of on `AppConfig` + the purchase SDK, so its capture path can
/// be driven by a fake in `CameraFeatureTests` without a store, a session or a network.
@MainActor
protocol PremiumGateProviding: AnyObject {
    /// Pure decision over the current inputs. `cameraReady` is the camera's own readiness, which the
    /// gate deliberately consults last (see `PremiumGate`).
    func captureOutcome(cameraReady: Bool) -> CaptureGateOutcome
}

/// Read-only side of the purchase gateway: everything the gate needs, nothing it could misuse.
@MainActor
protocol PurchaseSnapshotReading: AnyObject {
    var snapshot: PurchaseSnapshot { get }
    var snapshots: AnyPublisher<PurchaseSnapshot, Never> { get }
}

/// The live implementation already published both members for the paywall.
extension RevenueCatAdapter: PurchaseSnapshotReading {}

/// Live inputs for `PremiumGate`, and the one piece of account-scoped state the gate needs.
///
/// **Why this is its own model.** The camera should not have to know about the kill switches, the
/// RevenueCat snapshot or the session boundary; and the entitlement must be readable synchronously
/// from a shutter tap (a gate that awaited the SDK would let the press through while it waited).
///
/// **Why `SessionScoped`.** Entitlement is per Account (NFR-001), and the provider's own snapshot for
/// a new identity arrives a turn after the session changes. Until it does, the mirrored state is the
/// previous Account's. Adopting the scope resets it inside the same main-actor turn that delivers the
/// session event, so no shutter tap can read Account A's access while B (or nobody) is signed in.
/// The reset is what makes the gate independent of the provider's timing — see
/// `PremiumGateModelTests.testSignOutDropsEntitlementBeforeTheProviderPushes`.
@MainActor
final class PremiumGateModel: ObservableObject, PremiumGateProviding, SessionScoped {
    /// Last provider snapshot state. `.loading` until the gateway reports something: an unresolved
    /// entitlement is not access, so the gate reads it as "not entitled".
    @Published private(set) var entitlement: PurchaseGatewayState = .loading
    @Published private(set) var isSignedIn = false

    private let gateway: any PurchaseSnapshotReading
    private let boundary: SessionBoundary
    private let scope: SessionScope
    private let paywallEnabled: () -> Bool
    private let accountsAvailable: () -> Bool
    private var cancellable: AnyCancellable?
    private var startTask: Task<Void, Never>?

    init(
        gateway: any PurchaseSnapshotReading = RevenueCatAdapter.shared,
        boundary: SessionBoundary = ServiceLocator.sessionBoundary,
        paywallEnabled: @escaping () -> Bool = { AppConfig.shared.isPaywallEnabled },
        accountsAvailable: @escaping () -> Bool = { AppConfig.shared.isAccountFeatureEnabled }
    ) {
        self.gateway = gateway
        self.boundary = boundary
        self.scope = SessionScope.of(boundary)
        self.paywallEnabled = paywallEnabled
        self.accountsAvailable = accountsAvailable
    }

    /// Idempotent. Call once from the app root; the camera only reads `captureOutcome`.
    func start() {
        guard cancellable == nil else { return }
        entitlement = gateway.snapshot.state
        cancellable = gateway.snapshots.sink { [weak self] snapshot in
            self?.entitlement = snapshot.state
        }
        // Adoption is what subscribes the reset; the boundary itself is not replayed, so the current
        // session is read once here (the same convergence rule every other projection follows).
        scope.adopt(self)
        startTask = Task { [weak self] in
            guard let self else { return }
            let signedIn = await self.boundary.hasStoredSession()
            guard !Task.isCancelled else { return }
            self.isSignedIn = signedIn
        }
    }

    /// The kill switches are read at decision time, not cached: `paywall_enabled` can arrive on a late
    /// Firestore fetch, and a stale copy would keep the gate locked (or open) after the switch flipped.
    var purchasesConfigured: Bool {
        // `unconfigured` is the adapter's own "cannot sell from this build" answer (missing SDK key
        // or entitlement id, both of which fail closed at launch).
        entitlement != .unconfigured
    }

    func captureOutcome(cameraReady: Bool) -> CaptureGateOutcome {
        PremiumGate.captureOutcome(
            paywallEnabled: paywallEnabled(),
            purchasesConfigured: purchasesConfigured,
            accountsAvailable: accountsAvailable(),
            entitlement: entitlement,
            signedIn: isSignedIn,
            cameraReady: cameraReady
        )
    }

    // MARK: - Session scope

    /// Account-derived state dies with the session. `signedIn` is re-armed on `.signedIn` because the
    /// boundary tells us the new session exists; the previous session's access is never inherited —
    /// the provider's link + refresh decides that, and until it lands the gate fails closed.
    ///
    /// `.unconfigured` is preserved on purpose: it is not "no access", it is "this build cannot
    /// sell" (placeholder entitlement id / missing SDK key). Downgrading it to `.notEntitled` on a
    /// sign-in would re-enable the gate and lock the camera behind a paywall nobody can complete —
    /// exactly what rule G3 exists to prevent.
    func resetForSessionChange(_ event: SessionEvent) {
        isSignedIn = (event == .signedIn)
        if entitlement != .unconfigured {
            entitlement = .notEntitled
        }
    }
}
