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
    /// `nil` models a cold start whose RevenueCat link has not finished — or has failed. Mutable so a
    /// test can drive the coordinator's sequence: clear to `nil`, then link the next Account.
    var linkedAccountID: String?

    init(_ state: PurchaseGatewayState, linkedAccountID: String? = "account-a") {
        subject = CurrentValueSubject(PurchaseSnapshot(state: state, products: []))
        self.linkedAccountID = linkedAccountID
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

        XCTAssertEqual(model.entitlement, .loading, "access is dropped to UNKNOWN, not to a confirmed no")
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .paywall(signIn: true))
        XCTAssertEqual(reader.snapshot.state, .entitled, "the provider has not pushed anything yet")
        XCTAssertEqual(
            reader.linkedAccountID,
            "account-a",
            "signed out is local: the stale link must not change the sign-in paywall"
        )
    }

    /// P1 (the review's bug): a subscriber switches accounts, and the provider has not pushed anything
    /// yet — the link still names the previous Account. Reading that as a confirmed "no" paywalled the
    /// new Account for an answer that was never about it. Unknown is not a "no": capture proceeds.
    func testAccountSwitchBeforeTheProviderPushesFailsOpen() async {
        let boundary = SessionBoundary(tokenStorage: GateTokenStorage(credentials: accountASession))
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

        // The provider still reports A's entitled snapshot and A's link; nothing about B is known.
        XCTAssertEqual(reader.linkedAccountID, "account-a")
        XCTAssertEqual(reader.snapshot.state, .entitled)
        XCTAssertEqual(
            model.captureOutcome(cameraReady: true),
            .capture,
            "an answer that belongs to the previous session must not gate the new one"
        )
    }

    /// The confirmation half of the fix (P1): a push that arrives *after* the session change but before
    /// the coordinator's clear lands is still the previous Account's answer, delivered under the previous
    /// Account's link. It must not gate the new session — a subscriber who switched accounts was being
    /// paywalled by exactly this.
    func testAStaleAnswerAfterTheSessionChangeDoesNotGateTheNewAccount() async {
        let boundary = SessionBoundary(tokenStorage: GateTokenStorage(credentials: accountASession))
        let reader = FakeSnapshotReader(.notEntitled)
        let model = makeModel(reader: reader, boundary: boundary)
        model.start()
        await waitUntil("the session probe finished") { model.isSignedIn }
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .paywall(signIn: false))
        await waitForSubscription(boundary)

        await boundary.signOut()
        await waitUntil("A signed out") { !model.isSignedIn }
        await boundary.saveCredentials(accountBSession)
        await waitUntil("B signed in") { model.isSignedIn }

        // A late refresh for A lands before `clearAccount()`: the link and the answer are both A's.
        XCTAssertEqual(reader.linkedAccountID, "account-a")
        reader.publish(.notEntitled)

        XCTAssertEqual(
            model.captureOutcome(cameraReady: true),
            .capture,
            "an answer delivered under the previous Account's link must not gate the new session"
        )

        // Once the context has been cleared, the same answer is B's own and may gate.
        reader.linkedAccountID = nil
        reader.publish(.notEntitled)
        reader.linkedAccountID = "account-b"
        reader.publish(.notEntitled)

        XCTAssertEqual(model.captureOutcome(cameraReady: true), .paywall(signIn: false))
    }

    /// The state itself must be unknown after a session change, never a confirmed negative: that is the
    /// half of the fix a mutation of the reset line has to break.
    func testSessionChangeResetsToAnUnknownStateNotAConfirmedNo() async {
        let boundary = SessionBoundary(tokenStorage: GateTokenStorage(credentials: accountASession))
        let reader = FakeSnapshotReader(.notEntitled)
        let model = makeModel(reader: reader, boundary: boundary)
        model.start()
        await waitUntil("the session probe finished") { model.isSignedIn }
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .paywall(signIn: false))
        await waitForSubscription(boundary)

        await boundary.signOut()
        await waitUntil("A signed out") { !model.isSignedIn }
        await boundary.saveCredentials(accountBSession)
        await waitUntil("B signed in") { model.isSignedIn }

        XCTAssertEqual(
            model.entitlement,
            .loading,
            "a session change makes the answer unknown; a confirmed no is only ever a provider answer"
        )
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .capture)
    }

    /// Once the provider context has been cleared and B's own answer has landed, the gate uses it: B is
    /// not entitled → the paywall, for B's own confirmed reason.
    func testAnotherAccountIsGatedOnlyAfterItsOwnConfirmedAnswer() async {
        let boundary = SessionBoundary(tokenStorage: GateTokenStorage(credentials: accountASession))
        let reader = FakeSnapshotReader(.entitled)
        let model = makeModel(reader: reader, boundary: boundary)
        model.start()
        await waitUntil("the session probe finished") { model.isSignedIn }
        await waitForSubscription(boundary)

        await boundary.signOut()
        await waitUntil("A signed out") { !model.isSignedIn }
        await boundary.saveCredentials(accountBSession)
        await waitUntil("B signed in") { model.isSignedIn }

        // The coordinator's clearAccount() lands (the context is empty), then B is linked and answers.
        reader.linkedAccountID = nil
        reader.publish(.notEntitled)
        reader.linkedAccountID = "account-b"
        reader.publish(.notEntitled)

        XCTAssertEqual(
            model.captureOutcome(cameraReady: true),
            .paywall(signIn: false),
            "B's own confirmed answer may gate"
        )
    }

    /// And when B's own answer is `.entitled`, the same sequence captures — NFR-001 in the other
    /// direction: the gate follows the current session's answer, not the previous one's.
    func testAnotherAccountWithItsOwnConfirmedEntitlementCaptures() async {
        let boundary = SessionBoundary(tokenStorage: GateTokenStorage(credentials: accountASession))
        let reader = FakeSnapshotReader(.notEntitled)
        let model = makeModel(reader: reader, boundary: boundary)
        model.start()
        await waitUntil("the session probe finished") { model.isSignedIn }
        await waitForSubscription(boundary)

        await boundary.signOut()
        await waitUntil("A signed out") { !model.isSignedIn }
        await boundary.saveCredentials(accountBSession)
        await waitUntil("B signed in") { model.isSignedIn }

        reader.linkedAccountID = nil
        reader.publish(.notEntitled)
        reader.linkedAccountID = "account-b"
        reader.publish(.entitled)

        XCTAssertEqual(model.captureOutcome(cameraReady: true), .capture)
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

    // MARK: - Outages fail open (P1-b)

    /// The subscriber's cold-start link failed, so RevenueCat never bound the Account and the
    /// adapter's `.notEntitled` is not an answer about *this* user's access. Capture must proceed:
    /// losing a photo is worse than losing a sale.
    func testFailedColdStartLinkIsAnOutageNotANo() async {
        let boundary = SessionBoundary(tokenStorage: GateTokenStorage(credentials: accountASession))
        let reader = FakeSnapshotReader(.notEntitled, linkedAccountID: nil)
        let model = makeModel(reader: reader, boundary: boundary)
        model.start()
        await waitUntil("the session probe finished") { model.isSignedIn }

        XCTAssertEqual(model.captureOutcome(cameraReady: true), .capture)
        XCTAssertEqual(model.captureOutcome(cameraReady: false), .unchanged, "still today's camera rule")
    }

    /// Boot / a refresh still in flight is not a "no" either.
    func testAnUnresolvedSnapshotFailsOpen() async {
        let boundary = SessionBoundary(tokenStorage: GateTokenStorage(credentials: accountASession))
        let reader = FakeSnapshotReader(.loading)
        let model = makeModel(reader: reader, boundary: boundary)
        model.start()
        await waitUntil("the session probe finished") { model.isSignedIn }

        XCTAssertEqual(model.captureOutcome(cameraReady: true), .capture)
    }

    /// A failed price-list fetch says nothing about access.
    func testMissingOfferingDoesNotGate() async {
        let boundary = SessionBoundary(tokenStorage: GateTokenStorage(credentials: accountASession))
        let reader = FakeSnapshotReader(.noOffering)
        let model = makeModel(reader: reader, boundary: boundary)
        model.start()
        await waitUntil("the session probe finished") { model.isSignedIn }

        XCTAssertEqual(model.captureOutcome(cameraReady: true), .capture)
    }

    /// The outage path is not a permanent free pass: once a successful fetch confirms the answer, the
    /// gate uses it.
    func testConfirmedAnswerGatesAfterAnOutage() async {
        let boundary = SessionBoundary(tokenStorage: GateTokenStorage(credentials: accountASession))
        let reader = FakeSnapshotReader(.loading)
        let model = makeModel(reader: reader, boundary: boundary)
        model.start()
        await waitUntil("the session probe finished") { model.isSignedIn }
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .capture)

        reader.publish(.notEntitled)
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .paywall(signIn: false))

        reader.publish(.expired)
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .paywall(signIn: false))
    }

    /// The shutter's enabled state reads the gate, so the gate has to announce its moves: a purchase
    /// that lands while the user is back on the camera must re-enable the control.
    func testGateUpdatesAnnounceEntitlementMoves() async {
        let boundary = SessionBoundary(tokenStorage: GateTokenStorage(credentials: accountASession))
        let reader = FakeSnapshotReader(.notEntitled)
        let model = makeModel(reader: reader, boundary: boundary)
        var fired = 0
        let cancellable = model.gateUpdates.sink { _ in fired += 1 }
        model.start()
        await waitUntil("the session probe finished") { model.isSignedIn }

        fired = 0
        reader.publish(.entitled)

        XCTAssertEqual(fired, 1)
        XCTAssertEqual(model.captureOutcome(cameraReady: true), .capture)
        withExtendedLifetime(cancellable) {}
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
