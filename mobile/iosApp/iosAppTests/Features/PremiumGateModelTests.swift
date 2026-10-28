import Combine
import XCTest
@testable import iosApp

private final class GateTokenStorage: TokenStoring, @unchecked Sendable {
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

/// The read-only face of the purchase gateway: no offering, no purchase, no store.
@MainActor
private final class FakeSnapshotReader: PurchaseSnapshotReading {
    private let subject: CurrentValueSubject<PurchaseSnapshot, Never>

    var snapshot: PurchaseSnapshot { subject.value }
    var snapshots: AnyPublisher<PurchaseSnapshot, Never> { subject.eraseToAnyPublisher() }

    init(_ state: PurchaseGatewayState) {
        subject = CurrentValueSubject(PurchaseSnapshot(state: state, products: []))
    }

    /// A push from the provider: a delegate update, a purchase, a link that finished.
    func publish(_ state: PurchaseGatewayState) {
        subject.send(PurchaseSnapshot(state: state, products: []))
    }
}

private let accountASession = SessionCredentials(accessToken: "access-a", refreshToken: "refresh-a")
private let accountBSession = SessionCredentials(accessToken: "access-b", refreshToken: "refresh-b")

/// The gate's live inputs: kill switches, the provider snapshot, and the account-scoped entitlement.
///
/// The important cases here are the *session* ones. The provider's snapshot for a new identity always
/// lands a moment later, and FEAT-011 NFR-001 says Account A's entitlement must never stand in for B's
/// access in that gap — which is exactly what the `SessionScoped` reset exists to prevent. Those tests
/// therefore keep the fake reporting `.entitled` across the session change on purpose.
@MainActor
final class PremiumGateModelTests: XCTestCase {
    private func makeModel(
        reader: FakeSnapshotReader,
        boundary: SessionBoundary,
        paywallEnabled: @escaping () -> Bool = { true },
        accountsAvailable: @escaping () -> Bool = { true }
    ) -> PremiumGateModel {
        PremiumGateModel(
            gateway: reader,
            boundary: boundary,
            paywallEnabled: paywallEnabled,
            accountsAvailable: accountsAvailable
        )
    }

    func testStartMirrorsTheProviderSnapshotAndTheStoredSession() async {
        let boundary = SessionBoundary(tokenStorage: GateTokenStorage(credentials: accountASession))
        let reader = FakeSnapshotReader(.entitled)
        let model = makeModel(reader: reader, boundary: boundary)

        model.start()
        await waitUntil("the session probe finished") { model.isSignedIn }

        XCTAssertEqual(model.entitlement, .entitled)
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .capture)
    }

