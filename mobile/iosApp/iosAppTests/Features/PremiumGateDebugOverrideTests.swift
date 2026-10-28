import Combine
import XCTest
@testable import iosApp

private final class OverrideTokenStorage: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: SessionCredentials?

    init(credentials: SessionCredentials? = nil) {
        self.credentials = credentials
    }

    func saveCredentials(_ credentials: SessionCredentials) {
        lock.lock()
        self.credentials = credentials
        lock.unlock()
    }

    func loadCredentials() -> SessionCredentials? {
        lock.lock()
        defer { lock.unlock() }
        return credentials
    }

    func clearCredentials() {
        lock.lock()
        credentials = nil
        lock.unlock()
    }
}

/// What a placeholder-key build really looks like: the adapter stays `unconfigured` and never links.
@MainActor
private final class UnconfiguredReader: PurchaseSnapshotReading {
    private let subject = CurrentValueSubject<PurchaseSnapshot, Never>(
        PurchaseSnapshot(state: .unconfigured, products: [])
    )

    var snapshot: PurchaseSnapshot { subject.value }
    var snapshots: AnyPublisher<PurchaseSnapshot, Never> { subject.eraseToAnyPublisher() }
    var linkedAccountID: String? { nil }
}

/// A store that cannot sell: the paywall must say so instead of spinning or pretending.
@MainActor
private final class UnavailableStoreGateway: PurchaseGateway {
    private let subject = CurrentValueSubject<PurchaseSnapshot, Never>(
        PurchaseSnapshot(state: .unconfigured, products: [])
    )

    var snapshot: PurchaseSnapshot { subject.value }
    var snapshots: AnyPublisher<PurchaseSnapshot, Never> { subject.eraseToAnyPublisher() }
    private(set) var purchaseCount = 0
    private(set) var restoreCount = 0

    func loadOffering() async -> PurchaseSnapshot { snapshot }

    func purchase(packageID: String) async -> PurchaseSnapshot {
        purchaseCount += 1
        return snapshot
    }

    func restore() async -> PurchaseSnapshot {
        restoreCount += 1
        return snapshot
    }
}

private let overrideSession = SessionCredentials(accessToken: "access-a", refreshToken: "refresh-a")

/// `-AIPosePurchasesConfigured YES|NO` (Debug only): the QA precondition that makes the paywall
/// surface reachable on the placeholder-key Dev build, without faking any result.
///
/// The point of the packet is that this override changes *only* whether the gate believes a purchase
/// is possible. It must never grant access, never fabricate plans, and never leave the sheet spinning.
@MainActor
final class PremiumGateDebugOverrideTests: XCTestCase {
    private func makeGate(
        boundary: SessionBoundary,
        purchasesConfigured: @escaping () -> Bool?
    ) -> PremiumGateModel {
        PremiumGateModel(
            gateway: UnconfiguredReader(),
            boundary: boundary,
            paywallEnabled: { true },
            accountsAvailable: { true },
            purchasesConfiguredOverride: purchasesConfigured
        )
    }

    /// The Release shape (and the plain Debug shape without the argument): a placeholder build has no
    /// override, so G3 keeps capture free. This is the behaviour the override must be opt-in to.
    func testWithoutTheOverrideAPlaceholderBuildStillFailsOpen() async {
        let boundary = SessionBoundary(tokenStorage: OverrideTokenStorage(credentials: overrideSession))
        let model = makeGate(boundary: boundary, purchasesConfigured: { nil })
        model.start()
        await waitUntil("the session probe finished") { model.isSignedIn }

        XCTAssertFalse(model.purchasesConfigured)
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .capture)
    }

    /// `NO` is a real value, not "absent": the QA flow can also pin the fail-open path.
    func testForcedNotConfiguredKeepsCaptureFree() async {
        let boundary = SessionBoundary(tokenStorage: OverrideTokenStorage(credentials: overrideSession))
        let model = makeGate(boundary: boundary, purchasesConfigured: { false })
        model.start()
        await waitUntil("the session probe finished") { model.isSignedIn }

        XCTAssertFalse(model.purchasesConfigured)
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .capture)
    }

    /// TC-PAY-001/003: signed out + paywall on → the paywall opens on its sign-in state, on a build
    /// whose RevenueCat key is a placeholder.
    func testForcedConfiguredPutsASignedOutUserOnTheSignInPaywall() async {
        let boundary = SessionBoundary(tokenStorage: OverrideTokenStorage())
        let model = makeGate(boundary: boundary, purchasesConfigured: { true })
        model.start()
        await waitForSubscription(boundary)

        XCTAssertTrue(model.purchasesConfigured)
        XCTAssertEqual(model.captureOutcome(cameraReady: false), .paywall(signIn: true))
        XCTAssertTrue(
            PremiumGate.shutterAcceptsPress(
                outcome: model.captureOutcome(cameraReady: false),
                isBusy: false
            ),
            "the shutter has to reach the gate even with no capture device"
        )
    }

    /// Signed in without an entitlement → the paywall, not a capture and not a silent pass.
    func testForcedConfiguredPutsASignedInUnentitledUserOnThePaywall() async {
        let boundary = SessionBoundary(tokenStorage: OverrideTokenStorage(credentials: overrideSession))
        let model = makeGate(boundary: boundary, purchasesConfigured: { true })
        model.start()
        await waitUntil("the session probe finished") { model.isSignedIn }

        XCTAssertEqual(model.captureOutcome(cameraReady: true), .paywall(signIn: false))
    }

    /// The override states a precondition; it never becomes access. Only a real entitlement does.
    func testTheOverrideNeverGrantsAccess() async {
        let boundary = SessionBoundary(tokenStorage: OverrideTokenStorage(credentials: overrideSession))
        let model = makeGate(boundary: boundary, purchasesConfigured: { true })
        model.start()
        await waitUntil("the session probe finished") { model.isSignedIn }

        XCTAssertNotEqual(model.captureOutcome(cameraReady: true), .capture)
        XCTAssertEqual(model.entitlement, .unconfigured, "no snapshot was invented for the gate to read")
    }

    /// On such a build the paywall is reachable but honestly unbuyable: it settles in `unavailable`,
    /// a purchase does nothing, a restore is answered, and no spinner is left running.
    func testPurchaseOnAnUnconfiguredBuildFailsCleanly() async {
        let boundary = SessionBoundary(tokenStorage: OverrideTokenStorage(credentials: overrideSession))
        let gateway = UnavailableStoreGateway()
        let paywall = PaywallModel(gateway: gateway, boundary: boundary)

        paywall.start()
        await waitUntil("the paywall settled in its unavailable state") { isUnavailable(paywall) }

        XCTAssertTrue(paywall.plans.isEmpty, "no plan is fabricated for an unbuyable build")
        XCTAssertNil(paywall.selectedPlan)
        XCTAssertFalse(paywall.isBusy)
        XCTAssertNotNil(paywall.statusMessage, "the user is told the truth instead of facing a dead button")
        XCTAssertEqual(paywall.ctaTitle, "Plans unavailable")

        await paywall.purchase()
        XCTAssertEqual(gateway.purchaseCount, 0, "there is no plan to buy, so the store is never called")
        XCTAssertFalse(paywall.isBusy, "no stuck spinner")
        XCTAssertTrue(isUnavailable(paywall))

        await paywall.restore()
        XCTAssertEqual(gateway.restoreCount, 1, "restore is still offered, and answered")
        XCTAssertFalse(paywall.isBusy, "no stuck spinner after restore")
        XCTAssertTrue(isUnavailable(paywall))
        XCTAssertNotNil(paywall.statusMessage)
    }

    // MARK: - helpers

    private func isUnavailable(_ model: PaywallModel) -> Bool {
        if case .unavailable = model.phase { return true }
        return false
    }

    private func waitForSubscription(_ boundary: SessionBoundary, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await boundary.subscriberCountForTests() > 0 { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("the gate never subscribed to the session boundary")
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("timed out waiting for \(description)")
    }
}