    func testSignedOutUserIsGatedEvenWhileTheSnapshotSaysEntitled() async {
        let boundary = SessionBoundary(tokenStorage: GateTokenStorage())
        let reader = FakeSnapshotReader(.entitled)
        let model = makeModel(reader: reader, boundary: boundary)

        model.start()
        // The probe resolves to "no stored session"; nothing else moves.
        await waitForSubscription(boundary)
        XCTAssertFalse(model.isSignedIn)
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .paywall(signIn: true))
    }

    func testProviderPushesGrantAndRevokeAccess() async {
        let boundary = SessionBoundary(tokenStorage: GateTokenStorage(credentials: accountASession))
        let reader = FakeSnapshotReader(.notEntitled)
        let model = makeModel(reader: reader, boundary: boundary)
        model.start()
        await waitUntil("the session probe finished") { model.isSignedIn }
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .paywall(signIn: false))

        reader.publish(.entitled)
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .capture)

        reader.publish(.billingRetry)
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .paywall(signIn: false))
    }

    /// Mutation target: remove the `resetForSessionChange` body and this test goes red. The fake keeps
    /// reporting `.entitled` after the sign-out, so only the session-scoped reset can close the gate —
    /// which is the requirement: access must not depend on the provider's timing.
    func testSignOutDropsEntitlementBeforeTheProviderPushes() async {
        let boundary = SessionBoundary(tokenStorage: GateTokenStorage(credentials: accountASession))
        let reader = FakeSnapshotReader(.entitled)
        let model = makeModel(reader: reader, boundary: boundary)
        model.start()
        await waitUntil("the session probe finished") { model.isSignedIn }
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .capture)
        await waitForSubscription(boundary)

        await boundary.signOut()
        await waitUntil("the sign-out reached the gate") { !model.isSignedIn }

        XCTAssertEqual(model.entitlement, .notEntitled, "the previous session's access is dropped")
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .paywall(signIn: true))
        XCTAssertEqual(reader.snapshot.state, .entitled, "the provider has not pushed anything yet")
    }

    /// NFR-001: another Account on the same device is not entitled just because the last one was.
    func testAnotherAccountDoesNotInheritThePreviousAccountsEntitlement() async {
        let storage = GateTokenStorage(credentials: accountASession)
        let boundary = SessionBoundary(tokenStorage: storage)
        let reader = FakeSnapshotReader(.entitled)
        let model = makeModel(reader: reader, boundary: boundary)
        model.start()
        await waitUntil("the session probe finished") { model.isSignedIn }
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .capture)
        await waitForSubscription(boundary)

        await boundary.signOut()
        await waitUntil("A signed out") { !model.isSignedIn }
        await boundary.saveCredentials(accountBSession)
        await waitUntil("B signed in") { model.isSignedIn }

        // B's own link/refresh has not answered yet; the stale provider snapshot says `.entitled`.
        XCTAssertEqual(reader.snapshot.state, .entitled)
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .paywall(signIn: false))
    }

    /// G3: a build that cannot sell (placeholder entitlement id, no SDK key) must not lock the camera.
    func testUnconfiguredPurchasesAllowCapture() async {
        let boundary = SessionBoundary(tokenStorage: GateTokenStorage(credentials: accountASession))
        let reader = FakeSnapshotReader(.unconfigured)
        let model = makeModel(reader: reader, boundary: boundary)
        model.start()
        await waitUntil("the session probe finished") { model.isSignedIn }

        XCTAssertFalse(model.purchasesConfigured)
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .capture)
    }

    /// The kill switches are read at tap time: a late Firestore fetch (`paywall_enabled`) or the
    /// accounts switch flipping must change the next press without rebuilding anything.
    func testKillSwitchesAreReadAtDecisionTime() async {
        let boundary = SessionBoundary(tokenStorage: GateTokenStorage(credentials: accountASession))
        let reader = FakeSnapshotReader(.notEntitled)
        var paywallOn = false
        var accountsOn = true
        let model = makeModel(
            reader: reader,
            boundary: boundary,
            paywallEnabled: { paywallOn },
            accountsAvailable: { accountsOn }
        )
        model.start()
        await waitUntil("the session probe finished") { model.isSignedIn }

        XCTAssertEqual(model.captureOutcome(cameraReady: true), .capture, "G1: paywall disabled")

        paywallOn = true
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .paywall(signIn: false))

        accountsOn = false
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .capture, "G3: nobody could buy")
    }

    /// G3 has to survive the session reset: a build that cannot sell (placeholder entitlement id, no
    /// SDK key) must stay open after a sign-out/sign-in, or the camera locks behind a paywall that
    /// nobody could ever complete.
    func testUnconfiguredBuildStaysOpenAcrossASessionChange() async {
        let storage = GateTokenStorage(credentials: accountASession)
        let boundary = SessionBoundary(tokenStorage: storage)
        let reader = FakeSnapshotReader(.unconfigured)
        let model = makeModel(reader: reader, boundary: boundary)
        model.start()
        await waitUntil("the session probe finished") { model.isSignedIn }
        await waitForSubscription(boundary)

        await boundary.signOut()
        await waitUntil("A signed out") { !model.isSignedIn }
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .capture)

        await boundary.saveCredentials(accountBSession)
        await waitUntil("B signed in") { model.isSignedIn }
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .capture)
    }

    // MARK: - helpers

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
